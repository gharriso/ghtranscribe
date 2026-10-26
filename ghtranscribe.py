#!/usr/bin/env python3
"""
Transcribe and summarize a Just Press Record voice memo.

Usage:
    ghtranscribe.py                  # most recent recording
    ghtranscribe.py <file.m4a>       # specific file (path or bare filename
                                      # searched for inside the JPR folder)
    ghtranscribe.py --force <file>   # redo even if outputs already exist

Pipeline:
    1. whisperx transcribes the audio, then diarize.py labels speakers
       (pyannote, on the GPU; skipped with a warning if it fails).
    2. The transcript is sent to a local Ollama model for a summary
       + notable observations.
    3. Transcript and summary are written next to the source recording,
       along with a PDF of the summary.
    4. The summary is saved as a new Apple Note.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
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
WHISPER_MODEL = os.environ.get("WHISPERX_MODEL", "large-v3")
OLLAMA_MODEL = os.environ.get("GHTRANSCRIBE_OLLAMA_MODEL", "gpt-oss:latest")

DIARIZE = os.environ.get("GHTRANSCRIBE_DIARIZE", "1") != "0"
DIARIZE_SCRIPT = Path(__file__).resolve().parent / "diarize.py"
MIN_SPEAKERS = os.environ.get("GHTRANSCRIBE_MIN_SPEAKERS")
MAX_SPEAKERS = os.environ.get("GHTRANSCRIBE_MAX_SPEAKERS")

SUMMARY_PROMPT = (
    "You are given the transcript of a recorded conversation. "
    "Write a clear, well-organized summary covering the main topics discussed "
    "and any decisions or action items. "
    "Then add a short section titled 'Observations' with any comments you "
    "think are worthwhile -- e.g. open questions, risks, inconsistencies, or "
    "follow-ups the speakers may have missed.\n\n"
    "If the transcript labels speakers (Speaker 1, Speaker 2, ...), attribute "
    "points, decisions and action items to the speaker responsible. Where the "
    "conversation makes it clear who a speaker is (a name, or a role such as "
    "doctor or patient), say so once and refer to them that way.\n\n"
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


def ensure_downloaded(audio: Path) -> None:
    """Force iCloud Drive to materialize the file locally.

    Just Press Record recordings live on iCloud Drive and can still be
    cloud-only placeholders. Reading such a file with ffmpeg (as whisperx
    does) can fail with "Resource deadlock avoided" instead of triggering
    a download the way Finder/NSFileCoordinator would.
    """
    subprocess.run(["brctl", "download", str(audio)], check=False)


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
        "--compute_type", "float32",
        "--output_dir", str(out_dir),
        "--output_format", "json",
    ]

    attempts = 3
    for attempt in range(1, attempts + 1):
        ensure_downloaded(audio)
        print(f"Running whisperx on {audio.name} (model={WHISPER_MODEL}, attempt {attempt}/{attempts}) ...")
        result = subprocess.run(cmd, env=env)
        if result.returncode == 0:
            break
        if attempt == attempts:
            result.check_returncode()
        wait = 15 * attempt
        print(f"whisperx failed (likely still downloading from iCloud); retrying in {wait}s ...")
        time.sleep(wait)

    json_path = out_dir / f"{audio.stem}.json"
    if not json_path.exists():
        sys.exit(f"Expected whisperx output not found: {json_path}")
    return json_path


def run_diarization(audio: Path, json_path: Path) -> None:
    """Add speaker labels to the whisperx JSON in place.

    Failures are logged and swallowed: an unlabeled transcript is better than
    the watcher retrying (and failing) the same recording every minute.
    """
    venv_python = Path(WHISPERX_BIN).with_name("python3")
    cmd = [str(venv_python), str(DIARIZE_SCRIPT), str(audio), str(json_path)]
    if MIN_SPEAKERS:
        cmd += ["--min-speakers", MIN_SPEAKERS]
    if MAX_SPEAKERS:
        cmd += ["--max-speakers", MAX_SPEAKERS]

    env = os.environ.copy()
    env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
    result = subprocess.run(cmd, env=env)
    if result.returncode != 0:
        print(
            f"Warning: diarization failed (exit {result.returncode}); "
            "continuing without speaker labels.",
            file=sys.stderr,
        )


def format_timestamp(seconds: float) -> str:
    return str(timedelta(seconds=int(seconds)))


def build_transcript(json_path: Path) -> str:
    data = json.loads(json_path.read_text())
    segments = data.get("segments", [])

    # pyannote labels speakers SPEAKER_00, SPEAKER_01, ... in no useful
    # order; renumber them by first appearance.
    speaker_names: dict[str, str] = {}
    for seg in segments:
        label = seg.get("speaker")
        if label and label not in speaker_names:
            speaker_names[label] = f"Speaker {len(speaker_names) + 1}"

    # Merge consecutive segments from the same speaker into one turn.
    turns: list[tuple[float | None, str | None, list[str]]] = []
    for seg in segments:
        text = (seg.get("text") or "").strip()
        if not text:
            continue
        speaker = speaker_names.get(seg.get("speaker"))
        if turns and speaker and turns[-1][1] == speaker:
            turns[-1][2].append(text)
        else:
            turns.append((seg.get("start"), speaker, [text]))

    lines = []
    for start, speaker, texts in turns:
        ts = format_timestamp(start) if start is not None else "?"
        prefix = f"{speaker}: " if speaker else ""
        lines.append(f"[{ts}] {prefix}{' '.join(texts)}")

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


def output_paths(audio: Path) -> tuple[Path, Path]:
    base = audio.with_suffix("")
    transcript_path = base.with_name(base.name + "_transcript.txt")
    summary_path = base.with_name(base.name + "_summary.txt")
    return transcript_path, summary_path


def save_outputs(audio: Path, transcript: str, summary: str) -> tuple[Path, Path]:
    transcript_path, summary_path = output_paths(audio)
    transcript_path.write_text(transcript)
    summary_path.write_text(summary)
    return transcript_path, summary_path


def pdf_path(audio: Path) -> Path:
    return audio.with_name(audio.stem + "_summary.pdf")


PDF_CSS = """
@page { size: A4; margin: 18mm 15mm; }
body { font-family: -apple-system, "Helvetica Neue", Helvetica, sans-serif;
       font-size: 10.5pt; line-height: 1.4; }
table { border-collapse: collapse; width: 100%; margin: 0.8em 0; }
th, td { border: 1px solid #bbb; padding: 4px 6px; vertical-align: top; }
th { background: #eee; }
"""


def note_html(title: str, summary_markdown: str) -> str:
    return f"<b>{title}</b><br><br>" + markdown_to_html(summary_markdown)


def create_summary_pdf(path: Path, title: str, summary_markdown: str) -> None:
    """Render the Apple Note's HTML to a PDF via weasyprint.

    Failures are logged and swallowed so a PDF problem never blocks the note.
    """
    weasyprint = Path(WHISPERX_BIN).with_name("weasyprint")
    # gpt-oss likes narrow no-break spaces ("10 Oct"), which the PDF
    # fonts have no glyph for and render as nothing.
    summary_markdown = summary_markdown.replace(" ", " ")
    html = (
        f"<!doctype html><html><head><meta charset='utf-8'><title>{title}</title>"
        f"<style>{PDF_CSS}</style></head><body>"
        + note_html(title, summary_markdown)
        + "</body></html>"
    )
    env = os.environ.copy()
    # weasyprint needs Homebrew's pango/cairo, which macOS won't find by default.
    env["DYLD_FALLBACK_LIBRARY_PATH"] = (
        "/opt/homebrew/lib:" + env.get("DYLD_FALLBACK_LIBRARY_PATH", "")
    )
    result = subprocess.run(
        [str(weasyprint), "-", str(path)], input=html, text=True, env=env
    )
    if result.returncode != 0:
        print(
            f"Warning: PDF creation failed (exit {result.returncode}).",
            file=sys.stderr,
        )
    else:
        print(f"Saved summary PDF to {path}")


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
    # A prior AppleEvent timeout can still leave the note created server-side
    # even though the call reports failure, so skip creation if a note with
    # this exact title already exists rather than risk a duplicate.
    script = """
    on run argv
        set theTitle to item 1 of argv
        set theBody to item 2 of argv
        with timeout of 180 seconds
            tell application "Notes"
                tell account "iCloud"
                    if not (exists (notes of folder "Notes" whose name is theTitle)) then
                        make new note at folder "Notes" with properties {name:theTitle, body:theBody}
                    end if
                end tell
            end tell
        end timeout
    end run
    """
    html_body = note_html(title, summary_markdown)
    subprocess.run(
        ["osascript", "-e", script, title, html_body],
        check=True,
    )


def process_recording(audio: Path, force: bool = False) -> None:
    transcript_path, summary_path = output_paths(audio)

    if not force and transcript_path.exists() and summary_path.exists():
        print(f"Reusing existing transcript/summary for {audio.name}")
        summary = summary_path.read_text()
    else:
        print(f"Using recording: {audio}")

        with tempfile.TemporaryDirectory() as tmp:
            json_path = run_whisperx(audio, Path(tmp))
            if DIARIZE:
                run_diarization(audio, json_path)
            transcript = build_transcript(json_path)

        if not transcript.strip():
            sys.exit("Transcription produced no text; aborting.")

        summary = summarize_with_ollama(transcript)

        transcript_path, summary_path = save_outputs(audio, transcript, summary)
        print(f"Saved transcript to {transcript_path}")
        print(f"Saved summary to {summary_path}")

    note_title = f"Voice memo summary - {audio.parent.name} {audio.stem}"
    create_summary_pdf(pdf_path(audio), note_title, summary)
    create_apple_note(note_title, summary)
    print(f"Created Apple Note: {note_title}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "audio", nargs="?", help="Recording to process (path or filename). "
        "Defaults to the most recent recording in Just Press Record."
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Re-transcribe and re-summarize even if outputs already exist.",
    )
    args = parser.parse_args()

    audio = resolve_audio_arg(args.audio) if args.audio else find_most_recent_recording()
    process_recording(audio, force=args.force)


if __name__ == "__main__":
    main()
