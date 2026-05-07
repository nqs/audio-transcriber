# whisperx transcriber

A small template that transcribes audio files in a Git repo using
[WhisperX](https://github.com/m-bain/whisperX) (with speaker diarization),
both locally and via GitHub Actions. Transcripts are written next to the
source audio as `<file>.txt`.

Designed to drop into an Obsidian vault repo (or any repo that holds audio).

## What's in this folder

| File | Purpose |
|---|---|
| `transcribe.sh` | CLI script that transcribes one audio file. Used both locally and in CI. |
| `.github/workflows/transcribe.yml` | GitHub Action: on push, transcribes added/changed audio and commits the transcripts. |
| `scripts/install-into.sh` | Helper that copies the template into a target repo. |
| `tests/test_transcribe.sh` | Argument-validation tests for `transcribe.sh`. Run with `./tests/test_transcribe.sh`. |
| `gitignore.template` | Lines to merge into your target repo's `.gitignore`. |
| `.python-version` | Pins Python 3.11.9 for `pyenv` users (local only). |
| `.gitignore` | Ignores local secrets / venv / OS cruft for *this* dev folder. |

## Install into a vault repo

Use the helper script:

```bash
/path/to/transcriber/scripts/install-into.sh /path/to/your/vault
```

It copies `transcribe.sh`, `.github/workflows/transcribe.yml`, and
`.python-version` into the vault, and appends the ignore rules from
`gitignore.template` to the vault's `.gitignore` (idempotent — running it
again won't duplicate the lines).

Or do the same thing manually:

```bash
SRC=/path/to/this/transcriber
rsync -av \
  --exclude='.git/' --exclude='.DS_Store' --exclude='whisper-env/' \
  --exclude='huggingface.token' --exclude='session_*.*' \
  --exclude='.gitignore' --exclude='gitignore.template' \
  --exclude='README.md' --exclude='scripts/' \
  "$SRC"/ ./
cat "$SRC/gitignore.template" >> .gitignore
```

### One-time GitHub setup

1. **Add a repo secret** named `HF_TOKEN` (Settings → Secrets and variables →
   Actions → New repository secret). The token must belong to a Hugging Face
   account that has accepted the terms of these gated models:
   - <https://huggingface.co/pyannote/speaker-diarization-community-1>
   - <https://huggingface.co/pyannote/segmentation-3.0>
2. **Allow the workflow to push commits**: Settings → Actions → General →
   Workflow permissions → "Read and write permissions".
3. (Recommended) **Enable Git LFS** for audio files in your vault — Obsidian
   recordings can be large and quickly bloat a regular repo.

### How it triggers

- **On push** that includes any `*.m4a`, `*.mp3`, `*.wav`, `*.webm`,
  `*.flac`, or `*.ogg` file: only the added/changed audio files are
  transcribed. The push of the resulting `.txt` files won't re-trigger the
  workflow (paths filter excludes them, and the commit is marked `[skip ci]`).
- **Manual run** (Actions tab → "Transcribe audio" → "Run workflow"): tick
  the "all-files" box to backfill transcripts for every audio file in the repo.

## Local usage

Requires `pyenv` with Python 3.11.9 installed. On first run the script
creates `whisper-env/` and installs `whisperx` into it.

```bash
# One-time: write your Hugging Face token to a file
echo "hf_xxx..." > huggingface.token

# Transcribe a single file (output: my-recording.m4a.txt)
./transcribe.sh my-recording.m4a

# Or specify a custom output path
./transcribe.sh my-recording.m4a transcript.txt
```

Skip the pyenv check (e.g. when Python 3.11.9 is already on `PATH`):

```bash
SKIP_PYENV=1 ./transcribe.sh my-recording.m4a
```

Pass the token via env instead of a file:

```bash
HF_TOKEN=hf_xxx... ./transcribe.sh my-recording.m4a
```

## Notes and limitations

- **Runtime on free GitHub runners is CPU-only.** Roughly 0.3–0.8× realtime
  with `base.en` + diarization. An hour of audio takes 20–50 minutes. For
  serious volume, use a self-hosted runner with a GPU and edit
  `.github/workflows/transcribe.yml` to `runs-on: [self-hosted, gpu]`.
- **Model is `base.en`.** Edit `transcribe.sh` to change it (e.g.
  `--model large-v3`). Larger models are more accurate but slower / heavier.
- **Diarization can be disabled** by removing `--diarize` from
  `transcribe.sh`. You then don't need to accept the pyannote model terms,
  but transcripts won't have speaker labels.
- **Token leakage:** `whisperx` takes the token as a CLI argument, so it's
  visible to other processes on the same machine via `ps`. Acceptable on a
  GitHub-hosted runner (ephemeral, single-tenant); be mindful on shared
  systems.

## Keeping the template up to date

This template is distributed by copy-paste — copies will drift from the
source over time. To make updates easier across multiple vault repos,
consider one of:

- **`git subtree`**: pull updates from this repo into a subdirectory of the
  vault while still owning the files locally.
- **Composite GitHub Action**: convert this into an action that vaults
  reference via `uses: <owner>/<repo>@v1`. Smaller footprint per vault, easy
  version bumps, but vaults can't customize the script as freely.
