#!/usr/bin/env bash
# Installs the ghtranscribe watcher as a launchd LaunchAgent: it checks the
# Just Press Record folder every 60 seconds and transcribes anything new
# (see watch_jpr.py). Safe to re-run to pick up path/config changes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.guyharrison.ghtranscribe.watch"
PLIST_TEMPLATE="$REPO_DIR/$LABEL.plist.template"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/ghtranscribe-watch.log"
STATE_DIR="$HOME/.ghtranscribe"

if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "Template not found: $PLIST_TEMPLATE" >&2
    exit 1
fi

echo "==> Picking python interpreter"
if [ -x "$REPO_DIR/.venv/bin/python3" ]; then
    PYTHON_BIN="$REPO_DIR/.venv/bin/python3"
else
    PYTHON_BIN="$(command -v python3)"
fi
echo "Using: $PYTHON_BIN"

echo "==> Preparing directories"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$STATE_DIR"

echo "==> Generating $PLIST_DEST"
sed \
    -e "s|__PYTHON_BIN__|$PYTHON_BIN|g" \
    -e "s|__REPO_DIR__|$REPO_DIR|g" \
    -e "s|__LOG_PATH__|$LOG_PATH|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DEST"

echo "==> (Re)loading LaunchAgent: $LABEL"
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

sleep 1
if launchctl list | grep -q "$LABEL"; then
    echo "==> $LABEL is loaded and running."
else
    echo "==> Warning: $LABEL does not appear in 'launchctl list'." >&2
fi

cat <<EOF

==> Install complete.

The watcher checks for new Just Press Record recordings every 60 seconds.
On its first run it processes the 3 most recent recordings; after that it
only processes new ones, tracked in:
  $STATE_DIR/processed.json

Logs:
  $LOG_PATH

Manage it with:
  launchctl unload "$PLIST_DEST"   # stop
  launchctl load "$PLIST_DEST"     # start
  tail -f "$LOG_PATH"              # watch logs

To uninstall entirely:
  launchctl unload "$PLIST_DEST"
  rm "$PLIST_DEST"
EOF
