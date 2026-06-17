#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXE="$ROOT/.build/release/FzfPaletteApp"
CLI="$ROOT/.build/release/fzf-palette"
SOCKET="$HOME/Library/Application Support/FzfPalette/fzf-palette.sock"
TMPDIR="$(mktemp -d)"
APP_PID=""
OPEN_PID=""
REQUIRE="${FZF_PALETTE_REQUIRE_EXTERNAL_VISUAL:-0}"

cleanup() {
  if [[ -n "${OPEN_PID:-}" ]] && kill -0 "$OPEN_PID" 2>/dev/null; then
    "$CLI" test-control cancel >/dev/null 2>&1 || true
    wait "$OPEN_PID" 2>/dev/null || true
  fi
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    kill -9 "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

skip_or_fail() {
  local message="$1"
  if [[ "$REQUIRE" == "1" ]]; then
    echo "external visual test failed: $message" >&2
    exit 1
  fi
  echo "external visual test skipped: $message" >&2
  exit 0
}

wait_for_app() {
  for _ in {1..50}; do
    if "$CLI" status --json >/tmp/fzf-palette-visual-status.json 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_snapshot() {
  local snapshot_path="$1"
  for _ in {1..50}; do
    if "$CLI" test-control snapshot --json >"$snapshot_path" 2>/dev/null &&
      python3 - "$snapshot_path" <<'PY'
import json
import sys
with open(sys.argv[1]) as handle:
    snapshot = json.load(handle)
raise SystemExit(
    0
    if snapshot.get("panelVisible")
    and snapshot.get("queryFieldFocused")
    and snapshot.get("visibleRows", 0) >= 2
    and snapshot.get("previewVisible")
    and snapshot.get("windowNumber", 0) > 0
    and snapshot.get("captureWidth", 0) > 0
    and snapshot.get("captureHeight", 0) > 0
    and snapshot.get("layoutViolationCount") == 0
    else 1
)
PY
    then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

stop_app() {
  if [[ -n "${OPEN_PID:-}" ]] && kill -0 "$OPEN_PID" 2>/dev/null; then
    "$CLI" test-control cancel >/dev/null 2>&1 || true
    wait "$OPEN_PID" 2>/dev/null || true
    OPEN_PID=""
  fi
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
}

capture_appearance() {
  local appearance="$1"
  local png_path="$2"
  local snapshot_path="$TMPDIR/$appearance-snapshot.json"
  local out_path="$TMPDIR/$appearance-open.out"
  local err_path="$TMPDIR/$appearance-open.err"

  stop_app
  pkill -f "$APP_EXE" 2>/dev/null || true
  rm -f "$SOCKET"

  FZF_PALETTE_ENABLE_TEST_CONTROL=1 \
  FZF_PALETTE_APPEARANCE="$appearance" \
  "$APP_EXE" >"$TMPDIR/$appearance-app.out" 2>"$TMPDIR/$appearance-app.err" &
  APP_PID=$!

  if ! wait_for_app; then
    cat "$TMPDIR/$appearance-app.err" >&2 || true
    skip_or_fail "app did not start for $appearance appearance"
  fi

  "$CLI" open \
    --source-command "printf 'visual-alpha\nvisual-beta\nvisual-gamma\n'" \
    --preview-command "printf '\033[32mPreview\033[0m for {}\nsecond line\nthird line'" \
    --preview-window "right:55%:wrap" \
    --prompt "visual>" \
    --header "Visual screenshot $appearance" \
    --pointer ">" \
    --marker "*" \
    --timeout-ms 5000 >"$out_path" 2>"$err_path" &
  OPEN_PID=$!

  if ! wait_for_snapshot "$snapshot_path"; then
    "$CLI" status --json >&2 || true
    "$CLI" test-control snapshot --json >&2 || true
    skip_or_fail "panel did not become screenshot-ready for $appearance appearance"
  fi

  local window_number
  window_number="$(python3 - "$snapshot_path" <<'PY'
import json
import sys
with open(sys.argv[1]) as handle:
    print(json.load(handle)["windowNumber"])
PY
)"
  local capture_rect
  capture_rect="$(python3 - "$snapshot_path" <<'PY'
import json
import sys
with open(sys.argv[1]) as handle:
    snapshot = json.load(handle)
print(f'{snapshot["captureX"]},{snapshot["captureY"]},{snapshot["captureWidth"]},{snapshot["captureHeight"]}')
PY
)"

  set +e
  /usr/sbin/screencapture -x -l "$window_number" "$png_path" >/tmp/fzf-palette-screencapture.out 2>/tmp/fzf-palette-screencapture.err
  local capture_status=$?
  if [[ "$capture_status" -ne 0 || ! -s "$png_path" ]]; then
    /usr/sbin/screencapture -x -R "$capture_rect" "$png_path" >/tmp/fzf-palette-screencapture-rect.out 2>/tmp/fzf-palette-screencapture-rect.err
    capture_status=$?
  fi
  set -e
  if [[ "$capture_status" -ne 0 || ! -s "$png_path" ]]; then
    cat /tmp/fzf-palette-screencapture.err >&2 || true
    cat /tmp/fzf-palette-screencapture-rect.err >&2 || true
    skip_or_fail "screencapture could not capture $appearance window $window_number or rect $capture_rect"
  fi

  "$CLI" test-control cancel >/dev/null
  set +e
  wait "$OPEN_PID"
  local open_status=$?
  set -e
  OPEN_PID=""
  if [[ "$open_status" -eq 0 ]]; then
    skip_or_fail "visual picker for $appearance exited successfully instead of cancellation"
  fi
}

cd "$ROOT"
swift build -c release --product fzf-palette >/dev/null
swift build -c release --product FzfPaletteApp >/dev/null

LIGHT_PNG="$TMPDIR/light.png"
DARK_PNG="$TMPDIR/dark.png"
capture_appearance light "$LIGHT_PNG"
capture_appearance dark "$DARK_PNG"
stop_app

if ! "$ROOT/scripts/visual-metrics.swift" "$LIGHT_PNG" "$DARK_PNG"; then
  if [[ "$REQUIRE" == "1" ]]; then
    exit 1
  fi
  skip_or_fail "captured screenshots failed visual metrics"
fi

echo "external visual screenshot test passed"
