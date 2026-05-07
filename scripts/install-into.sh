#!/usr/bin/env bash
# Copy the whisperx transcriber template into a target repo.
#
# Usage: ./scripts/install-into.sh <target-repo-dir>
#
# Copies: transcribe.sh, .github/workflows/transcribe.yml, .python-version
# Skips:  local secrets, virtualenv, sample audio, this script itself,
#         the dev .gitignore, and the README.
# Appends gitignore.template to <target>/.gitignore.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <target-repo-dir>" >&2
    exit 1
fi

TARGET="$1"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$TARGET" ]; then
    echo "Error: target directory '$TARGET' does not exist." >&2
    exit 1
fi

if [ ! -f "$SRC/transcribe.sh" ] || [ ! -f "$SRC/.github/workflows/transcribe.yml" ]; then
    echo "Error: source directory '$SRC' is missing template files." >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync is required." >&2
    exit 1
fi

echo "Copying template from:"
echo "  $SRC"
echo "to:"
echo "  $TARGET"
echo

rsync -av \
    --exclude='.git/' \
    --exclude='.DS_Store' \
    --exclude='whisper-env/' \
    --exclude='huggingface.token' \
    --exclude='session_*.m4a' \
    --exclude='session_*.mp3' \
    --exclude='session_*.wav' \
    --exclude='session_*.webm' \
    --exclude='session_*.flac' \
    --exclude='session_*.ogg' \
    --exclude='session_*.txt' \
    --exclude='.gitignore' \
    --exclude='gitignore.template' \
    --exclude='README.md' \
    --exclude='scripts/' \
    --exclude='tests/' \
    --exclude='.run_id' \
    "$SRC"/ "$TARGET"/

# Merge gitignore.template into target's .gitignore (idempotent).
TEMPLATE_IGNORE="$SRC/gitignore.template"
TARGET_IGNORE="$TARGET/.gitignore"

if [ -f "$TEMPLATE_IGNORE" ]; then
    touch "$TARGET_IGNORE"
    if ! grep -qF "# --- whisperx transcriber ---" "$TARGET_IGNORE"; then
        echo >> "$TARGET_IGNORE"
        cat "$TEMPLATE_IGNORE" >> "$TARGET_IGNORE"
        echo "Appended gitignore.template lines to $TARGET_IGNORE"
    else
        echo "gitignore.template marker already present in $TARGET_IGNORE; skipping."
    fi
fi

echo
echo "Done."
echo
echo "Next steps in the target repo:"
echo "  1. Add a GitHub secret named HF_TOKEN."
echo "     gh secret set HF_TOKEN --repo <owner>/<repo>"
echo "  2. Settings -> Actions -> General -> Workflow permissions ="
echo "     'Read and write permissions' (so the action can push transcripts)."
echo "  3. Accept the pyannote model terms on Hugging Face for the account"
echo "     that owns HF_TOKEN:"
echo "       https://huggingface.co/pyannote/speaker-diarization-community-1"
echo "       https://huggingface.co/pyannote/segmentation-3.0"
echo "  4. (Recommended) Enable Git LFS for audio files."
