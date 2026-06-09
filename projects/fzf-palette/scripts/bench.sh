#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-smoke}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXE="$ROOT/.build/release/FzfPaletteApp"
CLI="$ROOT/.build/release/fzf-palette"
SOCKET="$HOME/Library/Application Support/FzfPalette/fzf-palette.sock"
TMPDIR="$(mktemp -d)"
APP_PID=""
cd "$ROOT"

cleanup() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    for _ in {1..20}; do
      if ! kill -0 "$APP_PID" 2>/dev/null; then
        break
      fi
      sleep 0.05
    done
    kill -9 "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

case "$MODE" in
  smoke|full|soak) ;;
  *)
    echo "Usage: scripts/bench.sh [smoke|full|soak]" >&2
    exit 2
    ;;
esac

swift build -c release --product fzf-palette >/dev/null
swift build -c release --product FzfPaletteApp >/dev/null

if [[ "$MODE" != "soak" ]]; then
  ENGINE_JSON="$("$CLI" bench engine --json)"
  echo "$ENGINE_JSON"

  python3 - "$ENGINE_JSON" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
failures = payload.get("failures", [])
if failures:
    raise SystemExit("; ".join(failures))
PY
fi

pkill -f "$APP_EXE" 2>/dev/null || true
rm -f "$SOCKET"
"$APP_EXE" >"$TMPDIR/app.out" 2>"$TMPDIR/app.err" &
APP_PID=$!

for _ in {1..50}; do
  if "$CLI" status --json >/tmp/fzf-palette-bench-status.json 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! "$CLI" status --json >/tmp/fzf-palette-bench-status.json; then
  cat "$TMPDIR/app.err" >&2 || true
  exit 1
fi

if [[ "$MODE" == "soak" ]]; then
  SOAK_RUNS=500
  SOAK_WARMUP=10
  LIFECYCLE_JSON="$("$CLI" bench lifecycle --runs "$SOAK_RUNS" --warmup "$SOAK_WARMUP" --json)"
  echo "$LIFECYCLE_JSON"
  python3 - "$LIFECYCLE_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
failures = report.get("failures", [])
if failures:
    raise SystemExit("; ".join(failures))
PY
  exit 0
elif [[ "$MODE" == "full" ]]; then
  PANEL_RUNS=100
  PANEL_WARMUP=10
  PREVIEW_RUNS=20
  PREVIEW_WARMUP=3
  KEYSTROKE_RUNS=120
  KEYSTROKE_WARMUP=20
  LARGE_KEYSTROKE_RUNS=60
  LARGE_KEYSTROKE_WARMUP=10
  SOURCE_RUNS=40
  SOURCE_WARMUP=5
  RESULT_RUNS=200
  RESULT_WARMUP=20
  LIFECYCLE_RUNS=30
  LIFECYCLE_WARMUP=5
  ROUNDTRIP_RUNS=200
  ROUNDTRIP_WARMUP=20
else
  PANEL_RUNS=20
  PANEL_WARMUP=2
  PREVIEW_RUNS=8
  PREVIEW_WARMUP=1
  KEYSTROKE_RUNS=36
  KEYSTROKE_WARMUP=6
  LARGE_KEYSTROKE_RUNS=24
  LARGE_KEYSTROKE_WARMUP=4
  SOURCE_RUNS=10
  SOURCE_WARMUP=2
  RESULT_RUNS=50
  RESULT_WARMUP=5
  LIFECYCLE_RUNS=5
  LIFECYCLE_WARMUP=1
  ROUNDTRIP_RUNS=50
  ROUNDTRIP_WARMUP=5
fi

PANEL_JSON="$("$CLI" bench panel --runs "$PANEL_RUNS" --warmup "$PANEL_WARMUP" --json)"
echo "$PANEL_JSON"
HOTKEY_JSON="$("$CLI" bench hotkey --runs "$PANEL_RUNS" --warmup "$PANEL_WARMUP" --json)"
echo "$HOTKEY_JSON"
CARBON_HOTKEY_JSON="$("$CLI" bench carbon-hotkey --runs "$PANEL_RUNS" --warmup "$PANEL_WARMUP" --json)"
echo "$CARBON_HOTKEY_JSON"
PHYSICAL_HOTKEY_JSON=""
if [[ "${FZF_PALETTE_RUN_PHYSICAL_HOTKEY_BENCH:-0}" == "1" || "${FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY:-0}" == "1" ]]; then
  set +e
  PHYSICAL_HOTKEY_OUTPUT="$("$CLI" bench physical-hotkey --runs "$PANEL_RUNS" --warmup "$PANEL_WARMUP" --json 2>&1)"
  PHYSICAL_HOTKEY_STATUS=$?
  set -e
  if [[ "$PHYSICAL_HOTKEY_STATUS" -eq 0 ]]; then
    PHYSICAL_HOTKEY_JSON="$PHYSICAL_HOTKEY_OUTPUT"
    echo "$PHYSICAL_HOTKEY_JSON"
  elif [[ "${FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY:-0}" == "1" ]]; then
    echo "$PHYSICAL_HOTKEY_OUTPUT" >&2
    exit "$PHYSICAL_HOTKEY_STATUS"
  else
    echo "physical hotkey benchmark skipped: $PHYSICAL_HOTKEY_OUTPUT" >&2
  fi
fi
KEYSTROKE_JSON="$("$CLI" bench keystroke --runs "$KEYSTROKE_RUNS" --warmup "$KEYSTROKE_WARMUP" --json)"
echo "$KEYSTROKE_JSON"
LARGE_KEYSTROKE_JSON="$("$CLI" bench large-keystroke --runs "$LARGE_KEYSTROKE_RUNS" --warmup "$LARGE_KEYSTROKE_WARMUP" --json)"
echo "$LARGE_KEYSTROKE_JSON"
MAIN_THREAD_JSON="$("$CLI" bench main-thread --runs "$KEYSTROKE_RUNS" --warmup "$KEYSTROKE_WARMUP" --json)"
echo "$MAIN_THREAD_JSON"
SOURCE_JSON="$("$CLI" bench source --runs "$SOURCE_RUNS" --warmup "$SOURCE_WARMUP" --json)"
echo "$SOURCE_JSON"
PREVIEW_JSON="$("$CLI" bench preview --runs "$PREVIEW_RUNS" --warmup "$PREVIEW_WARMUP" --json)"
echo "$PREVIEW_JSON"
RESULT_JSON="$("$CLI" bench result --runs "$RESULT_RUNS" --warmup "$RESULT_WARMUP" --json)"
echo "$RESULT_JSON"
LIFECYCLE_JSON="$("$CLI" bench lifecycle --runs "$LIFECYCLE_RUNS" --warmup "$LIFECYCLE_WARMUP" --json)"
echo "$LIFECYCLE_JSON"
ROUNDTRIP_JSON="$("$CLI" bench cli-roundtrip --runs "$ROUNDTRIP_RUNS" --warmup "$ROUNDTRIP_WARMUP" --json)"
echo "$ROUNDTRIP_JSON"

python3 - "$PANEL_JSON" "$HOTKEY_JSON" "$CARBON_HOTKEY_JSON" "$KEYSTROKE_JSON" "$LARGE_KEYSTROKE_JSON" "$MAIN_THREAD_JSON" "$SOURCE_JSON" "$PREVIEW_JSON" "$RESULT_JSON" "$LIFECYCLE_JSON" "$ROUNDTRIP_JSON" <<'PY'
import json
import sys

for raw in sys.argv[1:]:
    report = json.loads(raw)
    failures = report.get("failures", [])
    if failures:
        raise SystemExit("; ".join(failures))
PY

if [[ -n "$PHYSICAL_HOTKEY_JSON" ]]; then
  python3 - "$PHYSICAL_HOTKEY_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
failures = report.get("failures", [])
if failures:
    raise SystemExit("; ".join(failures))
PY
fi

if [[ "$MODE" == "full" ]]; then
  swift test --filter FzfPaletteBenchmarks
fi
