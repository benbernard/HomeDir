#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXE="$ROOT/.build/release/FzfPaletteApp"
CLI="$ROOT/.build/release/fzf-palette"
SOCKET="$HOME/Library/Application Support/FzfPalette/fzf-palette.sock"
TMPDIR="$(mktemp -d)"
APP_PID=""
OPEN_PID=""

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

wait_for_app() {
  for _ in {1..50}; do
    if "$CLI" status --json >/tmp/fzf-palette-internal-visual-status.json 2>/dev/null; then
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
checks = [
    snapshot.get("panelVisible"),
    snapshot.get("queryFieldFocused"),
    snapshot.get("renderedWidth", 0) > 0,
    snapshot.get("renderedHeight", 0) > 0,
    snapshot.get("sampledPixels", 0) >= 1000,
    snapshot.get("distinctColorBuckets", 0) >= 6,
    snapshot.get("nonBackgroundSampleRatio", 0) > 0.03,
    snapshot.get("luminanceStandardDeviation", 0) >= 0.025,
    snapshot.get("previewVisible"),
    snapshot.get("previewCharacterCount", 0) > 0,
    snapshot.get("layoutViolationCount") == 0,
]
raise SystemExit(0 if all(checks) else 1)
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

capture_internal_snapshot() {
  local appearance="$1"
  local snapshot_path="$2"
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
    echo "internal visual test failed: app did not start for $appearance appearance" >&2
    exit 1
  fi

  "$CLI" open \
    --source-command "printf 'visual-alpha\nvisual-beta\nvisual-gamma\n'" \
    --preview-command "printf '\033[32mPreview\033[0m for {}\nsecond line\nthird line'" \
    --preview-window "right:55%:wrap" \
    --prompt "visual>" \
    --header "Internal visual snapshot $appearance" \
    --pointer ">" \
    --marker "*" \
    --timeout-ms 5000 >"$out_path" 2>"$err_path" &
  OPEN_PID=$!

  if ! wait_for_snapshot "$snapshot_path"; then
    "$CLI" status --json >&2 || true
    "$CLI" test-control snapshot --json >&2 || true
    echo "internal visual test failed: panel did not become snapshot-ready for $appearance appearance" >&2
    exit 1
  fi

  "$CLI" test-control cancel >/dev/null
  set +e
  wait "$OPEN_PID"
  local open_status=$?
  set -e
  OPEN_PID=""
  if [[ "$open_status" -eq 0 ]]; then
    echo "internal visual test failed: visual picker for $appearance exited successfully instead of cancellation" >&2
    exit 1
  fi
}

cd "$ROOT"
swift build -c release --product fzf-palette >/dev/null
swift build -c release --product FzfPaletteApp >/dev/null

LIGHT_JSON="$TMPDIR/light.json"
DARK_JSON="$TMPDIR/dark.json"
capture_internal_snapshot light "$LIGHT_JSON"
capture_internal_snapshot dark "$DARK_JSON"
stop_app

python3 - "$LIGHT_JSON" "$DARK_JSON" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    light = json.load(handle)
with open(sys.argv[2]) as handle:
    dark = json.load(handle)

failures = []
light_name = light.get("effectiveAppearanceName", "").lower()
dark_name = dark.get("effectiveAppearanceName", "").lower()
if "dark" in light_name:
    failures.append(f"light snapshot reported dark appearance: {light.get('effectiveAppearanceName')}")
if "dark" not in dark_name:
    failures.append(f"dark snapshot did not report dark appearance: {dark.get('effectiveAppearanceName')}")

for name, snapshot in (("light", light), ("dark", dark)):
    if snapshot.get("distinctColorBuckets", 0) < 6:
        failures.append(f"{name} snapshot has too few color buckets: {snapshot.get('distinctColorBuckets')}")
    if snapshot.get("nonBackgroundSampleRatio", 0) <= 0.03:
        failures.append(f"{name} snapshot has too few non-background pixels: {snapshot.get('nonBackgroundSampleRatio')}")
    if snapshot.get("luminanceStandardDeviation", 0) < 0.025:
        failures.append(f"{name} snapshot is visually flat: {snapshot.get('luminanceStandardDeviation')}")

luminance_delta = light.get("averageLuminance", 0) - dark.get("averageLuminance", 0)
if luminance_delta < 0.03:
    failures.append(f"light/dark internal snapshots are not distinct enough: luminance delta {luminance_delta}")

if failures:
    raise SystemExit("; ".join(failures) + f"; light={light}; dark={dark}")
PY

echo "internal visual snapshot test passed"
