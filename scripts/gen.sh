#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/gen.sh --dir <repo-path> [--buf-bin <path>]

Runs `buf generate` for a target ConnectRPC repo.

Options:
  --dir <repo-path>     Target repository containing buf.yaml (required)
  --buf-bin <path>      Override buf binary path or name (default: auto-detect)
  --help                Show this help message

Behavior:
  - requires an installed `buf` binary
  - does not execute shell command strings
  - prints JSON to stdout
  - prints diagnostics to stderr
EOF
}

REPO_DIR=""
BUF_BIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --buf-bin)
      BUF_BIN="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Missing required --dir argument" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$REPO_DIR" ]]; then
  echo "Directory does not exist: $REPO_DIR" >&2
  exit 2
fi

if [[ ! -f "$REPO_DIR/buf.yaml" ]]; then
  echo "No buf.yaml found in: $REPO_DIR" >&2
  exit 2
fi

REPO_DIR=$(cd "$REPO_DIR" && pwd -P)

if [[ -z "$BUF_BIN" ]]; then
  if command -v buf >/dev/null 2>&1; then
    BUF_BIN="buf"
  else
    echo "buf is not available. Install the Buf CLI and retry." >&2
    exit 3
  fi
fi

if [[ "$BUF_BIN" == *[[:space:]]* ]]; then
  echo "--buf-bin must be a single executable path or command name, not a shell command string." >&2
  exit 2
fi

if ! command -v "$BUF_BIN" >/dev/null 2>&1; then
  echo "buf binary is not executable or not on PATH: $BUF_BIN" >&2
  exit 3
fi

START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_OUTPUT=$(mktemp)

if (cd "$REPO_DIR" && "$BUF_BIN" generate) >"$TMP_OUTPUT" 2> >(tee /dev/stderr >&2); then
  STATUS="ok"
  EXIT_CODE=0
else
  STATUS="error"
  EXIT_CODE=$?
fi

OUTPUT=$(python3 - <<'PY' "$TMP_OUTPUT"
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8', errors='replace')
print(json.dumps(text))
PY
)

rm -f "$TMP_OUTPUT"

printf '{\n'
printf '  "status": "%s",\n' "$STATUS"
printf '  "repo_dir": %s,\n' "$(python3 - <<'PY' "$REPO_DIR"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "command": %s,\n' "$(python3 - <<'PY' "$BUF_BIN generate"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "started_at": %s,\n' "$(python3 - <<'PY' "$START_TS"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "output": %s\n' "$OUTPUT"
printf '}\n'

exit "$EXIT_CODE"
