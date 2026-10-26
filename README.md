# ghtranscribe

Transcribes and summarizes voice memos from the "Just Press Record" iCloud
folder.

## Pipeline

1. [whisperx](https://github.com/m-bain/whisperX) transcribes the audio,
   then `diarize.py` labels who is speaking (pyannote, run on the Apple
   Silicon GPU). The transcript is written as speaker turns:
   `[0:01:23] Speaker 2: ...`. If diarization fails, the recording is still
   transcribed and summarized, just without speaker labels.
2. The transcript is sent to a local [Ollama](https://ollama.com) model
   (`gpt-oss:latest` by default) for a summary plus any observations worth
   flagging.
3. The transcript and summary are written next to the source recording as
   `<name>_transcript.txt` and `<name>_summary.txt`, plus
   `<name>_summary.pdf` -- the same content as the Apple Note, rendered with
   [WeasyPrint](https://weasyprint.org).
4. The summary (converted from Markdown to HTML via `pandoc`) is saved as a
   new, richly formatted Apple Note.

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
python3 ghtranscribe.py --force 14-21-19.m4a   # redo an already-processed one
```

Diarization needs a Hugging Face token with access to
[pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)
(accept its terms on that page first). Provide it as `HUGGINGFACE_TOKEN`, or
-- for the launchd watcher, which doesn't see your shell environment -- in
`~/.ghtranscribe/hf_token`.

The first time it creates an Apple Note, macOS will prompt for automation
access to Notes -- approve that prompt.

## Environment variables

- `WHISPERX_BIN` -- override the path to the whisperx binary.
- `WHISPERX_MODEL` -- whisper model size (default `large-v3`).
- `GHTRANSCRIBE_DIARIZE` -- set to `0` to skip speaker diarization.
- `GHTRANSCRIBE_MIN_SPEAKERS` / `GHTRANSCRIBE_MAX_SPEAKERS` -- hint the
  expected number of speakers.
- `GHTRANSCRIBE_DIARIZE_DEVICE` -- override the diarization device (default
  `mps` when available, else `cpu`).
- `GHTRANSCRIBE_OLLAMA_MODEL` -- Ollama model used for summarization
  (default `gpt-oss:latest`).
