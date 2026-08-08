#!/usr/bin/env python3
"""
Watch the Just Press Record folder for new recordings and transcribe them.

Meant to be invoked on a short interval (e.g. every minute) by launchd or
cron. Each invocation:
    1. Lists recordings currently in the Just Press Record folder.
    2. Compares against a state file of already-processed recordings.
    3. Transcribes/summarizes whatever is new via ghtranscribe.process_recording.

On the very first run (no state file yet), only the 3 most recent
recordings are queued for transcription; anything older is marked as
already processed without being transcribed.

A lock file prevents overlapping runs in case one invocation (transcription
can take a while) is still going when the next one fires.
"""

import fcntl
import json
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ghtranscribe  # noqa: E402

STATE_DIR = Path("~/.ghtranscribe").expanduser()
STATE_PATH = STATE_DIR / "processed.json"
LOCK_PATH = STATE_DIR / "watch.lock"
INITIAL_BACKLOG = 3


def find_recordings() -> list[Path]:
    return sorted(
        (
            p
            for p in ghtranscribe.JPR_DIR.rglob("*")
            if p.suffix.lower() in ghtranscribe.AUDIO_EXTS and p.is_file()
        ),
        key=lambda p: p.stat().st_mtime,
    )


def load_state():
    if STATE_PATH.exists():
        return set(json.loads(STATE_PATH.read_text()))
    return None


def save_state(processed: set) -> None:
    STATE_PATH.write_text(json.dumps(sorted(processed), indent=2))


def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock_file = open(LOCK_PATH, "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("Another watch_jpr run is already in progress; exiting.")
        return

    recordings = find_recordings()
    processed = load_state()

    if processed is None:
        print("No previous state found; seeding backlog.")
        to_process = recordings[-INITIAL_BACKLOG:]
        processed = {str(p) for p in recordings if p not in to_process}
    else:
        to_process = [p for p in recordings if str(p) not in processed]

    if not to_process:
        print("No new recordings.")
        return

    for audio in to_process:
        print(f"Processing new recording: {audio}")
        try:
            ghtranscribe.process_recording(audio)
        except Exception:
            print(f"Failed to process {audio}:", file=sys.stderr)
            traceback.print_exc()
            continue
        processed.add(str(audio))
        save_state(processed)


if __name__ == "__main__":
    main()
