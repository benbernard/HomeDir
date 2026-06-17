#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXE="$ROOT/.build/release/FzfPaletteApp"
CLI="$ROOT/.build/release/fzf-palette"
SOCKET="$HOME/Library/Application Support/FzfPalette/fzf-palette.sock"
APP_PID=""
TMPDIR="$(mktemp -d)"
OPEN_LOG="$TMPDIR/open.log"
PASTE_LOG="$TMPDIR/paste.log"
PROFILES_FILE="$TMPDIR/profiles.json"
PROFILE_PREVIEW_FILE="$TMPDIR/profile-preview.out"
TWO_STAGE_ROOT="$TMPDIR/two-stage-root"
TWO_STAGE_PREVIEW_FILE="$TMPDIR/two-stage-preview.out"
PROGRAM_CONTEXT_ROOT="$TMPDIR/program-context-root"
CODEX_CONTEXT_FILE="$TMPDIR/codex-context.json"
BUILTIN_HOME="$TMPDIR/builtin-home"
BUILTIN_PROJECT="$BUILTIN_HOME/projects/project-builtin"
BUILTIN_AVA="$BUILTIN_HOME/projects/ava"
BUILTIN_REPO="$BUILTIN_HOME/repos/repo-builtin"
BUILTIN_DOWNLOADS="$BUILTIN_HOME/Downloads"
SETTINGS_SUITE="dev.benbernard.fzf-palette.e2e.$$"

cleanup() {
  defaults delete "$SETTINGS_SUITE" >/dev/null 2>&1 || true
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

wait_for_picker_rows() {
  local expected="$1"
  for _ in {1..50}; do
    if python3 - "$("$CLI" status --json)" "$expected" <<'PY'
import json
import sys
expected = int(sys.argv[2])
status = json.loads(sys.argv[1])["app"]
raise SystemExit(0 if status["activePicker"] and status["visibleRows"] == expected else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "picker did not become ready with $expected visible rows" >&2
  "$CLI" status --json >&2 || true
  exit 1
}

wait_for_panel_visible() {
  for _ in {1..50}; do
    if python3 - "$("$CLI" status --json)" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
raise SystemExit(0 if status["panelVisible"] else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "panel did not become visible" >&2
  "$CLI" status --json >&2 || true
  exit 1
}

wait_for_preview_visible_state() {
  local expected="$1"
  for _ in {1..50}; do
    if python3 - "$("$CLI" status --json)" "$expected" <<'PY'
import json
import sys
expected = sys.argv[2] == "true"
status = json.loads(sys.argv[1])["app"]
raise SystemExit(0 if status["activePicker"] and status["previewVisible"] == expected else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "preview visible state did not become $expected" >&2
  "$CLI" status --json >&2 || true
  exit 1
}

wait_for_preview_ansi_spans() {
  local expected="$1"
  for _ in {1..50}; do
    if python3 - "$("$CLI" test-control snapshot --json)" "$expected" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = int(sys.argv[2])
raise SystemExit(
    0
    if snapshot["previewAnsiSpanCount"] >= expected
    and not snapshot["previewContainsEscapeSequences"]
    else 1
)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "preview ANSI spans did not become >= $expected" >&2
  "$CLI" test-control snapshot --json >&2 || true
  exit 1
}

wait_for_preview_scroll_offset() {
  local minimum="$1"
  for _ in {1..50}; do
    if python3 - "$("$CLI" test-control snapshot --json)" "$minimum" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
minimum = float(sys.argv[2])
raise SystemExit(0 if snapshot["previewScrollOffsetY"] > minimum else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "preview scroll offset did not exceed $minimum" >&2
  "$CLI" test-control snapshot --json >&2 || true
  exit 1
}

wait_for_chrome() {
  local expected_prompt="$1"
  local expected_header="$2"
  local expected_pointer="$3"
  local expected_marker="$4"
  local expected_info="$5"
  for _ in {1..50}; do
    if python3 - "$("$CLI" status --json)" "$expected_prompt" "$expected_header" "$expected_pointer" "$expected_marker" "$expected_info" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
def matches(actual, expected):
    return actual == expected if expected else actual in (None, "")
raise SystemExit(
    0
    if status["activePicker"]
    and matches(status.get("prompt"), sys.argv[2])
    and matches(status.get("header"), sys.argv[3])
    and matches(status.get("pointer"), sys.argv[4])
    and matches(status.get("marker"), sys.argv[5])
    and matches(status.get("info"), sys.argv[6])
    else 1
)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "native chrome did not become expected values" >&2
  echo "expected prompt: $expected_prompt" >&2
  echo "expected header: $expected_header" >&2
  echo "expected pointer: $expected_pointer" >&2
  echo "expected marker: $expected_marker" >&2
  echo "expected info: $expected_info" >&2
  "$CLI" status --json >&2 || true
  exit 1
}

wait_for_file() {
  local file="$1"
  for _ in {1..50}; do
    if [[ -s "$file" ]]; then
      return 0
    fi
    sleep 0.1
  done

  echo "file did not appear: $file" >&2
  exit 1
}

wait_for_file_content() {
  local file="$1"
  local expected="$2"
  for _ in {1..60}; do
    if [[ -f "$file" ]] && [[ "$(cat "$file")" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done

  echo "file did not contain expected content: $file" >&2
  echo "expected: $expected" >&2
  echo "actual:" >&2
  cat "$file" >&2 2>/dev/null || true
  exit 1
}

assert_pid_dead() {
  local pid="$1"
  for _ in {1..30}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done

  echo "process $pid is still alive" >&2
  ps -p "$pid" -o pid=,ppid=,command= >&2 || true
  exit 1
}

cd "$ROOT"

swift build -c release --product FzfPaletteApp >/dev/null
swift build -c release --product fzf-palette >/dev/null

mkdir -p "$TWO_STAGE_ROOT/nested" "$PROGRAM_CONTEXT_ROOT"
printf 'alpha\n' >"$TWO_STAGE_ROOT/alpha.txt"
printf 'beta\n' >"$TWO_STAGE_ROOT/nested/beta.txt"
printf 'codex context\n' >"$PROGRAM_CONTEXT_ROOT/context.txt"
python3 - "$CODEX_CONTEXT_FILE" "$PROGRAM_CONTEXT_ROOT" <<'PY'
import json
import sys
path, cwd = sys.argv[1:3]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"cwd": cwd, "detail": "e2e codex context"}, handle)
PY
mkdir -p "$BUILTIN_PROJECT/nested" "$BUILTIN_AVA/gohan" "$BUILTIN_REPO" "$BUILTIN_DOWNLOADS"
printf 'alpha\n' >"$BUILTIN_PROJECT/alpha.txt"
printf 'beta\n' >"$BUILTIN_PROJECT/nested/beta.txt"
printf 'gohan\n' >"$BUILTIN_AVA/gohan/gohan.txt"
printf 'repo\n' >"$BUILTIN_REPO/README.md"
printf 'old\n' >"$BUILTIN_DOWNLOADS/download-old.txt"
printf 'new\n' >"$BUILTIN_DOWNLOADS/download-new.txt"
touch -t 202601010101 "$BUILTIN_DOWNLOADS/download-old.txt"
touch -t 202601010102 "$BUILTIN_DOWNLOADS/download-new.txt"

python3 - "$PROFILES_FILE" "$PROFILE_PREVIEW_FILE" "$TWO_STAGE_ROOT" "$TWO_STAGE_PREVIEW_FILE" <<'PY'
import json
import sys
profiles_file, preview_file, two_stage_root, two_stage_preview_file = sys.argv[1:5]
two_stage_command = """root={}
find "$root" -mindepth 1 -maxdepth 2 \\( -type f -o -type d \\) -print 2>/dev/null | sort | awk -v root="$root" 'index($0, root "/") == 1 { rel=substr($0, length(root)+2); if (rel != "") print rel "\\t" $0 }'
"""
with open(profiles_file, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "profiles": [
                {
                    "name": "hotkey-profile",
                    "title": "Hotkey Profile",
                    "source": {
                        "type": "static",
                        "items": ["hotkey-one"],
                    },
                    "display": {
                        "prompt": "hotkey>",
                        "header": "Hotkey profile",
                        "pointer": ">",
                        "marker": "*",
                        "info": "inline",
                    },
                    "preview": {
                        "command": "printf 'hotkey preview'",
                        "window": "right:60%:wrap",
                        "debounceMs": 0,
                    },
                    "result": {
                        "mode": "return",
                    },
                },
                {
                    "name": "config-profile",
                    "title": "Config Profile",
                    "source": {
                        "type": "command",
                        "command": "printf 'profile-one\\t/hidden/profile-one.json\\nprofile-two\\t/hidden/profile-two.json\\n'",
                    },
                    "fzfOptions": ["--bind", "ctrl-/:toggle-preview"],
                    "display": {
                        "delimiter": "\t",
                        "withNth": "1",
                        "prompt": "profile>",
                        "header": "Config profile",
                        "pointer": ">",
                        "marker": "*",
                        "info": "inline",
                    },
                    "preview": {
                        "command": f"printf '%s' {{}} > {json.dumps(preview_file)}",
                        "window": "right:60%:wrap",
                        "debounceMs": 0,
                    },
                    "result": {
                        "mode": "return",
                        "fields": "2",
                        "join": "newline",
                    },
                },
                {
                    "name": "two-stage-profile",
                    "title": "Two Stage Profile",
                    "source": {
                        "type": "twoStage",
                        "first": {
                            "title": "Choose Test Root",
                            "source": {
                                "type": "static",
                                "items": [
                                    f"fixture\t{two_stage_root}",
                                    "/tmp/missing\t/tmp/missing",
                                ],
                            },
                            "display": {
                                "delimiter": "\t",
                                "withNth": "1",
                                "prompt": "roots>",
                                "header": "Pick test root",
                                "pointer": ">",
                                "marker": "*",
                                "info": "inline",
                            },
                            "result": {
                                "mode": "return",
                                "fields": "2",
                            },
                        },
                        "second": {
                            "title": "Choose Test File",
                            "source": {
                                "type": "command",
                                "command": two_stage_command,
                            },
                            "display": {
                                "delimiter": "\t",
                                "withNth": "1",
                                "prompt": "files>",
                                "header": "Pick test file",
                                "pointer": ">",
                                "marker": "*",
                                "info": "inline",
                            },
                            "preview": {
                                "command": f"printf '%s' {{}} > {json.dumps(two_stage_preview_file)}",
                                "window": "right:60%:wrap",
                                "debounceMs": 0,
                            },
                            "result": {
                                "mode": "return",
                                "fields": "2",
                            },
                        },
                    },
                }
            ],
            "hotkeys": [
                {
                    "profile": "two-stage-profile",
                    "binding": "ctrl+option+shift+f17",
                }
            ]
        },
        handle,
    )
PY

pkill -f "$APP_EXE" 2>/dev/null || true
rm -f "$SOCKET"
defaults delete "$SETTINGS_SUITE" >/dev/null 2>&1 || true

FZF_PALETTE_ENABLE_TEST_CONTROL=1 \
FZF_PALETTE_HOTKEY="ctrl+option+shift+f18" \
FZF_PALETTE_HOTKEY_PROFILE="hotkey-profile" \
FZF_DEFAULT_OPTS="--height 40% --reverse --border -i -m --bind ctrl-A:select-all,ctrl-d:deselect-all --border-label ' e2e default '" \
FZF_DEFAULT_COMMAND="printf 'default-one\ndefault-two\n'" \
FZF_CTRL_T_COMMAND="printf 'ctrl-t-one\nctrl-t-two\n'" \
FZF_PALETTE_OPEN_LOG="$OPEN_LOG" \
FZF_PALETTE_PASTE_LOG="$PASTE_LOG" \
FZF_PALETTE_PROFILES_FILE="$PROFILES_FILE" \
FZF_PALETTE_USER_DEFAULTS_SUITE="$SETTINGS_SUITE" \
FZF_PALETTE_TEST_FRONTMOST_APP_NAME="Codex" \
FZF_PALETTE_TEST_FRONTMOST_APP_BUNDLE_ID="com.openai.codex" \
FZF_PALETTE_CODEX_CONTEXT_FILE="$CODEX_CONTEXT_FILE" \
HOME="$BUILTIN_HOME" \
"$APP_EXE" >"$TMPDIR/app.out" 2>"$TMPDIR/app.err" &
APP_PID=$!

for _ in {1..50}; do
  if "$CLI" status --json >/tmp/fzf-palette-e2e-status.json 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! "$CLI" status --json >/tmp/fzf-palette-e2e-status.json; then
  cat "$TMPDIR/app.err" >&2 || true
  exit 1
fi

python3 - "$(< /tmp/fzf-palette-e2e-status.json)" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
if status.get("hotkey") != "ctrl+option+shift+f18":
    raise SystemExit(f"expected configured hotkey ctrl+option+shift+f18, got {status.get('hotkey')}")
if status.get("hotkeyRegistered") is not True:
    raise SystemExit(f"configured hotkey did not register: {status.get('hotkeyError')}")
if status.get("hotkeyError"):
    raise SystemExit(status["hotkeyError"])
hotkeys = status.get("hotkeys", [])
expected = {
    ("hotkey-profile", "ctrl+option+shift+f18"),
    ("two-stage-profile", "ctrl+option+shift+f17"),
}
actual = {(entry.get("profile"), entry.get("hotkey")) for entry in hotkeys}
missing = expected - actual
if missing:
    raise SystemExit(f"missing configured profile hotkeys: {sorted(missing)} from {hotkeys}")
if not all(entry.get("registered") for entry in hotkeys):
    raise SystemExit(f"not all hotkeys registered: {hotkeys}")
PY

SETTINGS_GET="$("$CLI" settings get --json)"
python3 - "$SETTINGS_GET" <<'PY'
import json
import sys
settings = json.loads(sys.argv[1])["settings"]
if settings.get("hotkey") not in (None, ""):
    raise SystemExit(f"expected empty initial settings hotkey, got {settings}")
if settings.get("profile") != "default":
    raise SystemExit(f"expected default initial settings profile, got {settings}")
PY

SETTINGS_SET="$("$CLI" settings set --hotkey ctrl+option+shift+f16 --profile config-profile --json)"
python3 - "$SETTINGS_SET" <<'PY'
import json
import sys
settings = json.loads(sys.argv[1])["settings"]
if settings.get("hotkey") != "ctrl+option+shift+f16":
    raise SystemExit(f"expected canonical settings hotkey ctrl+option+shift+f16, got {settings}")
if settings.get("profile") != "config-profile":
    raise SystemExit(f"expected settings profile config-profile, got {settings}")
PY

SETTINGS_STATUS="$("$CLI" status --json)"
python3 - "$SETTINGS_STATUS" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
if status.get("settingsHotkey") != "ctrl+option+shift+f16":
    raise SystemExit(f"settings hotkey missing from status: {status}")
if status.get("settingsProfile") != "config-profile":
    raise SystemExit(f"settings profile missing from status: {status}")
hotkeys = status.get("hotkeys", [])
if ("config-profile", "ctrl+option+shift+f16") not in {
    (entry.get("profile"), entry.get("hotkey")) for entry in hotkeys
}:
    raise SystemExit(f"settings hotkey missing from registered hotkeys: {hotkeys}")
PY

"$CLI" test-control hotkey config-profile >/tmp/fzf-palette-e2e-settings-hotkey-control.out
wait_for_picker_rows 2
wait_for_chrome "profile>" "Config profile" ">" "*" "inline"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-settings-hotkey-cancel.out

"$CLI" settings show --json >/tmp/fzf-palette-e2e-settings-show.json
SETTINGS_SHOW_STATUS="$("$CLI" status --json)"
python3 - "$SETTINGS_SHOW_STATUS" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
if status.get("settingsVisible") is not True:
    raise SystemExit(f"settings window did not become visible: {status}")
PY

"$CLI" settings close --json >/tmp/fzf-palette-e2e-settings-close.json
SETTINGS_CLOSE_STATUS="$("$CLI" status --json)"
python3 - "$SETTINGS_CLOSE_STATUS" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
if status.get("settingsVisible") is not False:
    raise SystemExit(f"settings window did not close: {status}")
PY

"$CLI" settings clear --json >/tmp/fzf-palette-e2e-settings-clear.json
SETTINGS_CLEAR_STATUS="$("$CLI" status --json)"
python3 - "$SETTINGS_CLEAR_STATUS" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
if status.get("settingsHotkey") not in (None, ""):
    raise SystemExit(f"settings hotkey did not clear: {status}")
if ("config-profile", "ctrl+option+shift+f16") in {
    (entry.get("profile"), entry.get("hotkey")) for entry in status.get("hotkeys", [])
}:
    raise SystemExit(f"settings hotkey still registered after clear: {status.get('hotkeys')}")
PY

"$CLI" test-control hotkey >/tmp/fzf-palette-e2e-hotkey-control.out
wait_for_panel_visible
wait_for_picker_rows 1
wait_for_chrome "hotkey>" "Hotkey profile" ">" "*" "inline"
HOTKEY_CONTEXT_STATUS="$("$CLI" status --json)"
python3 - "$HOTKEY_CONTEXT_STATUS" "$PROGRAM_CONTEXT_ROOT" <<'PY'
import json
import sys
status = json.loads(sys.argv[1])["app"]
expected_cwd = sys.argv[2]
context = status.get("programContext")
if not context:
    raise SystemExit(f"expected program context in status, got {status}")
if context.get("cwd") != expected_cwd:
    raise SystemExit(f"expected context cwd {expected_cwd}, got {context}")
if context.get("provider") != "codex-bridge":
    raise SystemExit(f"expected codex-bridge provider, got {context}")
if context.get("bundleIdentifier") != "com.openai.codex":
    raise SystemExit(f"expected Codex bundle id, got {context}")
PY
HOTKEY_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$HOTKEY_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
checks = [
    (snapshot["panelVisible"], "panel is visible"),
    (snapshot["queryFieldFocused"], "query field is focused"),
    (not snapshot.get("queryFieldActionBound", True), "query field does not auto-accept through NSSearchField action"),
    (snapshot["width"] >= 900 and snapshot["height"] >= 500, "panel has stable expected size"),
    (snapshot["renderedWidth"] > 0 and snapshot["renderedHeight"] > 0, "panel rendered to pixels"),
    (snapshot["sampledPixels"] >= 1000, "snapshot sampled enough pixels"),
    (snapshot["distinctColorBuckets"] >= 6, "panel render is not flat/blank"),
    (snapshot["nonBackgroundSampleRatio"] > 0.03, "panel render has non-background pixels"),
    (snapshot.get("usesVibrantBackground"), "panel uses native vibrant background"),
    (snapshot.get("contentCornerRadius", 0) >= 12, "panel content has rounded corners"),
    (snapshot.get("resultsCornerRadius", 0) >= 8, "results pane has rounded corners"),
    (snapshot.get("previewCornerRadius", 0) >= 8, "preview pane has rounded corners"),
    (snapshot.get("usesCustomSelectionStyle"), "result rows use custom selection style"),
    (snapshot["visibleRows"] >= 1, "panel has visible rows"),
    (snapshot["previewVisible"], "preview pane is visible"),
    (snapshot["previewWidth"] >= 200, "preview pane has real width"),
    (snapshot["resultsWidth"] >= 200, "results pane has real width"),
    (snapshot["previewCharacterCount"] > 0, "preview has content"),
    (snapshot["layoutViolationCount"] == 0, "panel layout has no snapshot violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-hotkey-cancel.out

KEY_NAV_OUT="$TMPDIR/key-nav.out"
KEY_NAV_ERR="$TMPDIR/key-nav.err"
"$CLI" open \
  --source-command "printf 'alpha\nbeta\ngamma\n'" \
  +m \
  --timeout-ms 5000 >"$KEY_NAV_OUT" 2>"$KEY_NAV_ERR" &
OPEN_PID=$!

wait_for_picker_rows 3
KEY_NAV_INITIAL="$("$CLI" test-control snapshot --json)"
python3 - "$KEY_NAV_INITIAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
if not snapshot.get("queryFieldFocused"):
    raise SystemExit(f"query field should be focused before arrow navigation: {snapshot}")
if snapshot.get("selectedRowIndex") != 0 or snapshot.get("activeRowText") != "alpha":
    raise SystemExit(f"expected initial active row alpha, got {snapshot}")
PY

"$CLI" test-control key down >/tmp/fzf-palette-e2e-key-down-control.out
KEY_NAV_DOWN="$("$CLI" test-control snapshot --json)"
python3 - "$KEY_NAV_DOWN" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
if not snapshot.get("queryFieldFocused"):
    raise SystemExit(f"query field lost focus after arrow down: {snapshot}")
if snapshot.get("selectedRowIndex") != 1 or snapshot.get("activeRowText") != "beta":
    raise SystemExit(f"expected arrow down to select beta, got {snapshot}")
PY

"$CLI" test-control key up >/tmp/fzf-palette-e2e-key-up-control.out
KEY_NAV_UP="$("$CLI" test-control snapshot --json)"
python3 - "$KEY_NAV_UP" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
if not snapshot.get("queryFieldFocused"):
    raise SystemExit(f"query field lost focus after arrow up: {snapshot}")
if snapshot.get("selectedRowIndex") != 0 or snapshot.get("activeRowText") != "alpha":
    raise SystemExit(f"expected arrow up to return to alpha, got {snapshot}")
PY

"$CLI" test-control cancel >/tmp/fzf-palette-e2e-key-nav-cancel.out
set +e
wait "$OPEN_PID"
set -e
OPEN_PID=""

"$CLI" test-control carbon-hotkey >/tmp/fzf-palette-e2e-carbon-hotkey-control.out
wait_for_panel_visible
wait_for_picker_rows 1
wait_for_chrome "hotkey>" "Hotkey profile" ">" "*" "inline"
CARBON_HOTKEY_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$CARBON_HOTKEY_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
checks = [
    (snapshot["panelVisible"], "panel is visible after Carbon event"),
    (snapshot["queryFieldFocused"], "query field is focused after Carbon event"),
    (snapshot["visibleRows"] >= 1, "Carbon event panel has visible rows"),
    (snapshot["layoutViolationCount"] == 0, "Carbon event panel layout has no snapshot violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-carbon-hotkey-cancel.out

set +e
PHYSICAL_HOTKEY_OUTPUT="$("$CLI" test-control physical-hotkey 2>&1)"
PHYSICAL_HOTKEY_STATUS=$?
set -e
if [[ "$PHYSICAL_HOTKEY_STATUS" -eq 0 ]]; then
  wait_for_panel_visible
  wait_for_picker_rows 1
  wait_for_chrome "hotkey>" "Hotkey profile" ">" "*" "inline"
  PHYSICAL_HOTKEY_VISUAL="$("$CLI" test-control snapshot --json)"
  python3 - "$PHYSICAL_HOTKEY_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
checks = [
    (snapshot["panelVisible"], "panel is visible after physical CGEvent hotkey"),
    (snapshot["queryFieldFocused"], "query field is focused after physical CGEvent hotkey"),
    (snapshot["visibleRows"] >= 1, "physical CGEvent panel has visible rows"),
    (snapshot["layoutViolationCount"] == 0, "physical CGEvent panel layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
  "$CLI" test-control cancel >/tmp/fzf-palette-e2e-physical-hotkey-cancel.out
elif [[ "${FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY:-0}" == "1" ]]; then
  echo "$PHYSICAL_HOTKEY_OUTPUT" >&2
  exit "$PHYSICAL_HOTKEY_STATUS"
else
  echo "e2e physical-hotkey skipped: $PHYSICAL_HOTKEY_OUTPUT" >&2
fi

PHYSICAL_UI_OUT="$TMPDIR/physical-ui.out"
PHYSICAL_UI_ERR="$TMPDIR/physical-ui.err"
"$CLI" open --source-command "printf 'apple\nbanana\ncherry\n'" --timeout-ms 5000 >"$PHYSICAL_UI_OUT" 2>"$PHYSICAL_UI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 3
set +e
PHYSICAL_TYPE_OUTPUT="$("$CLI" test-control physical-type ban 2>&1)"
PHYSICAL_TYPE_STATUS=$?
set -e
if [[ "$PHYSICAL_TYPE_STATUS" -eq 0 ]]; then
  wait_for_picker_rows 1
  "$CLI" test-control physical-key return >/tmp/fzf-palette-e2e-physical-ui-return.out
  wait "$OPEN_PID"
  OPEN_PID=""
  if [[ "$(cat "$PHYSICAL_UI_OUT")" != "banana" ]]; then
    echo "expected physical keyboard accepted row banana, got:" >&2
    cat "$PHYSICAL_UI_OUT" >&2
    cat "$PHYSICAL_UI_ERR" >&2
    exit 1
  fi
elif [[ "${FZF_PALETTE_REQUIRE_PHYSICAL_UI:-0}" == "1" ]]; then
  echo "$PHYSICAL_TYPE_OUTPUT" >&2
  "$CLI" test-control cancel >/tmp/fzf-palette-e2e-physical-ui-cancel.out || true
  wait "$OPEN_PID" 2>/dev/null || true
  OPEN_PID=""
  exit "$PHYSICAL_TYPE_STATUS"
else
  echo "e2e physical-ui skipped: $PHYSICAL_TYPE_OUTPUT" >&2
  "$CLI" test-control cancel >/tmp/fzf-palette-e2e-physical-ui-cancel.out
  set +e
  wait "$OPEN_PID"
  set -e
  OPEN_PID=""
fi

"$CLI" test-control hotkey two-stage-profile >/tmp/fzf-palette-e2e-profile-hotkey-control.out
wait_for_picker_rows 2
wait_for_chrome "roots>" "Pick test root" ">" "*" "inline"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-profile-hotkey-cancel.out

"$CLI" test-control carbon-hotkey two-stage-profile >/tmp/fzf-palette-e2e-profile-carbon-hotkey-control.out
wait_for_picker_rows 2
wait_for_chrome "roots>" "Pick test root" ">" "*" "inline"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-profile-carbon-hotkey-cancel.out

PANEL_BENCH="$("$CLI" bench panel --runs 20 --warmup 2 --json)"
python3 - "$PANEL_BENCH" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
if report["failures"]:
    raise SystemExit("; ".join(report["failures"]))
metric = report["metrics"]["panel_show_ms"]
if metric["max"] >= 200:
    raise SystemExit(f"panel max {metric['max']}ms >= 200ms")
PY

MOVEMENT_BENCH="$("$CLI" bench movement --runs 36 --warmup 6 --json)"
python3 - "$MOVEMENT_BENCH" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
if report["failures"]:
    raise SystemExit("; ".join(report["failures"]))
metric = report["metrics"]["selection_movement_ms"]
if metric["max"] >= 16:
    raise SystemExit(f"selection movement max {metric['max']}ms >= 16ms")
PY

ACCEPT_OUT="$TMPDIR/accept.out"
ACCEPT_ERR="$TMPDIR/accept.err"
"$CLI" open --source-command "printf 'alpha\nbeta\n'" --timeout-ms 5000 >"$ACCEPT_OUT" 2>"$ACCEPT_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$ACCEPT_OUT")" != "alpha" ]]; then
  echo "expected accepted row alpha, got:" >&2
  cat "$ACCEPT_OUT" >&2
  cat "$ACCEPT_ERR" >&2
  exit 1
fi

DEFAULT_MULTI_OUT="$TMPDIR/default-multi.out"
DEFAULT_MULTI_ERR="$TMPDIR/default-multi.err"
"$CLI" open \
  --source-command "printf 'alpha\nbeta\n'" \
  --timeout-ms 5000 >"$DEFAULT_MULTI_OUT" 2>"$DEFAULT_MULTI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-default-multi-select-all-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-default-multi-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$DEFAULT_MULTI_OUT")" != $'alpha\nbeta' ]]; then
  echo "expected FZF_DEFAULT_OPTS -m to select alpha/beta, got:" >&2
  cat "$DEFAULT_MULTI_OUT" >&2
  cat "$DEFAULT_MULTI_ERR" >&2
  exit 1
fi

NO_MULTI_OUT="$TMPDIR/no-multi.out"
NO_MULTI_ERR="$TMPDIR/no-multi.err"
"$CLI" open \
  --source-command "printf 'alpha\nbeta\n'" \
  +m \
  --timeout-ms 5000 >"$NO_MULTI_OUT" 2>"$NO_MULTI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-no-multi-select-all-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-no-multi-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$NO_MULTI_OUT")" != "alpha" ]]; then
  echo "expected +m to override FZF_DEFAULT_OPTS -m and return alpha, got:" >&2
  cat "$NO_MULTI_OUT" >&2
  cat "$NO_MULTI_ERR" >&2
  exit 1
fi

DEFAULT_COMMAND_OUT="$TMPDIR/default-command.out"
DEFAULT_COMMAND_ERR="$TMPDIR/default-command.err"
"$CLI" open \
  --profile default \
  +m \
  --timeout-ms 5000 >"$DEFAULT_COMMAND_OUT" 2>"$DEFAULT_COMMAND_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-default-command-control.out
wait "$OPEN_PID"

if [[ "$(cat "$DEFAULT_COMMAND_OUT")" != "default-one" ]]; then
  echo "expected default profile to use FZF_DEFAULT_COMMAND and return default-one, got:" >&2
  cat "$DEFAULT_COMMAND_OUT" >&2
  cat "$DEFAULT_COMMAND_ERR" >&2
  exit 1
fi

CTRL_T_COMMAND_OUT="$TMPDIR/ctrl-t-command.out"
CTRL_T_COMMAND_ERR="$TMPDIR/ctrl-t-command.err"
"$CLI" open \
  --profile ctrl-t \
  +m \
  --timeout-ms 5000 >"$CTRL_T_COMMAND_OUT" 2>"$CTRL_T_COMMAND_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_chrome "files>" "Pick files" ">" "*" "inline"

"$CLI" test-control accept >/tmp/fzf-palette-e2e-ctrl-t-command-control.out
wait "$OPEN_PID"

if [[ "$(cat "$CTRL_T_COMMAND_OUT")" != "ctrl-t-one" ]]; then
  echo "expected ctrl-t profile to use FZF_CTRL_T_COMMAND and return ctrl-t-one, got:" >&2
  cat "$CTRL_T_COMMAND_OUT" >&2
  cat "$CTRL_T_COMMAND_ERR" >&2
  exit 1
fi

BUILTIN_REPOS_OUT="$TMPDIR/builtin-repos.out"
BUILTIN_REPOS_ERR="$TMPDIR/builtin-repos.err"
"$CLI" open \
  --profile repos \
  +m \
  --query /repos/repo-builtin \
  --timeout-ms 5000 >"$BUILTIN_REPOS_OUT" 2>"$BUILTIN_REPOS_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_chrome "repos>" "Pick a repo" "" "" "inline"

"$CLI" test-control accept >/tmp/fzf-palette-e2e-builtin-repos-control.out
wait "$OPEN_PID"

if [[ "$(cat "$BUILTIN_REPOS_OUT")" != "$BUILTIN_REPO" ]]; then
  echo "expected built-in repos profile result $BUILTIN_REPO, got:" >&2
  cat "$BUILTIN_REPOS_OUT" >&2
  cat "$BUILTIN_REPOS_ERR" >&2
  exit 1
fi

BUILTIN_DOWNLOADS_OUT="$TMPDIR/builtin-downloads.out"
BUILTIN_DOWNLOADS_ERR="$TMPDIR/builtin-downloads.err"
"$CLI" open \
  --profile downloads \
  +m \
  --query download-new \
  --timeout-ms 5000 >"$BUILTIN_DOWNLOADS_OUT" 2>"$BUILTIN_DOWNLOADS_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_chrome "downloads>" "Recent downloads" "" "" "inline"

"$CLI" test-control accept >/tmp/fzf-palette-e2e-builtin-downloads-control.out
wait "$OPEN_PID"

if [[ "$(cat "$BUILTIN_DOWNLOADS_OUT")" != "download-new.txt" ]]; then
  echo "expected built-in downloads profile result download-new.txt, got:" >&2
  cat "$BUILTIN_DOWNLOADS_OUT" >&2
  cat "$BUILTIN_DOWNLOADS_ERR" >&2
  exit 1
fi

BUILTIN_CONTEXT_OUT="$TMPDIR/builtin-context.out"
BUILTIN_CONTEXT_ERR="$TMPDIR/builtin-context.err"
"$CLI" open \
  --profile context-files \
  +m \
  --query project-builtin \
  --timeout-ms 5000 >"$BUILTIN_CONTEXT_OUT" 2>"$BUILTIN_CONTEXT_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_chrome "roots>" "Pick a root" "" "" "inline"
"$CLI" test-control accept >/tmp/fzf-palette-e2e-builtin-context-root-control.out
wait_for_picker_rows 3
wait_for_chrome "files>" "Pick a file or directory" "" "" "inline"
"$CLI" test-control query alpha.txt >/tmp/fzf-palette-e2e-builtin-context-query-control.out
wait_for_picker_rows 1
"$CLI" test-control accept >/tmp/fzf-palette-e2e-builtin-context-file-control.out
wait "$OPEN_PID"

if [[ "$(cat "$BUILTIN_CONTEXT_OUT")" != "$BUILTIN_PROJECT/alpha.txt" ]]; then
  echo "expected built-in context-files result $BUILTIN_PROJECT/alpha.txt, got:" >&2
  cat "$BUILTIN_CONTEXT_OUT" >&2
  cat "$BUILTIN_CONTEXT_ERR" >&2
  exit 1
fi

ALFRED_CONTEXT_OUT="$TMPDIR/alfred-context.out"
ALFRED_CONTEXT_ERR="$TMPDIR/alfred-context.err"
"$CLI" open \
  --profile context-files \
  +m \
  --timeout-ms 5000 >"$ALFRED_CONTEXT_OUT" 2>"$ALFRED_CONTEXT_ERR" &
OPEN_PID=$!

wait_for_panel_visible
"$CLI" test-control query ava >/tmp/fzf-palette-e2e-alfred-context-query-ava-control.out
wait_for_picker_rows 1
sleep 1.2
ALFRED_CONTEXT_ROOT_SNAPSHOT="$("$CLI" test-control snapshot --json)"
python3 - "$ALFRED_CONTEXT_ROOT_SNAPSHOT" "$BUILTIN_AVA" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = sys.argv[2]
if not snapshot.get("panelVisible"):
    raise SystemExit(f"panel disappeared after idle query ava: {snapshot}")
if not snapshot.get("queryFieldFocused"):
    raise SystemExit(f"query field lost focus after idle query ava: {snapshot}")
active = snapshot.get("activeRowText", "")
if expected not in active:
    raise SystemExit(f"expected ava root active before tab, got {snapshot}")
PY

"$CLI" test-control key tab >/tmp/fzf-palette-e2e-alfred-context-tab-control.out
wait_for_panel_visible
wait_for_chrome "files>" "Pick a file or directory" "" "" "inline"
"$CLI" test-control query gohan >/tmp/fzf-palette-e2e-alfred-context-query-gohan-control.out
wait_for_picker_rows 2
sleep 1.2
ALFRED_CONTEXT_INNER_SNAPSHOT="$("$CLI" test-control snapshot --json)"
python3 - "$ALFRED_CONTEXT_INNER_SNAPSHOT" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
if not snapshot.get("panelVisible"):
    raise SystemExit(f"panel disappeared after ava tab gohan: {snapshot}")
if not snapshot.get("queryFieldFocused"):
    raise SystemExit(f"query field lost focus after ava tab gohan: {snapshot}")
if "gohan" not in snapshot.get("activeRowText", ""):
    raise SystemExit(f"expected gohan result after ava tab gohan, got {snapshot}")
PY

"$CLI" test-control accept >/tmp/fzf-palette-e2e-alfred-context-accept-control.out
wait "$OPEN_PID"
OPEN_PID=""

if [[ "$(cat "$ALFRED_CONTEXT_OUT")" != "$BUILTIN_AVA/gohan" ]]; then
  echo "expected ava tab gohan result $BUILTIN_AVA/gohan, got:" >&2
  cat "$ALFRED_CONTEXT_OUT" >&2
  cat "$ALFRED_CONTEXT_ERR" >&2
  exit 1
fi

CHROME_OUT="$TMPDIR/chrome.out"
CHROME_ERR="$TMPDIR/chrome.err"
"$CLI" open \
  --source-command "printf 'chrome-target\n'" \
  --prompt "sessions>" \
  --header "Pick a session" \
  --pointer ">" \
  --marker "*" \
  --info inline \
  --timeout-ms 5000 >"$CHROME_OUT" 2>"$CHROME_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_chrome "sessions>" "Pick a session" ">" "*" "inline"

"$CLI" test-control accept >/tmp/fzf-palette-e2e-chrome-control.out
wait "$OPEN_PID"

if [[ "$(cat "$CHROME_OUT")" != "chrome-target" ]]; then
  echo "expected chrome picker output chrome-target, got:" >&2
  cat "$CHROME_OUT" >&2
  cat "$CHROME_ERR" >&2
  exit 1
fi

PROFILE_OUT="$TMPDIR/profile.out"
PROFILE_ERR="$TMPDIR/profile.err"
"$CLI" open \
  --profile config-profile \
  --timeout-ms 5000 >"$PROFILE_OUT" 2>"$PROFILE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_chrome "profile>" "Config profile" ">" "*" "inline"
wait_for_file_content "$PROFILE_PREVIEW_FILE" "$(printf 'profile-one\t/hidden/profile-one.json')"
"$CLI" test-control accept >/tmp/fzf-palette-e2e-profile-control.out
wait "$OPEN_PID"

if [[ "$(cat "$PROFILE_OUT")" != "/hidden/profile-one.json" ]]; then
  echo "expected profile result hidden path, got:" >&2
  cat "$PROFILE_OUT" >&2
  cat "$PROFILE_ERR" >&2
  exit 1
fi

TWO_STAGE_OUT="$TMPDIR/two-stage.out"
TWO_STAGE_ERR="$TMPDIR/two-stage.err"
"$CLI" open \
  --profile two-stage-profile \
  --timeout-ms 5000 >"$TWO_STAGE_OUT" 2>"$TWO_STAGE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_chrome "roots>" "Pick test root" ">" "*" "inline"
"$CLI" test-control accept >/tmp/fzf-palette-e2e-two-stage-root-control.out
wait_for_picker_rows 3
wait_for_chrome "files>" "Pick test file" ">" "*" "inline"
wait_for_file_content "$TWO_STAGE_PREVIEW_FILE" "$(printf 'alpha.txt\t%s/alpha.txt' "$TWO_STAGE_ROOT")"
"$CLI" test-control accept >/tmp/fzf-palette-e2e-two-stage-file-control.out
wait "$OPEN_PID"

if [[ "$(cat "$TWO_STAGE_OUT")" != "$TWO_STAGE_ROOT/alpha.txt" ]]; then
  echo "expected two-stage hidden file path $TWO_STAGE_ROOT/alpha.txt, got:" >&2
  cat "$TWO_STAGE_OUT" >&2
  cat "$TWO_STAGE_ERR" >&2
  exit 1
fi

QUERY_OUT="$TMPDIR/query.out"
QUERY_ERR="$TMPDIR/query.err"
"$CLI" open \
  --source-command "printf 'alpha\nbeta\ngamma\n'" \
  --query beta \
  --timeout-ms 5000 >"$QUERY_OUT" 2>"$QUERY_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-query-control.out
wait "$OPEN_PID"

if [[ "$(cat "$QUERY_OUT")" != "beta" ]]; then
  echo "expected initial query result beta, got:" >&2
  cat "$QUERY_OUT" >&2
  cat "$QUERY_ERR" >&2
  exit 1
fi

CASE_OUT="$TMPDIR/case.out"
CASE_ERR="$TMPDIR/case.err"
"$CLI" open \
  --source-command "printf 'Readme.md\nREADME.md\nreadme.md\n'" \
  +i \
  --query REA \
  --timeout-ms 5000 >"$CASE_OUT" 2>"$CASE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-case-control.out
wait "$OPEN_PID"

if [[ "$(cat "$CASE_OUT")" != "README.md" ]]; then
  echo "expected case-sensitive +i result README.md, got:" >&2
  cat "$CASE_OUT" >&2
  cat "$CASE_ERR" >&2
  exit 1
fi

ANSI_OUT="$TMPDIR/ansi.out"
ANSI_ERR="$TMPDIR/ansi.err"
"$CLI" open \
  --source-command "printf '\033[31mred-target\033[0m\nblue-target\n'" \
  --ansi \
  --query red \
  --timeout-ms 5000 >"$ANSI_OUT" 2>"$ANSI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-ansi-control.out
wait "$OPEN_PID"

if [[ "$(cat "$ANSI_OUT")" != "red-target" ]]; then
  echo "expected ANSI-stripped result red-target, got:" >&2
  cat "$ANSI_OUT" >&2
  cat "$ANSI_ERR" >&2
  exit 1
fi

TIEBREAK_OUT="$TMPDIR/tiebreak.out"
TIEBREAK_ERR="$TMPDIR/tiebreak.err"
"$CLI" open \
  --source-command "printf 'abcxxxx\nabc\n'" \
  --tiebreak=index \
  --query abc \
  --timeout-ms 5000 >"$TIEBREAK_OUT" 2>"$TIEBREAK_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-tiebreak-control.out
wait "$OPEN_PID"

if [[ "$(cat "$TIEBREAK_OUT")" != "abcxxxx" ]]; then
  echo "expected --tiebreak=index result abcxxxx, got:" >&2
  cat "$TIEBREAK_OUT" >&2
  cat "$TIEBREAK_ERR" >&2
  exit 1
fi

TIEBREAK_LIST_OUT="$TMPDIR/tiebreak-list.out"
TIEBREAK_LIST_ERR="$TMPDIR/tiebreak-list.err"
"$CLI" open \
  --source-command "printf 'xxabc\nabcxx\nxabcx\nabc\n'" \
  --tiebreak=begin,end \
  --query abc \
  --timeout-ms 5000 >"$TIEBREAK_LIST_OUT" 2>"$TIEBREAK_LIST_ERR" &
OPEN_PID=$!

wait_for_picker_rows 4

"$CLI" test-control accept >/tmp/fzf-palette-e2e-tiebreak-list-control.out
wait "$OPEN_PID"

if [[ "$(cat "$TIEBREAK_LIST_OUT")" != "abc" ]]; then
  echo "expected --tiebreak=begin,end result abc, got:" >&2
  cat "$TIEBREAK_LIST_OUT" >&2
  cat "$TIEBREAK_LIST_ERR" >&2
  exit 1
fi

TIEBREAK_CHUNK_OUT="$TMPDIR/tiebreak-chunk.out"
TIEBREAK_CHUNK_ERR="$TMPDIR/tiebreak-chunk.err"
"$CLI" open \
  --source-command "printf '1 foobarbaz ba\n2 foobar baz\n3 foo barbaz\n'" \
  --tiebreak=chunk \
  --query o \
  --timeout-ms 5000 >"$TIEBREAK_CHUNK_OUT" 2>"$TIEBREAK_CHUNK_ERR" &
OPEN_PID=$!

wait_for_picker_rows 3

"$CLI" test-control accept >/tmp/fzf-palette-e2e-tiebreak-chunk-control.out
wait "$OPEN_PID"

if [[ "$(cat "$TIEBREAK_CHUNK_OUT")" != "3 foo barbaz" ]]; then
  echo "expected --tiebreak=chunk result '3 foo barbaz', got:" >&2
  cat "$TIEBREAK_CHUNK_OUT" >&2
  cat "$TIEBREAK_CHUNK_ERR" >&2
  exit 1
fi

NO_SORT_OUT="$TMPDIR/no-sort.out"
NO_SORT_ERR="$TMPDIR/no-sort.err"
"$CLI" open \
  --source-command "printf 'axbycz\nabc\n'" \
  --no-sort \
  --query abc \
  --timeout-ms 5000 >"$NO_SORT_OUT" 2>"$NO_SORT_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-no-sort-control.out
wait "$OPEN_PID"

if [[ "$(cat "$NO_SORT_OUT")" != "axbycz" ]]; then
  echo "expected --no-sort result axbycz, got:" >&2
  cat "$NO_SORT_OUT" >&2
  cat "$NO_SORT_ERR" >&2
  exit 1
fi

PATH_SCHEME_OUT="$TMPDIR/path-scheme.out"
PATH_SCHEME_ERR="$TMPDIR/path-scheme.err"
"$CLI" open \
  --source-command "printf 'foo/bar/baz/qux.txt\nfoo-baz-qux.txt\nbar/foo/qux-baz.txt\nqux/foo/bar/baz.txt\nqux.txt\n'" \
  --scheme=path \
  --query qux \
  --timeout-ms 5000 >"$PATH_SCHEME_OUT" 2>"$PATH_SCHEME_ERR" &
OPEN_PID=$!

wait_for_picker_rows 5

"$CLI" test-control accept >/tmp/fzf-palette-e2e-path-scheme-control.out
wait "$OPEN_PID"

if [[ "$(cat "$PATH_SCHEME_OUT")" != "qux.txt" ]]; then
  echo "expected --scheme=path result qux.txt, got:" >&2
  cat "$PATH_SCHEME_OUT" >&2
  cat "$PATH_SCHEME_ERR" >&2
  exit 1
fi

HISTORY_SCHEME_OUT="$TMPDIR/history-scheme.out"
HISTORY_SCHEME_ERR="$TMPDIR/history-scheme.err"
"$CLI" open \
  --source-command "printf 'abcxxxx\nabc\nxabcx\nxxabc\n'" \
  --scheme=history \
  --tiebreak=length \
  --query abc \
  --timeout-ms 5000 >"$HISTORY_SCHEME_OUT" 2>"$HISTORY_SCHEME_ERR" &
OPEN_PID=$!

wait_for_picker_rows 4

"$CLI" test-control accept >/tmp/fzf-palette-e2e-history-scheme-control.out
wait "$OPEN_PID"

if [[ "$(cat "$HISTORY_SCHEME_OUT")" != "abcxxxx" ]]; then
  echo "expected --scheme=history score-only result abcxxxx, got:" >&2
  cat "$HISTORY_SCHEME_OUT" >&2
  cat "$HISTORY_SCHEME_ERR" >&2
  exit 1
fi

NTH_OUT="$TMPDIR/nth.out"
NTH_ERR="$TMPDIR/nth.err"
"$CLI" open \
  --source-command "printf 'src/App.swift:10:1:alpha match\ndocs/App.md:20:1:alpha match\nsrc/Other.swift:30:1:beta match\n'" \
  --delimiter ":" \
  --nth 1 \
  --query src \
  --timeout-ms 5000 >"$NTH_OUT" 2>"$NTH_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-nth-control.out
wait "$OPEN_PID"

if [[ "$(cat "$NTH_OUT")" != "src/App.swift:10:1:alpha match" ]]; then
  echo "expected --nth result src/App.swift:10:1:alpha match, got:" >&2
  cat "$NTH_OUT" >&2
  cat "$NTH_ERR" >&2
  exit 1
fi

FIELDS_OUT="$TMPDIR/fields.out"
FIELDS_ERR="$TMPDIR/fields.err"
TAB=$'\t'
"$CLI" open \
  --source-command "printf 'friendly${TAB}/tmp/session.json\nother${TAB}/tmp/other.json\n'" \
  --delimiter "$TAB" \
  --with-nth 1 \
  --result-fields 2 \
  --timeout-ms 5000 >"$FIELDS_OUT" 2>"$FIELDS_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control accept >/tmp/fzf-palette-e2e-fields-control.out
wait "$OPEN_PID"

if [[ "$(cat "$FIELDS_OUT")" != "/tmp/session.json" ]]; then
  echo "expected hidden result field /tmp/session.json, got:" >&2
  cat "$FIELDS_OUT" >&2
  cat "$FIELDS_ERR" >&2
  exit 1
fi

MULTI_OUT="$TMPDIR/multi.out"
MULTI_ERR="$TMPDIR/multi.err"
"$CLI" open \
  --source-command "printf 'alpha\nbeta\ngamma\n'" \
  --multi \
  --timeout-ms 5000 >"$MULTI_OUT" 2>"$MULTI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 3

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-multi-select-all-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-multi-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$MULTI_OUT")" != $'alpha\nbeta\ngamma' ]]; then
  echo "expected multi result alpha/beta/gamma, got:" >&2
  cat "$MULTI_OUT" >&2
  cat "$MULTI_ERR" >&2
  exit 1
fi

MULTI_SPACE_OUT="$TMPDIR/multi-space.out"
MULTI_SPACE_ERR="$TMPDIR/multi-space.err"
"$CLI" open \
  --source-command "printf 'friendly${TAB}/hidden/session.json\nother${TAB}/hidden/other.json\n'" \
  --multi \
  --delimiter "$TAB" \
  --with-nth 1 \
  --result-fields 2 \
  --join space \
  --timeout-ms 5000 >"$MULTI_SPACE_OUT" 2>"$MULTI_SPACE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-multi-space-select-all-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-multi-space-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$MULTI_SPACE_OUT")" != "/hidden/session.json /hidden/other.json" ]]; then
  echo "expected space-joined hidden multi result, got:" >&2
  cat "$MULTI_SPACE_OUT" >&2
  cat "$MULTI_SPACE_ERR" >&2
  exit 1
fi

MULTI_JSON_OUT="$TMPDIR/multi-json.out"
MULTI_JSON_ERR="$TMPDIR/multi-json.err"
"$CLI" open \
  --source-command "printf 'json-one${TAB}/hidden/json-one.json\njson-two${TAB}/hidden/json-two.json\n'" \
  --multi \
  --delimiter "$TAB" \
  --with-nth 1 \
  --result-fields 2 \
  --join json \
  --timeout-ms 5000 >"$MULTI_JSON_OUT" 2>"$MULTI_JSON_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-multi-json-select-all-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-multi-json-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$MULTI_JSON_OUT")" != '["/hidden/json-one.json","/hidden/json-two.json"]' ]]; then
  echo "expected json hidden multi result, got:" >&2
  cat "$MULTI_JSON_OUT" >&2
  cat "$MULTI_JSON_ERR" >&2
  exit 1
fi

MULTI_TOGGLE_OUT="$TMPDIR/multi-toggle.out"
MULTI_TOGGLE_ERR="$TMPDIR/multi-toggle.err"
"$CLI" open \
  --source-command "printf 'toggle-alpha\ntoggle-beta\n'" \
  --multi \
  --timeout-ms 5000 >"$MULTI_TOGGLE_OUT" 2>"$MULTI_TOGGLE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2

"$CLI" test-control select-all >/tmp/fzf-palette-e2e-multi-toggle-select-all-control.out
"$CLI" test-control deselect-all >/tmp/fzf-palette-e2e-multi-toggle-deselect-all-control.out
"$CLI" test-control toggle >/tmp/fzf-palette-e2e-multi-toggle-control.out
"$CLI" test-control accept >/tmp/fzf-palette-e2e-multi-toggle-accept-control.out
wait "$OPEN_PID"

if [[ "$(cat "$MULTI_TOGGLE_OUT")" != "toggle-alpha" ]]; then
  echo "expected toggled multi result toggle-alpha, got:" >&2
  cat "$MULTI_TOGGLE_OUT" >&2
  cat "$MULTI_TOGGLE_ERR" >&2
  exit 1
fi

COPY_OUT="$TMPDIR/copy.out"
COPY_ERR="$TMPDIR/copy.err"
"$CLI" open \
  --source-command "printf 'copy-target\n'" \
  --result copy \
  --timeout-ms 5000 >"$COPY_OUT" 2>"$COPY_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-copy-control.out
wait "$OPEN_PID"

if [[ "$(cat "$COPY_OUT")" != "copy-target" ]]; then
  echo "expected copy result output copy-target, got:" >&2
  cat "$COPY_OUT" >&2
  cat "$COPY_ERR" >&2
  exit 1
fi

if [[ "$(pbpaste)" != "copy-target" ]]; then
  echo "expected pasteboard copy-target, got:" >&2
  pbpaste >&2 || true
  exit 1
fi

PASTE_OUT="$TMPDIR/paste.out"
PASTE_ERR="$TMPDIR/paste.err"
"$CLI" open \
  --source-command "printf 'paste-target\n'" \
  --result paste \
  --timeout-ms 5000 >"$PASTE_OUT" 2>"$PASTE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-paste-control.out
wait "$OPEN_PID"

if [[ "$(cat "$PASTE_OUT")" != "paste-target" ]]; then
  echo "expected paste result output paste-target, got:" >&2
  cat "$PASTE_OUT" >&2
  cat "$PASTE_ERR" >&2
  exit 1
fi

if [[ "$(pbpaste)" != "paste-target" ]]; then
  echo "expected pasteboard paste-target, got:" >&2
  pbpaste >&2 || true
  exit 1
fi

if [[ "$(cat "$PASTE_LOG")" != "paste-target" ]]; then
  echo "expected side-effect-safe paste log paste-target, got:" >&2
  cat "$PASTE_LOG" >&2 || true
  exit 1
fi

OPEN_OUT="$TMPDIR/open.out"
OPEN_ERR="$TMPDIR/open.err"
"$CLI" open \
  --source-command "printf 'open-target\n'" \
  --result open \
  --timeout-ms 5000 >"$OPEN_OUT" 2>"$OPEN_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-open-control.out
wait "$OPEN_PID"

if [[ "$(cat "$OPEN_OUT")" != "open-target" ]]; then
  echo "expected open result output open-target, got:" >&2
  cat "$OPEN_OUT" >&2
  cat "$OPEN_ERR" >&2
  exit 1
fi

if [[ "$(cat "$OPEN_LOG")" != "open-target" ]]; then
  echo "expected side-effect-safe open log open-target, got:" >&2
  cat "$OPEN_LOG" >&2 || true
  exit 1
fi

RESULT_COMMAND_FILE="$TMPDIR/result-command.out"
COMMAND_OUT="$TMPDIR/command.out"
COMMAND_ERR="$TMPDIR/command.err"
"$CLI" open \
  --source-command "printf 'cmd-target\n'" \
  --result command \
  --result-command "printf '%s' {} > '$RESULT_COMMAND_FILE'" \
  --timeout-ms 5000 >"$COMMAND_OUT" 2>"$COMMAND_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1

"$CLI" test-control accept >/tmp/fzf-palette-e2e-command-control.out
wait "$OPEN_PID"

if [[ "$(cat "$COMMAND_OUT")" != "cmd-target" ]]; then
  echo "expected command result output cmd-target, got:" >&2
  cat "$COMMAND_OUT" >&2
  cat "$COMMAND_ERR" >&2
  exit 1
fi

if [[ "$(cat "$RESULT_COMMAND_FILE")" != "cmd-target" ]]; then
  echo "expected result command file cmd-target, got:" >&2
  cat "$RESULT_COMMAND_FILE" >&2 || true
  exit 1
fi

PREVIEW_CURSOR_FILE="$TMPDIR/preview-cursor.out"
PREVIEW_CURSOR_STDOUT="$TMPDIR/preview-cursor-open.out"
PREVIEW_CURSOR_STDERR="$TMPDIR/preview-cursor-open.err"
"$CLI" open \
  --source-command "printf 'cursor-one\ncursor-two\n'" \
  --preview-command "printf '%s' {} > '$PREVIEW_CURSOR_FILE'" \
  --timeout-ms 5000 >"$PREVIEW_CURSOR_STDOUT" 2>"$PREVIEW_CURSOR_STDERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_file_content "$PREVIEW_CURSOR_FILE" "cursor-one"
"$CLI" test-control move-down >/tmp/fzf-palette-e2e-preview-move-down-control.out
wait_for_file_content "$PREVIEW_CURSOR_FILE" "cursor-two"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-cursor-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_CURSOR_CODE=$?
set -e

if [[ "$PREVIEW_CURSOR_CODE" -eq 0 ]]; then
  echo "expected preview cursor picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_QUERY_FILE="$TMPDIR/preview-query.out"
PREVIEW_QUERY_STDOUT="$TMPDIR/preview-query-open.out"
PREVIEW_QUERY_STDERR="$TMPDIR/preview-query-open.err"
"$CLI" open \
  --source-command "printf 'apple\nbanana\n'" \
  --preview-command "printf '%s' {} > '$PREVIEW_QUERY_FILE'" \
  --timeout-ms 5000 >"$PREVIEW_QUERY_STDOUT" 2>"$PREVIEW_QUERY_STDERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_file_content "$PREVIEW_QUERY_FILE" "apple"
"$CLI" test-control query banana >/tmp/fzf-palette-e2e-preview-query-control.out
wait_for_file_content "$PREVIEW_QUERY_FILE" "banana"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-query-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_QUERY_CODE=$?
set -e

if [[ "$PREVIEW_QUERY_CODE" -eq 0 ]]; then
  echo "expected preview query picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_ANSI_OUT="$TMPDIR/preview-ansi.out"
PREVIEW_ANSI_ERR="$TMPDIR/preview-ansi.err"
"$CLI" open \
  --source-command "printf 'ansi-preview\n'" \
  --preview-command "printf '\\033[3;4;38;5;196;48;2;10;20;30mrich\\033[0m-\\033[2;38;2;1;2;3mdim\\033[0m'" \
  --timeout-ms 5000 >"$PREVIEW_ANSI_OUT" 2>"$PREVIEW_ANSI_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_preview_ansi_spans 2
PREVIEW_ANSI_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_ANSI_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
checks = [
    (snapshot["previewVisible"], "ANSI preview is visible"),
    (snapshot["previewAnsiSpanCount"] >= 2, "ANSI preview has styled spans"),
    (snapshot["previewAnsiRGBSpanCount"] >= 2, "ANSI preview has RGB/256-color spans"),
    (snapshot["previewAnsiBackgroundSpanCount"] >= 1, "ANSI preview has background spans"),
    (snapshot["previewAnsiTextStyleSpanCount"] >= 2, "ANSI preview has text-style spans"),
    (not snapshot["previewContainsEscapeSequences"], "ANSI preview strips raw escape sequences"),
    (snapshot["previewCharacterCount"] == len("rich-dim"), "ANSI preview text is stripped to visible content"),
    (snapshot["layoutViolationCount"] == 0, "ANSI preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-ansi-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_ANSI_CODE=$?
set -e

if [[ "$PREVIEW_ANSI_CODE" -eq 0 ]]; then
  echo "expected preview ANSI picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_TERMINAL_OUT="$TMPDIR/preview-terminal.out"
PREVIEW_TERMINAL_ERR="$TMPDIR/preview-terminal.err"
"$CLI" open \
  --source-command "printf 'terminal-preview\n'" \
  --preview-command "printf 'loading 10%%\r\033[2K\033[32mdone\033[0m\nfirst\nsecond\033[1A\r\033[2Kfinal\033[1B\r\033[2Ktail'" \
  --timeout-ms 5000 >"$PREVIEW_TERMINAL_OUT" 2>"$PREVIEW_TERMINAL_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
for _ in {1..50}; do
  PREVIEW_TERMINAL_VISUAL="$("$CLI" test-control snapshot --json)"
  if python3 - "$PREVIEW_TERMINAL_VISUAL" $'done\nfinal\ntail' <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = sys.argv[2]
raise SystemExit(0 if snapshot.get("previewTextSample") == expected else 1)
PY
  then
    break
  fi
  sleep 0.1
done

PREVIEW_TERMINAL_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_TERMINAL_VISUAL" $'done\nfinal\ntail' <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = sys.argv[2]
checks = [
    (snapshot["previewVisible"], "terminal-control preview is visible"),
    (snapshot["previewTextSample"] == expected, f"terminal-control preview text is {expected!r}"),
    (snapshot["previewAnsiSpanCount"] >= 1, "terminal-control preview keeps final SGR styling"),
    (not snapshot["previewContainsEscapeSequences"], "terminal-control preview strips raw escape sequences"),
    (snapshot["previewCharacterCount"] == len(expected), "terminal-control preview character count matches final screen"),
    (snapshot["layoutViolationCount"] == 0, "terminal-control preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-terminal-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_TERMINAL_CODE=$?
set -e

if [[ "$PREVIEW_TERMINAL_CODE" -eq 0 ]]; then
  echo "expected preview terminal-control picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_TERMINAL_LINES_OUT="$TMPDIR/preview-terminal-lines.out"
PREVIEW_TERMINAL_LINES_ERR="$TMPDIR/preview-terminal-lines.err"
"$CLI" open \
  --source-command "printf 'terminal-lines-preview\n'" \
  --preview-command "printf 'one\ntwo\nthree\033[2;1H\033[M\033[2;1H\033[Linsert\033[1S\033[1T\rscroll'" \
  --timeout-ms 5000 >"$PREVIEW_TERMINAL_LINES_OUT" 2>"$PREVIEW_TERMINAL_LINES_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
for _ in {1..50}; do
  PREVIEW_TERMINAL_LINES_VISUAL="$("$CLI" test-control snapshot --json)"
  if python3 - "$PREVIEW_TERMINAL_LINES_VISUAL" $'\nscroll\nthree' <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = sys.argv[2]
raise SystemExit(0 if snapshot.get("previewTextSample") == expected else 1)
PY
  then
    break
  fi
  sleep 0.1
done

PREVIEW_TERMINAL_LINES_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_TERMINAL_LINES_VISUAL" $'\nscroll\nthree' <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
expected = sys.argv[2]
checks = [
    (snapshot["previewVisible"], "terminal line-control preview is visible"),
    (snapshot["previewTextSample"] == expected, f"terminal line-control preview text is {expected!r}"),
    (not snapshot["previewContainsEscapeSequences"], "terminal line-control preview strips raw escape sequences"),
    (snapshot["previewCharacterCount"] == len(expected), "terminal line-control preview character count matches final screen"),
    (snapshot["layoutViolationCount"] == 0, "terminal line-control preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-terminal-lines-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_TERMINAL_LINES_CODE=$?
set -e

if [[ "$PREVIEW_TERMINAL_LINES_CODE" -eq 0 ]]; then
  echo "expected preview terminal line-control picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_TOGGLE_OUT="$TMPDIR/preview-toggle.out"
PREVIEW_TOGGLE_ERR="$TMPDIR/preview-toggle.err"
"$CLI" open \
  --source-command "printf 'apple\nbanana\n'" \
  --preview-command "printf '%s' {}" \
  --bind "ctrl-/:toggle-preview" \
  --timeout-ms 5000 >"$PREVIEW_TOGGLE_OUT" 2>"$PREVIEW_TOGGLE_ERR" &
OPEN_PID=$!

wait_for_picker_rows 2
wait_for_preview_visible_state true
PREVIEW_VISUAL_BEFORE="$("$CLI" test-control snapshot --json)"

if [[ "$("$CLI" test-control toggle-preview)" != "preview:hidden" ]]; then
  echo "expected preview:hidden after toggle-preview" >&2
  exit 1
fi
wait_for_preview_visible_state false
PREVIEW_VISUAL_HIDDEN="$("$CLI" test-control snapshot --json)"

if [[ "$("$CLI" test-control toggle-preview)" != "preview:visible" ]]; then
  echo "expected preview:visible after second toggle-preview" >&2
  exit 1
fi
wait_for_preview_visible_state true
PREVIEW_VISUAL_AFTER="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_VISUAL_BEFORE" "$PREVIEW_VISUAL_HIDDEN" "$PREVIEW_VISUAL_AFTER" <<'PY'
import json
import sys
before = json.loads(sys.argv[1])
hidden = json.loads(sys.argv[2])
after = json.loads(sys.argv[3])

def stable_size(left, right):
    return abs(left["width"] - right["width"]) <= 1 and abs(left["height"] - right["height"]) <= 1

checks = [
    (before["previewVisible"], "preview starts visible"),
    (before["previewWidth"] >= 200, "preview starts with real width"),
    (before["layoutViolationCount"] == 0, "preview-visible layout has no violations"),
    (not hidden["previewVisible"], "preview hides after toggle"),
    (stable_size(before, hidden), "panel size remains stable when preview hides"),
    (hidden["layoutViolationCount"] == 0, "preview-hidden layout has no violations"),
    (after["previewVisible"], "preview becomes visible again"),
    (after["previewWidth"] >= 200, "preview regains real width"),
    (after["previewCharacterCount"] > 0, "preview content remains rendered"),
    (after["layoutViolationCount"] == 0, "preview-restored layout has no violations"),
    (stable_size(before, after), "panel size remains stable when preview returns"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; before={before}; hidden={hidden}; after={after}")
PY

"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-toggle-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_TOGGLE_CODE=$?
set -e

if [[ "$PREVIEW_TOGGLE_CODE" -eq 0 ]]; then
  echo "expected preview toggle picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_RIGHT_OUT="$TMPDIR/preview-right.out"
PREVIEW_RIGHT_ERR="$TMPDIR/preview-right.err"
"$CLI" open \
  --source-command "printf 'layout-right\n'" \
  --preview-command "printf '%s' {}" \
  --preview-window "right:60%:wrap" \
  --timeout-ms 5000 >"$PREVIEW_RIGHT_OUT" 2>"$PREVIEW_RIGHT_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
PREVIEW_RIGHT_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_RIGHT_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
total = snapshot["previewWidth"] + snapshot["resultsWidth"]
fraction = snapshot["previewWidth"] / total if total else 0
checks = [
    (snapshot["previewVisible"], "right preview is visible"),
    (snapshot["previewPosition"] == "right", "right preview reports right position"),
    (snapshot["previewWrap"], "right preview applies wrap"),
    (0.52 <= fraction <= 0.68, f"right preview fraction near 60%, got {fraction:.3f}"),
    (snapshot["previewWidth"] > snapshot["resultsWidth"], "right preview is wider than results"),
    (snapshot["layoutViolationCount"] == 0, "right preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-right-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_RIGHT_CODE=$?
set -e

if [[ "$PREVIEW_RIGHT_CODE" -eq 0 ]]; then
  echo "expected preview right picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_UP_OUT="$TMPDIR/preview-up.out"
PREVIEW_UP_ERR="$TMPDIR/preview-up.err"
"$CLI" open \
  --source-command "printf 'layout-up\n'" \
  --preview-command "printf '%s' {}" \
  --preview-window "up:60%" \
  --timeout-ms 5000 >"$PREVIEW_UP_OUT" 2>"$PREVIEW_UP_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
PREVIEW_UP_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_UP_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
total = snapshot["previewHeight"] + snapshot["resultsHeight"]
fraction = snapshot["previewHeight"] / total if total else 0
checks = [
    (snapshot["previewVisible"], "up preview is visible"),
    (snapshot["previewPosition"] == "up", "up preview reports up position"),
    (not snapshot["previewWrap"], "up preview leaves wrap disabled"),
    (0.52 <= fraction <= 0.68, f"up preview fraction near 60%, got {fraction:.3f}"),
    (snapshot["previewHeight"] > snapshot["resultsHeight"], "up preview is taller than results"),
    (snapshot["previewWidth"] >= 800 and snapshot["resultsWidth"] >= 800, "up preview uses full split width"),
    (snapshot["layoutViolationCount"] == 0, "up preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-up-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_UP_CODE=$?
set -e

if [[ "$PREVIEW_UP_CODE" -eq 0 ]]; then
  echo "expected preview up picker cancellation to exit nonzero" >&2
  exit 1
fi

PREVIEW_SCROLL_OUT="$TMPDIR/preview-scroll.out"
PREVIEW_SCROLL_ERR="$TMPDIR/preview-scroll.err"
"$CLI" open \
  --source-command "printf 'Sources/App.swift:80:body\n'" \
  --delimiter ":" \
  --preview-command "for i in {1..120}; do printf 'line-%03d\n' \$i; done" \
  --preview-window "+{2}-/2" \
  --timeout-ms 5000 >"$PREVIEW_SCROLL_OUT" 2>"$PREVIEW_SCROLL_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_preview_scroll_offset 100
PREVIEW_SCROLL_VISUAL="$("$CLI" test-control snapshot --json)"
python3 - "$PREVIEW_SCROLL_VISUAL" <<'PY'
import json
import sys
snapshot = json.loads(sys.argv[1])
checks = [
    (snapshot["previewVisible"], "scroll preview is visible"),
    (snapshot["previewScrollOffsetY"] > 100, f"scroll preview moved down, got {snapshot['previewScrollOffsetY']}"),
    (snapshot["previewCharacterCount"] > 1000, "scroll preview has long rendered content"),
    (snapshot["layoutViolationCount"] == 0, "scroll preview layout has no violations"),
]
failed = [message for ok, message in checks if not ok]
if failed:
    raise SystemExit("; ".join(failed) + f"; snapshot={snapshot}")
PY
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-scroll-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_SCROLL_CODE=$?
set -e

if [[ "$PREVIEW_SCROLL_CODE" -eq 0 ]]; then
  echo "expected preview scroll picker cancellation to exit nonzero" >&2
  exit 1
fi

RESULT_COMMAND_PID_FILE="$TMPDIR/result-command-child.pid"
RESULT_COMMAND_CANCEL_OUT="$TMPDIR/result-command-cancel.out"
RESULT_COMMAND_CANCEL_ERR="$TMPDIR/result-command-cancel.err"
"$CLI" open \
  --source-command "printf 'cmd-cancel-target\n'" \
  --result command \
  --result-command "sleep 30 & echo \\$! > '$RESULT_COMMAND_PID_FILE'; wait" \
  --timeout-ms 10000 >"$RESULT_COMMAND_CANCEL_OUT" 2>"$RESULT_COMMAND_CANCEL_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
"$CLI" test-control accept >/tmp/fzf-palette-e2e-command-cancel-accept-control.out
wait_for_file "$RESULT_COMMAND_PID_FILE"
RESULT_COMMAND_CHILD_PID="$(cat "$RESULT_COMMAND_PID_FILE")"
"$CLI" cancel >/tmp/fzf-palette-e2e-command-cancel-control.out
set +e
wait "$OPEN_PID"
RESULT_COMMAND_CANCEL_CODE=$?
set -e

if [[ "$RESULT_COMMAND_CANCEL_CODE" -eq 0 ]]; then
  echo "expected result command cancellation picker to exit nonzero" >&2
  exit 1
fi
assert_pid_dead "$RESULT_COMMAND_CHILD_PID"

SOURCE_PID_FILE="$TMPDIR/source-child.pid"
SOURCE_CANCEL_OUT="$TMPDIR/source-cancel.out"
SOURCE_CANCEL_ERR="$TMPDIR/source-cancel.err"
"$CLI" open \
  --source-command "sleep 30 & echo \\$! > '$SOURCE_PID_FILE'; echo ready; wait" \
  --timeout-ms 5000 >"$SOURCE_CANCEL_OUT" 2>"$SOURCE_CANCEL_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_file "$SOURCE_PID_FILE"
SOURCE_CHILD_PID="$(cat "$SOURCE_PID_FILE")"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-source-cancel-control.out
set +e
wait "$OPEN_PID"
SOURCE_CANCEL_CODE=$?
set -e

if [[ "$SOURCE_CANCEL_CODE" -eq 0 ]]; then
  echo "expected source cancellation picker to exit nonzero" >&2
  exit 1
fi
assert_pid_dead "$SOURCE_CHILD_PID"

PREVIEW_PID_FILE="$TMPDIR/preview-child.pid"
PREVIEW_CANCEL_OUT="$TMPDIR/preview-cancel.out"
PREVIEW_CANCEL_ERR="$TMPDIR/preview-cancel.err"
"$CLI" open \
  --source-command "printf 'preview-target\n'" \
  --preview-command "sleep 30 & echo \\$! > '$PREVIEW_PID_FILE'; wait" \
  --timeout-ms 5000 >"$PREVIEW_CANCEL_OUT" 2>"$PREVIEW_CANCEL_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
wait_for_file "$PREVIEW_PID_FILE"
PREVIEW_CHILD_PID="$(cat "$PREVIEW_PID_FILE")"
"$CLI" test-control cancel >/tmp/fzf-palette-e2e-preview-cancel-control.out
set +e
wait "$OPEN_PID"
PREVIEW_CANCEL_CODE=$?
set -e

if [[ "$PREVIEW_CANCEL_CODE" -eq 0 ]]; then
  echo "expected preview cancellation picker to exit nonzero" >&2
  exit 1
fi
assert_pid_dead "$PREVIEW_CHILD_PID"

CANCEL_OUT="$TMPDIR/cancel.out"
CANCEL_ERR="$TMPDIR/cancel.err"
set +e
"$CLI" open --source-command "printf 'gamma\ndelta\n'" --timeout-ms 5000 >"$CANCEL_OUT" 2>"$CANCEL_ERR" &
OPEN_PID=$!
set -e

wait_for_picker_rows 2

"$CLI" test-control cancel >/tmp/fzf-palette-e2e-cancel-control.out
set +e
wait "$OPEN_PID"
CANCEL_CODE=$?
set -e

if [[ "$CANCEL_CODE" -eq 0 ]]; then
  echo "expected cancelled picker to exit nonzero" >&2
  exit 1
fi

if ! grep -q "cancelled" "$CANCEL_ERR"; then
  echo "expected cancel error message, got:" >&2
  cat "$CANCEL_ERR" >&2
  exit 1
fi

ORPHANED_CLIENT_OUT="$TMPDIR/orphaned-client.out"
ORPHANED_CLIENT_ERR="$TMPDIR/orphaned-client.err"
"$CLI" open \
  --source-command "printf 'orphaned-client-row\n'" \
  --timeout-ms 600000 >"$ORPHANED_CLIENT_OUT" 2>"$ORPHANED_CLIENT_ERR" &
OPEN_PID=$!

wait_for_picker_rows 1
ORPHANED_CLIENT_PID_BEFORE="$("$CLI" status --json)"
kill "$OPEN_PID" 2>/dev/null || true
set +e
wait "$OPEN_PID"
set -e
OPEN_PID=""

"$CLI" test-control cancel >/tmp/fzf-palette-e2e-orphaned-client-cancel-control.out
ORPHANED_CLIENT_PID_AFTER="$("$CLI" status --json)"
python3 - "$ORPHANED_CLIENT_PID_BEFORE" "$ORPHANED_CLIENT_PID_AFTER" <<'PY'
import json
import sys
before = json.loads(sys.argv[1])["app"]
after = json.loads(sys.argv[2])["app"]
if before["pid"] != after["pid"]:
    raise SystemExit(f"app restarted after writing to orphaned picker client: before={before}, after={after}")
if after["activePicker"]:
    raise SystemExit(f"orphaned-client picker stayed active after cancel: {after}")
if after.get("lastCompletionReason") != "panel_cancelled":
    raise SystemExit(f"expected panel_cancelled after orphaned-client cancel, got {after}")
PY

echo "e2e hotkey-config/settings/program-context/hotkey/key-navigation/movement-bench/alfred-context-transition/carbon-hotkey/physical-hotkey-optional/physical-ui-optional/profile-hotkeys/panel/visual-snapshot/query/native-chrome/default-opts/default-command/ctrl-t-command/built-in-profiles/profile/two-stage/case/ansi/tiebreak/tiebreak-list/tiebreak-chunk/no-sort/path-scheme/history-scheme/nth/accept/multi/multi-join/copy/paste/open/command/preview-update/preview-ansi/preview-terminal/preview-terminal-lines/preview-toggle/preview-layout/preview-scroll/result-command-cancel/source-preview-cancel/cancel/orphaned-client passed"
