#!/usr/bin/env python3
"""
Add speaker labels to a whisperx JSON transcript.

Usage:
    diarize.py <audio> <whisperx.json> [--min-speakers N] [--max-speakers N]

Runs pyannote speaker diarization (via whisperx's wrapper) and rewrites the
JSON in place with a "speaker" key on each segment and word. Invoked by
ghtranscribe.py as a separate process under the venv's python, so the main
script stays stdlib-only and a diarization crash can't take it down.

Runs on Apple Silicon's GPU (mps) when available: diarization is far too
slow on CPU, while whisperx's transcription step (ctranslate2) can't use
mps at all -- hence diarization lives here instead of whisperx --diarize.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

HF_TOKEN_FILE = Path("~/.ghtranscribe/hf_token").expanduser()
DIARIZE_MODEL = os.environ.get(
    "GHTRANSCRIBE_DIARIZE_MODEL", "pyannote/speaker-diarization-community-1"
)


def hf_token():
    token = os.environ.get("HUGGINGFACE_TOKEN") or os.environ.get("HF_TOKEN")
    if token:
        return token
    if HF_TOKEN_FILE.exists():
        return HF_TOKEN_FILE.read_text().strip()
    # Fall back to whatever `hf auth login` cached.
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio")
    parser.add_argument("json_path")
    parser.add_argument("--min-speakers", type=int)
    parser.add_argument("--max-speakers", type=int)
    args = parser.parse_args()

    import torch
    import whisperx
    from whisperx.diarize import DiarizationPipeline, assign_word_speakers

    device = os.environ.get("GHTRANSCRIBE_DIARIZE_DEVICE") or (
        "mps" if torch.backends.mps.is_available() else "cpu"
    )
    json_path = Path(args.json_path)
    result = json.loads(json_path.read_text())

    started = time.monotonic()
    print(f"Diarizing on {device} ({DIARIZE_MODEL}) ...")
    pipeline = DiarizationPipeline(model_name=DIARIZE_MODEL, token=hf_token(), device=device)
    audio = whisperx.load_audio(args.audio)
    diarize_df = pipeline(
        audio, min_speakers=args.min_speakers, max_speakers=args.max_speakers
    )
    result = assign_word_speakers(diarize_df, result)

    speakers = sorted({s["speaker"] for s in result["segments"] if s.get("speaker")})
    print(
        f"Diarization found {len(speakers)} speaker(s) "
        f"in {time.monotonic() - started:.0f}s"
    )
    json_path.write_text(json.dumps(result, default=float))


if __name__ == "__main__":
    sys.exit(main())
