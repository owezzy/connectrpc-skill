#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/validate-proto.sh --dir <repo-path> [--against <baseline>] [--buf-bin <path>]

Runs `buf lint` and `buf breaking` for a target ConnectRPC repo.

Options:
  --dir <repo-path>      Target repository containing buf.yaml (required)
  --against <baseline>   Baseline for buf breaking (default: .git#branch=main)
  --buf-bin <path>       Override buf binary path or name (default: auto-detect)
  --help                 Show this help message

Behavior:
  - requires an installed `buf` binary
  - does not execute shell command strings
  - prints JSON to stdout
  - prints diagnostics to stderr
EOF
}

REPO_DIR=""
AGAINST=".git#branch=main"
BUF_BIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --against)
      AGAINST="${2:-}"
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

run_step() {
  local step_name="$1"
  shift
  local command_display stdout_file stderr_file status exit_code stdout_json stderr_json
  local command=("$@")

  command_display=$(printf '%q ' "${command[@]}")
  command_display=${command_display% }

  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  if (cd "$REPO_DIR" && "${command[@]}") >"$stdout_file" 2>"$stderr_file"; then
    status="ok"
    exit_code=0
  else
    status="error"
    exit_code=$?
  fi

  cat "$stderr_file" >&2

  stdout_json=$(python3 - <<'PY' "$stdout_file"
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
print(json.dumps(path.read_text(encoding='utf-8', errors='replace')))
PY
)
  stderr_json=$(python3 - <<'PY' "$stderr_file"
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
print(json.dumps(path.read_text(encoding='utf-8', errors='replace')))
PY
)

  rm -f "$stdout_file" "$stderr_file"

  printf '    {\n'
  printf '      "name": %s,\n' "$(python3 - <<'PY' "$step_name"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
  printf '      "command": %s,\n' "$(python3 - <<'PY' "$command_display"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
  printf '      "status": "%s",\n' "$status"
  printf '      "exit_code": %s,\n' "$exit_code"
  printf '      "stdout": %s,\n' "$stdout_json"
  printf '      "stderr": %s\n' "$stderr_json"
  printf '    }'

  return "$exit_code"
}

START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

LINT_RESULT=$(run_step "lint" "$BUF_BIN" lint) || LINT_EXIT=$?
LINT_EXIT=${LINT_EXIT:-0}

BREAKING_RESULT=$(run_step "breaking" "$BUF_BIN" breaking --against "$AGAINST") || BREAKING_EXIT=$?
BREAKING_EXIT=${BREAKING_EXIT:-0}

if [[ "$LINT_EXIT" -eq 0 && "$BREAKING_EXIT" -eq 0 ]]; then
  STATUS="ok"
  EXIT_CODE=0
else
  STATUS="error"
  EXIT_CODE=1
fi

printf '{\n'
printf '  "status": "%s",\n' "$STATUS"
printf '  "repo_dir": %s,\n' "$(python3 - <<'PY' "$REPO_DIR"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "against": %s,\n' "$(python3 - <<'PY' "$AGAINST"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "started_at": %s,\n' "$(python3 - <<'PY' "$START_TS"
import json, sys
print(json.dumps(sys.argv[1]))
PY
)"
printf '  "steps": [\n'
printf '%s,\n' "$LINT_RESULT"
printf '%s\n' "$BREAKING_RESULT"
printf '  ]\n'
printf '}\n'

exit "$EXIT_CODE"
