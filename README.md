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

## Install into a repo

There are two supported ways to drop the transcriber into a target repo
(a vault, a recordings repo, etc.):

1. **Copy-paste** — files are owned by the target repo. Simplest to
   customize; updates require re-copying.
2. **Git submodule** — the transcriber lives in a subdirectory pinned to a
   commit of this repo. Updates are a `git submodule update --remote`. You
   still write a thin workflow file in the target repo that calls the
   submodule's script.

Pick one. Don't mix them in the same repo.

### Option A — Copy-paste (helper script)

From a clone of this repo:

```bash
/path/to/audio-transcriber/scripts/install-into.sh /path/to/your/repo
```

It copies `transcribe.sh`, `.github/workflows/transcribe.yml`, and
`.python-version` into the target, and appends the ignore rules from
`gitignore.template` to the target's `.gitignore` (idempotent — running it
again won't duplicate the lines).

### Option B — Copy-paste (manual)

```bash
SRC=/path/to/audio-transcriber
rsync -av \
  --exclude='.git/' --exclude='.DS_Store' --exclude='whisper-env/' \
  --exclude='huggingface.token' --exclude='session_*.*' \
  --exclude='.gitignore' --exclude='gitignore.template' \
  --exclude='README.md' --exclude='scripts/' --exclude='tests/' \
  "$SRC"/ ./
cat "$SRC/gitignore.template" >> .gitignore
```

### Option C — Git submodule

GitHub Actions only runs workflows that live in the consumer repo's own
`.github/workflows/` directory, so the submodule approach uses a thin
wrapper workflow that calls the script from the submodule.

From inside the target repo:

```bash
# 1. Add this repo as a submodule.
git submodule add https://github.com/nqs/audio-transcriber.git audio-transcriber

# 2. Append the ignore rules.
cat audio-transcriber/gitignore.template >> .gitignore

# 3. Create a wrapper workflow (see contents below).
mkdir -p .github/workflows
$EDITOR .github/workflows/transcribe.yml

git add .gitmodules audio-transcriber .gitignore .github/workflows/transcribe.yml
git commit -m "Add audio-transcriber submodule"
```

Wrapper workflow contents — paste this into
`.github/workflows/transcribe.yml` in the **target** repo. It is the same
workflow shipped in this repo, with two differences: `submodules:
recursive` on checkout, and the script path prefixed with
`audio-transcriber/`.

```yaml
name: Transcribe audio

on:
  push:
    paths:
      - '**.m4a'
      - '**.mp3'
      - '**.wav'
      - '**.webm'
      - '**.flac'
      - '**.ogg'
  workflow_dispatch:
    inputs:
      all-files:
        description: 'Transcribe every audio file in the repo (backfill)'
        type: boolean
        default: false

permissions:
  contents: write

jobs:
  transcribe:
    runs-on: ubuntu-latest
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 2
          lfs: true
          submodules: recursive
      - uses: actions/setup-python@v6
        with:
          python-version: '3.11.9'
      - run: sudo apt-get update && sudo apt-get install -y ffmpeg
      - name: Find audio files to transcribe
        id: find
        env:
          ALL_FILES: ${{ inputs.all-files }}
          BEFORE: ${{ github.event.before }}
        run: |
          regex='\.(m4a|mp3|wav|webm|flac|ogg)$'
          if [ "${ALL_FILES:-false}" = "true" ]; then
            git ls-files | grep -Ei "$regex" > audio_files.txt || true
          else
            if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
              BEFORE="$(git rev-parse HEAD~1 2>/dev/null || echo '')"
            fi
            if [ -n "$BEFORE" ]; then
              git diff --name-only --diff-filter=AM "$BEFORE" HEAD \
                | grep -Ei "$regex" > audio_files.txt || true
            else
              git ls-files | grep -Ei "$regex" > audio_files.txt || true
            fi
          fi
          count=$(wc -l < audio_files.txt | tr -d ' ')
          echo "count=$count" >> "$GITHUB_OUTPUT"
      - name: Transcribe
        if: steps.find.outputs.count != '0'
        env:
          HF_TOKEN: ${{ secrets.HF_TOKEN }}
          SKIP_PYENV: '1'
        run: |
          chmod +x ./audio-transcriber/transcribe.sh
          while IFS= read -r f; do
            [ -z "$f" ] && continue
            ./audio-transcriber/transcribe.sh "$f" "$f.txt" \
              || echo "::warning::Failed to transcribe $f"
          done < audio_files.txt
          rm -f audio_files.txt
      - name: Commit transcripts
        if: steps.find.outputs.count != '0'
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A -- ':(glob)**/*.txt'
          if git diff --cached --quiet; then exit 0; fi
          git commit -m "chore: add transcripts [skip ci]"
          git push
```

To pull future updates of the transcriber into the target repo:

```bash
git submodule update --remote audio-transcriber
git add audio-transcriber
git commit -m "Bump audio-transcriber"
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

If you installed via submodule, prefix the script path with the submodule
directory (e.g. `./audio-transcriber/transcribe.sh ...`).

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

## Keeping the install up to date

- **Copy-paste installs** drift from this repo over time. Re-run
  `scripts/install-into.sh` (or repeat the manual `rsync`) to refresh
  `transcribe.sh`, the workflow, and `.python-version`.
- **Submodule installs** update with
  `git submodule update --remote audio-transcriber` followed by a commit
  of the new submodule pointer. The wrapper workflow in your repo only
  needs editing if the upstream `transcribe.sh` CLI changes.
