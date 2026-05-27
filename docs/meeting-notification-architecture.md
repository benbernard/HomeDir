# Meeting Notification System Architecture

## Overview

This document describes the full architecture of the meeting notification and overlay system. The system triggers when a calendar event is about to start, then launches both a **full-screen overlay** and a **native macOS notification** in parallel.

There are three main layers: the **trigger**, the **orchestrator**, and the two parallel **presentation paths** (overlay + native notifications).

---

## 1. Trigger Layer: MeetingBar

**Location:** `repos/MeetingBar/`

MeetingBar is a modified open-source macOS menu bar calendar app. The relevant logic is in `Core/Managers/ActionsOnEventStart.swift`.

### How it works

- **Timer:** It runs a check every **10 seconds** looking for the next upcoming meeting.
- **Trigger window:** For the script hook, it fires when the meeting is within `0 < timeInterval < actionTime` (default is at the meeting start time, but configurable in MeetingBar preferences under **Advanced → "Run script on event start"**).
- **Deduplication:** It tracks processed events in `Defaults[.processedEventsForRunScriptOnEventStart]` so it doesn't fire twice for the same meeting (unless the meeting is edited/rescheduled).
- **Execution:** When it decides to fire, it calls `runMeetingStartsScript(event:type:)` which loads and executes an AppleScript from:
  ```
  ~/Library/Application Scripts/leits.MeetingBar/eventStartScript.scpt
  ```
  **Important:** MeetingBar **caches the entire AppleScript** in its `~/Library/Preferences/leits.MeetingBar.plist`. Editing the `.scpt` file on disk alone does nothing. You must either:
  1. Quit and restart MeetingBar (it re-reads the file on launch), or
  2. Manually update the plist via `defaults import leits.MeetingBar <plist-file>`.

### Parameters passed to the script

MeetingBar passes **11 parameters** to the AppleScript:

| # | Parameter | Example |
|---|-----------|---------|
| 1 | `eventId` | `ABC123` |
| 2 | `title` | `Team Standup` |
| 3 | `allDay` | `false` |
| 4 | `startDate` | `Thursday, May 21, 2026 at 11:00:00 AM` |
| 5 | `endDate` | `Thursday, May 21, 2026 at 11:30:00 AM` |
| 6 | `eventLocation` | `Conference Room A` or `EMPTY` |
| 7 | `repeatingEvent` | `false` |
| 8 | `attendeeCount` | `5` |
| 9 | `meetingUrl` | `https://meet.google.com/abc-defg-hij` |
| 10 | `meetingService` | `Google Meet` or `EMPTY` |
| 11 | `meetingNotes` | `<p>Agenda: ...</p>` or `EMPTY` |

---

## 2. Bridge Layer: `eventStartScript.scpt`

**Location:** `~/bin/eventStartScript.scpt` (canonical source)  
**Symlink:** `~/Library/Application Scripts/leits.MeetingBar/eventStartScript.scpt`

This is the AppleScript sitting in MeetingBar's sandboxed scripts directory. It is configured through MeetingBar's **Advanced preferences**.

### Why plist instead of positional arguments?

Previously, this script passed 11 shell arguments directly:

```applescript
nohup ~/bin/event-prompt.sh "arg1" "arg2" ... &
```

This broke whenever event titles, locations, or notes contained quotes, newlines, or special characters. The current approach eliminates all shell escaping by using structured data:

1. **AppleScript** creates a temporary `.plist` file via System Events
2. **TypeScript binary** reads it via `plutil -convert json`
3. The temp file is **deleted immediately** after reading

### What it does

```applescript
-- Creates a temp plist with all 11 fields as key-value pairs
set plistPath to "/tmp/meetingbar-event-" & (do shell script "date +%s%N") & ".plist"

addField(thePlist, "eventId", eventId as text)
addField(thePlist, "title", title as text)
-- ... etc

-- Passes just the plist path to the binary
nohup ~/bin/ts/bin/meeting-notify "<plist-path>" > /dev/null 2>&1 &
```

This detaches execution from MeetingBar so the app doesn't hang while the downstream scripts run.

---

## 3. Orchestrator: `~/bin/ts/bin/meeting-notify`

**Source:** `~/bin/ts/src/meeting-notify.ts`  
**Compiled:** `~/bin/ts/dist/meeting-notify` (58MB standalone executable)  
**Entry in manifest:** `~/bin/ts/src/manifest.ts`

This is a compiled TypeScript binary that replaces the old `~/bin/event-prompt.sh` and `~/site/meeting-prompt.sh` shell scripts. It receives a plist path, reads the event data, and branches into parallel work.

### Step-by-step flow

1. **Reads the plist** via `plutil -convert json -o - "<path>"` — structured, no escaping
2. **Deletes the temp plist** immediately after reading
3. **Logs everything** to `~/event-log.txt` (JSON structured logs)
4. **Filters silent events** — hardcoded skip for `"Focus Time (via Clockwise)"` and `"Lunch (via Clockwise)"`
5. **Fetches other upcoming meetings** from Google Calendar (via `gws` CLI) for the next 15 minutes
6. **Filters all-day events** — events with only `start.date` (no `start.dateTime`) are excluded. This prevents non-actionable events like "Home" or "Out of office" from appearing in the overlay
7. **Builds meetings JSON** — triggered event + any other timed events starting soon
8. **Launches the overlay** (if not `--dry-run`):
   ```bash
   ~/bin/meeting-overlay \
     --meetings-json '[{"title":"...","url":"...","time":"..."}]' \
     --cal-url "https://calendar.google.com/calendar/r/day/YYYY/M/D"
   ```
   This is **backgrounded** via `spawn()` with `detached: true`.
9. **Generates a smart notification message** from meeting notes:
   - Filters out join-instructions boilerplate ("Meeting ID", "Passcode", "Dial by", "Google Meet", etc.)
   - Truncates to 160 characters
   - Falls back to "Meeting starting now" if notes are empty or boilerplate-only
10. **Sends a native macOS notification** via `notifyctl`:
    ```bash
    notifyctl send meety \
      --title "$title" \
      --subtitle "$startTime-$endTime" \
      --message "$summary" \
      --data "meet_url=$normalizedURL"
    ```

---

## 4. Path A: The Full-Screen Overlay

### Files

| File | Purpose |
|------|---------|
| `~/bin/meeting-overlay.swift` | Swift source code |
| `~/bin/meeting-overlay` | Compiled binary |
| `~/bin/build-meeting-overlay` | Compile script (`swiftc -O`) |

### How it works

`meeting-notify` spawns `~/bin/meeting-overlay` with:

1. **A JSON array** of all meetings starting soon (triggered one + any others from calendar fetch)
2. **A calendar day URL** for the "Open in Google Calendar" button

### What the overlay does

- **Borderless, full-screen, always-on-top** Cocoa window (screen-saver window level)
- **Single meeting mode:** Big 📅 icon, title, time, large green "Join" button
- **Multi-meeting mode:** Warning banner "⚠️ N MEETINGS STARTING NOW", plus rows for each meeting with individual join buttons
- **Bottom controls:**
  - **"Snooze 2 min"** — hides overlay, re-shows in 2 minutes
  - **"Dismiss"** — quits the app
  - **"Open in Google Calendar"** — opens the day's calendar view
- **Join behavior:** Clicking a Join button opens the meeting URL via `NSWorkspace.shared.open()` and immediately terminates the overlay app
- **Safety delay:** Buttons are visually disabled for 1 second on show to prevent accidental clicks

---

## 5. Path B: Native macOS Notifications (`notifyctl`)

### Files

| File | Purpose |
|------|---------|
| `~/bin/ts/src/notifyctl.ts` | CLI tool |
| `~/notifications/manifest.json` | Profile definitions |
| `~/notifications/runtime/NotifyAgent.swift` | Runtime compiled into each notification app |
| `~/Applications/NotificationApps/Meeting Notification.app` | Built app for the `meety` profile |

### How it works

`notifyctl` is a custom TypeScript utility that manages **tiny custom macOS notification apps**.

#### Profile: `meety`

Defined in `~/notifications/manifest.json`:

- **Bundle ID:** `com.benbernard.notify.meetingavocado`
- **Icon:** `icons/meeting-notification.icns`
- **Default action:** `open-url` with target `{{meet_url}}`
- **Actions:**
  - **"Join"** — opens the meeting URL
  - **"Snooze 5m"** — reschedules the notification for 5 minutes later

#### Build flow

On first `send` (or when manifest/runtime changes), `notifyctl`:
1. Compiles `NotifyAgent.swift` into a `.app` bundle using `swiftc`
2. Copies the icon
3. Generates an `Info.plist`
4. Ad-hoc signs the bundle

#### Send flow

1. `notifyctl` launches the built app with a **base64-encoded JSON payload**
2. The app uses the `UserNotifications` framework to post a real native macOS banner/alert
3. Clicking the notification or action buttons dispatches back through the agent to open URLs or run commands

#### URL normalization

`meeting-notify` converts `https://meet.google.com/...` links to `gmeet://...` so they open in the Meety/Google Meet app instead of the browser.

---

## 6. Backward Compatibility

### `~/bin/event-prompt.sh`

This is a thin wrapper that forwards all arguments to `~/bin/ts/bin/meeting-notify`. It exists for any manual scripts or old workflows that still call `event-prompt.sh` directly.

```bash
#!/bin/zsh
exec ~/bin/ts/bin/meeting-notify "$@"
```

---

## 7. Supporting Scripts & Debug Tools

| File | Purpose |
|------|---------|
| `~/bin/test-meeting-trigger.sh` | Simulates the full MeetingBar trigger chain for testing |
| `~/bin/debug-meetingbar-timing.sh` | Analyzes whether a meeting at a specific time would trigger given MeetingBar's 10s timer granularity |
| `~/bin/raiseMeeting.scpt` | Old AppleScript to raise Zoom/Google Meet windows |
| `~/bin/event-prompt.applescript` | Fallback dialog box if `notifyctl` fails (legacy) |

---

## Data Flow Diagram

```
┌─────────────────┐
│   MeetingBar    │  (checks every 10s for upcoming meetings)
│   (macOS app)   │
└────────┬────────┘
         │ runs AppleScript hook
         ▼
┌───────────────────────────────────┐
│ eventStartScript.scpt             │  (in ~/Library/Application Scripts/leits.MeetingBar/)
│ 1. Creates temp plist with all    │
│    11 event fields                │
│ 2. Calls ~/bin/ts/bin/meeting-notify <plist>
└────────┬──────────────────────────┘
         │
         ▼
┌───────────────────────────────────┐
│ ~/bin/ts/bin/meeting-notify       │  (compiled TypeScript binary)
│  ├─ Reads plist via plutil        │
│  ├─ Logs to ~/event-log.txt       │
│  ├─ Fetches other meetings via gws│
│  ├─ Filters all-day events        │
│  ├─ Spawns overlay (BACKGROUND) ──┼──► Overlay Path
│  └─ Calls notifyctl send meety ───┼──► Native Notification Path
└───────────────────────────────────┘
```

### Overlay Path

```
meeting-notify
    │
    ▼
~/bin/meeting-overlay --meetings-json [...] --cal-url [...]
    │
    ▼
Full-screen Cocoa overlay window
```

### Native Notification Path

```
meeting-notify
    │
    ▼
notifyctl send meety --title ... --subtitle ... --message ... --data meet_url=...
    │
    ├─ (re)builds Meeting Notification.app if needed
    ├─ launches agent with base64 payload
    │
    ▼
Native UNNotification banner/alert
    │
    ▼
User clicks "Join" → opens gmeet:// or zoom URL
```

---

## Configuration & Maintenance

### Updating the AppleScript

1. Edit `~/bin/eventStartScript.scpt`
2. Export MeetingBar's plist: `defaults export leits.MeetingBar /tmp/mb.plist`
3. Update the `eventStartScript` key in the plist with the new file content
4. Import back: `defaults import leits.MeetingBar /tmp/mb.plist`
5. Quit and restart MeetingBar

### Rebuilding the TypeScript binary

```bash
cd ~/bin/ts
rm -f dist/meeting-notify
bun build --compile --target=bun-darwin-arm64 src/meeting-notify.ts --outfile dist/meeting-notify
```

The wrapper script at `~/bin/ts/bin/meeting-notify` auto-rebuilds on next run if the source is newer than the binary.

### Rebuilding the overlay

```bash
~/bin/build-meeting-overlay
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Plist over positional args** | Eliminates shell escaping issues with quotes, newlines, and special characters in event titles/notes |
| **Compiled TypeScript binary** | Replaces fragile shell scripts; `set -e`, `date` parsing, and `async` edge cases were causing silent failures |
| **Sync calendar fetch** | `execSync` for `gws` avoids Bun background process termination issues |
| **Filter all-day events** | Events like "Home" or "Out of office" have no actionable start time and clutter the overlay |
| **No internal forking** | AppleScript's `nohup ... &` already backgrounds the binary; forking inside the binary broke in compiled Bun executables |
| **JSON structured logging** | `~/event-log.txt` contains machine-parseable logs with timestamps, components, and metadata |

---

## Troubleshooting

### "The overlay doesn't appear"

1. Check `~/event-log.txt` for errors
2. Verify `~/bin/meeting-overlay` exists
3. Try `--dry-run` to test without launching the overlay: `~/bin/ts/bin/meeting-notify --dry-run /tmp/test.plist`

### "MeetingBar is using the old script"

MeetingBar caches the script. You must quit and restart it, or manually update its plist (see Configuration above).

### "All-day events like 'Home' appear in the overlay"

The binary filters these out. If they still appear, the binary may not have been rebuilt since the filter was added. Run the rebuild command above.
