#!/usr/bin/env python3
"""
Transcribe and summarize a Just Press Record voice memo.

Usage:
    ghtranscribe.py                  # most recent recording
    ghtranscribe.py <file.m4a>       # specific file (path or bare filename
                                      # searched for inside the JPR folder)

Pipeline:
    1. whisperx transcribes the audio (no speaker diarization yet).
    2. The transcript is sent to a local Ollama model for a summary
       + notable observations.
    3. Transcript and summary are written next to the source recording.
    4. The summary is saved as a new Apple Note.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from datetime import timedelta
from pathlib import Path

JPR_DIR = Path(
    "~/Library/Mobile Documents/iCloud~com~openplanetsoftware~just-press-record/Documents"
).expanduser()

AUDIO_EXTS = {".m4a", ".wav", ".mp3", ".caf"}


def _default_whisperx_bin() -> str:
    venv_bin = Path(__file__).resolve().parent / ".venv" / "bin" / "whisperx"
    if venv_bin.exists():
        return str(venv_bin)
    on_path = shutil.which("whisperx")
    if on_path:
        return on_path
    return str(Path("~/.conda_envs/s385/bin/whisperx").expanduser())


WHISPERX_BIN = os.environ.get("WHISPERX_BIN", _default_whisperx_bin())
WHISPER_MODEL = os.environ.get("WHISPERX_MODEL", "medium")
OLLAMA_MODEL = os.environ.get("GHTRANSCRIBE_OLLAMA_MODEL", "gpt-oss:latest")

SUMMARY_PROMPT = (
    "You are given the transcript of a recorded conversation. "
    "Write a clear, well-organized summary covering the main topics discussed "
    "and any decisions or action items. "
    "Then add a short section titled 'Observations' with any comments you "
    "think are worthwhile -- e.g. open questions, risks, inconsistencies, or "
    "follow-ups the speakers may have missed.\n\n"
    "Transcript:\n\n{transcript}"
)


def find_most_recent_recording() -> Path:
    candidates = [
        p for p in JPR_DIR.rglob("*") if p.suffix.lower() in AUDIO_EXTS and p.is_file()
    ]
    if not candidates:
        sys.exit(f"No recordings found under {JPR_DIR}")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def resolve_audio_arg(arg: str) -> Path:
    p = Path(arg).expanduser()
    if p.is_file():
        return p
    matches = list(JPR_DIR.rglob(p.name))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        sys.exit(
            f"Multiple recordings named '{p.name}' found under {JPR_DIR}:\n"
            + "\n".join(str(m) for m in matches)
        )
    sys.exit(f"Could not find recording '{arg}' (checked as given, and under {JPR_DIR})")


def run_whisperx(audio: Path, out_dir: Path) -> Path:
    env = os.environ.copy()
    env["DYLD_FALLBACK_LIBRARY_PATH"] = (
        "/opt/homebrew/lib:" + env.get("DYLD_FALLBACK_LIBRARY_PATH", "")
    )
    env["KMP_DUPLICATE_LIB_OK"] = "TRUE"

    cmd = [
        WHISPERX_BIN,
        str(audio),
        "--model", WHISPER_MODEL,
        "--device", "cpu",
        "--output_dir", str(out_dir),
        "--output_format", "json",
    ]
    print(f"Running whisperx on {audio.name} (model={WHISPER_MODEL}) ...")
    subprocess.run(cmd, env=env, check=True)

    json_path = out_dir / f"{audio.stem}.json"
    if not json_path.exists():
        sys.exit(f"Expected whisperx output not found: {json_path}")
    return json_path


def format_timestamp(seconds: float) -> str:
    return str(timedelta(seconds=int(seconds)))


def build_transcript(json_path: Path) -> str:
    data = json.loads(json_path.read_text())
    segments = data.get("segments", [])

    lines = []
    for seg in segments:
        text = (seg.get("text") or "").strip()
        if not text:
            continue
        ts = format_timestamp(seg.get("start")) if seg.get("start") is not None else "?"
        lines.append(f"[{ts}] {text}")

    return "\n\n".join(lines)


OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")


def summarize_with_ollama(transcript: str) -> str:
    prompt = SUMMARY_PROMPT.format(transcript=transcript)
    print(f"Sending transcript to ollama ({OLLAMA_MODEL}) for summarization ...")
    payload = json.dumps({
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
    }).encode()
    req = urllib.request.Request(
        f"{OLLAMA_HOST}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    return data["response"].strip()


def save_outputs(audio: Path, transcript: str, summary: str) -> tuple[Path, Path]:
    base = audio.with_suffix("")
    transcript_path = base.with_name(base.name + "_transcript.txt")
    summary_path = base.with_name(base.name + "_summary.txt")
    transcript_path.write_text(transcript)
    summary_path.write_text(summary)
    return transcript_path, summary_path


def markdown_to_html(text: str) -> str:
    result = subprocess.run(
        ["pandoc", "-f", "gfm", "-t", "html"],
        input=text,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def create_apple_note(title: str, summary_markdown: str) -> None:
    script = """
    on run argv
        set theTitle to item 1 of argv
        set theBody to item 2 of argv
        tell application "Notes"
            tell account "iCloud"
                make new note at folder "Notes" with properties {name:theTitle, body:theBody}
            end tell
        end tell
    end run
    """
    html_body = f"<b>{title}</b><br><br>" + markdown_to_html(summary_markdown)
    subprocess.run(
        ["osascript", "-e", script, title, html_body],
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "audio", nargs="?", help="Recording to process (path or filename). "
        "Defaults to the most recent recording in Just Press Record."
    )
    args = parser.parse_args()

    audio = resolve_audio_arg(args.audio) if args.audio else find_most_recent_recording()
    print(f"Using recording: {audio}")

    with tempfile.TemporaryDirectory() as tmp:
        json_path = run_whisperx(audio, Path(tmp))
        transcript = build_transcript(json_path)

    if not transcript.strip():
        sys.exit("Transcription produced no text; aborting.")

    summary = summarize_with_ollama(transcript)

    transcript_path, summary_path = save_outputs(audio, transcript, summary)
    print(f"Saved transcript to {transcript_path}")
    print(f"Saved summary to {summary_path}")

    note_title = f"Voice memo summary - {audio.parent.name} {audio.stem}"
    create_apple_note(note_title, summary)
    print(f"Created Apple Note: {note_title}")


if __name__ == "__main__":
    main()
