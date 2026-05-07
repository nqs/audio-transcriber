#!/usr/bin/env bash
# Basic argument-validation tests for transcribe.sh.
#
# Covers the early-exit paths that don't require pyenv, a venv, whisperx,
# or a Hugging Face token. Run from anywhere:
#
#     ./tests/test_transcribe.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRANSCRIBE="$SCRIPT_DIR/transcribe.sh"

TESTS=0
PASSED=0
FAILED=0

assert_eq() {
    local actual="$1" expected="$2" name="$3"
    TESTS=$((TESTS + 1))
    if [ "$actual" = "$expected" ]; then
        PASSED=$((PASSED + 1))
        echo "  ok   $name"
    else
        FAILED=$((FAILED + 1))
        echo "FAIL   $name: expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" name="$3"
    TESTS=$((TESTS + 1))
    case "$haystack" in
        *"$needle"*)
            PASSED=$((PASSED + 1))
            echo "  ok   $name"
            ;;
        *)
            FAILED=$((FAILED + 1))
            echo "FAIL   $name: '$needle' not found in output:"
            echo "$haystack" | sed 's/^/         | /'
            ;;
    esac
}

if [ ! -x "$TRANSCRIBE" ]; then
    echo "Error: $TRANSCRIBE is not executable." >&2
    exit 2
fi

# --- shell syntax ---
if bash -n "$TRANSCRIBE"; then
    syntax_rc=0
else
    syntax_rc=$?
fi
assert_eq "$syntax_rc" "0" "transcribe.sh has valid shell syntax"

# --- usage: no args ---
out=$("$TRANSCRIBE" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "exits 1 when called with no args"
assert_contains "$out" "Usage:" "prints usage when called with no args"

# --- usage: too many args ---
out=$("$TRANSCRIBE" a b c 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "exits 1 when called with three args"
assert_contains "$out" "Usage:" "prints usage when called with three args"

# --- nonexistent input file ---
missing="/tmp/__transcriber_does_not_exist_$$.m4a"
out=$("$TRANSCRIBE" "$missing" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "exits 1 when input file is missing"
assert_contains "$out" "not found" "prints 'not found' when input file is missing"

# --- missing HF token ---
# Create a fake input + a stubbed whisper-env so the script reaches the
# token check without trying to install anything. SKIP_PYENV=1 bypasses
# the pyenv block entirely.
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
fake_audio="$TMPDIR_TEST/sample.m4a"
: > "$fake_audio"

stub_root="$TMPDIR_TEST/stub"
mkdir -p "$stub_root/whisper-env/bin"
cp "$TRANSCRIBE" "$stub_root/transcribe.sh"
cat > "$stub_root/whisper-env/bin/activate" <<'EOF'
# no-op stub for tests
EOF
# Provide a fake `whisperx` so command -v succeeds.
cat > "$stub_root/whisper-env/bin/whisperx" <<'EOF'
#!/usr/bin/env bash
echo "stub whisperx invoked: $*" >&2
exit 0
EOF
chmod +x "$stub_root/whisper-env/bin/whisperx"

# Make the stub whisperx visible to `command -v` after `source activate`
# is a no-op, by prepending the stub bin dir to PATH for this invocation.
out=$(
    cd "$stub_root"
    HF_TOKEN= PATH="$stub_root/whisper-env/bin:$PATH" SKIP_PYENV=1 \
        ./transcribe.sh "$fake_audio" 2>&1
) && rc=0 || rc=$?
assert_eq "$rc" "1" "exits 1 when no HF token is configured"
assert_contains "$out" "no Hugging Face token found" \
    "prints token-missing error when HF_TOKEN is unset and no token file exists"

# --- final report ---
echo
echo "$PASSED/$TESTS passed"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
