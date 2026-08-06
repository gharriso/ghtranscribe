#!/usr/bin/env bash
# Sets up dependencies for ghtranscribe.py: a Python venv with whisperx,
# ffmpeg, and Ollama (with the summarization model pulled).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_DIR/.venv"
OLLAMA_MODEL="${GHTRANSCRIBE_OLLAMA_MODEL:-gpt-oss:latest}"

echo "==> Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Install it from https://brew.sh and re-run this script." >&2
    exit 1
fi

echo "==> Checking ffmpeg"
if ! command -v ffmpeg >/dev/null 2>&1; then
    brew install ffmpeg
else
    echo "ffmpeg already installed: $(command -v ffmpeg)"
fi

echo "==> Checking Ollama"
if ! command -v ollama >/dev/null 2>&1; then
    brew install ollama
    brew services start ollama
else
    echo "ollama already installed: $(command -v ollama)"
fi

echo "==> Checking ollama model: $OLLAMA_MODEL"
if ! ollama list | awk '{print $1}' | grep -qx "$OLLAMA_MODEL"; then
    ollama pull "$OLLAMA_MODEL"
else
    echo "Model $OLLAMA_MODEL already present"
fi

echo "==> Setting up Python venv at $VENV_DIR"
PYTHON_BIN="$(command -v python3.12 || command -v python3)"
if [ ! -d "$VENV_DIR" ]; then
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install whisperx

cat <<EOF

==> Setup complete.

Notes:
  - whisperx is installed at: $VENV_DIR/bin/whisperx
  - ghtranscribe.py will use it automatically (no PATH changes needed).
  - Diarization is not yet wired up in ghtranscribe.py, but when it is,
    you'll need a Hugging Face token with access to the pyannote speaker
    diarization models, exported as HUGGINGFACE_TOKEN.
  - The first time ghtranscribe.py creates an Apple Note, macOS will ask
    you to grant your terminal/Claude Code automation access to Notes.
    Approve that prompt (System Settings > Privacy & Security > Automation).

Run it with:
  python3 $REPO_DIR/ghtranscribe.py
EOF
