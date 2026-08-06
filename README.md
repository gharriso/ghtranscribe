# ghtranscribe

Transcribes and summarizes voice memos from the "Just Press Record" iCloud
folder.

## Pipeline

1. [whisperx](https://github.com/m-bain/whisperX) transcribes the audio.
2. The transcript is sent to a local [Ollama](https://ollama.com) model
   (`gpt-oss:latest` by default) for a summary plus any observations worth
   flagging.
3. The transcript and summary are written next to the source recording as
   `<name>_transcript.txt` and `<name>_summary.txt`.
4. The summary (converted from Markdown to HTML via `pandoc`) is saved as a
   new, richly formatted Apple Note.

Speaker diarization is not wired up yet -- whisperx's diarization step
(pyannote) is too slow on CPU for this to be practical right now. That's
being worked on separately.

## Setup

```
./install.sh
```

This installs ffmpeg and Ollama via Homebrew (if missing), pulls the Ollama
summarization model, and creates a `.venv` with whisperx.

## Usage

```
python3 ghtranscribe.py                # most recent recording
python3 ghtranscribe.py 14-21-19.m4a    # a specific recording (by filename
                                        # or full path)
```

The first time it creates an Apple Note, macOS will prompt for automation
access to Notes -- approve that prompt.

## Environment variables

- `WHISPERX_BIN` -- override the path to the whisperx binary.
- `WHISPERX_MODEL` -- whisper model size (default `medium`).
- `GHTRANSCRIBE_OLLAMA_MODEL` -- Ollama model used for summarization
  (default `gpt-oss:latest`).
