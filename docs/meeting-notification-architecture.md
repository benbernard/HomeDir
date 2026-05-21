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

### Parameters passed to the script

MeetingBar passes **13 parameters** to the AppleScript:

| # | Parameter | Example |
|---|-----------|---------|
| 1 | `eventId` | `ABC123` |
| 2 | `title` | `Team Standup` |
| 3 | `allDay` | `false` |
| 4 | `startDate` | `Thursday, May 21, 2026 at 11:00:00 AM` |
| 5 | `endDate` | `Thursday, May 21, 2026 at 11:30:00 AM` |
| 6 | `location` | `Conference Room A` or `EMPTY` |
| 7 | `recurrent` | `false` |
| 8 | `attendeeCount` | `5` |
| 9 | `meetingURL` | `https://meet.google.com/abc-defg-hij` |
| 10 | `meetingService` | `Google Meet` or `EMPTY` |
| 11 | `notes` | `<p>Agenda: ...</p>` or `EMPTY` |
| 12 | `calendarName` | `Work` |
| 13 | `calendarSource` | `Gmail` |
| 14 | `attendees` | `Alice <alice@example.com>, Bob <bob@example.com>` |

---

## 2. Bridge Layer: `eventStartScript.scpt`

**Location:** `~/Library/Application Scripts/leits.MeetingBar/eventStartScript.scpt`

This is the AppleScript sitting in MeetingBar's sandboxed scripts directory. It is configured through MeetingBar's **Advanced preferences**.

### What it does

It simply calls the main shell script in the background:

```applescript
nohup ~/bin/event-prompt.sh "<arg1>" "<arg2>" ... &
```

This detaches execution from MeetingBar so the app doesn't hang while the downstream scripts run.

---

## 3. Orchestrator: `~/bin/event-prompt.sh`

**Location:** `~/bin/event-prompt.sh`

This is the main entry point. It receives all meeting parameters, sanitizes them, logs them, and then branches into parallel work.

### Step-by-step flow

1. **Sanitizes input** — strips HTML from notes, cleans up strings, normalizes text.
2. **Logs everything** to `~/event-log.txt`.
3. **Calls the overlay script** (if it exists):
   ```bash
   ~/site/meeting-prompt.sh --verbose &
   ```
   It pipes the full event data via stdin. This is **backgrounded**, so execution continues immediately.
4. **Filters silent events** — hardcoded skip for `"Focus Time (via Clockwise)"` and `"Lunch (via Clockwise)"`.
5. **Generates a notification subtitle** — formats start/end times (e.g. `11:00 AM-11:30 AM`).
6. **Generates a smart notification message** from meeting notes using an LLM:
   - Tries to call `~/bin/ai` (local AI CLI, model `claude-haiku-4-5`)
   - Prompts it to write one short sentence (6–18 words) for the notification body
   - Aggressive fallback and opt-out detection: if the LLM returns boilerplate like "not enough detail", it falls back to using a cleaned snippet of the notes directly
   - Also filters out join-instructions boilerplate ("Meeting ID", "Passcode", "Dial by", etc.)
7. **Sends a native macOS notification** via `notifyctl`:
   ```bash
   notifyctl send meety \
     --title "$title" \
     --subtitle "$startTime-$endTime" \
     --message "$summary" \
     --data "meet_url=$normalizedURL"
   ```
8. **Fallback** — if `notifyctl` fails or is missing, it falls back to `~/bin/event-prompt.applescript` (an old dialog box).

---

## 4. Path A: The Full-Screen Overlay

### Files

| File | Purpose |
|------|---------|
| `~/site/meeting-prompt.sh` | Fetches context and launches the overlay |
| `~/bin/meeting-overlay.swift` | Swift source code |
| `~/bin/meeting-overlay` | Compiled binary |
| `~/bin/build-meeting-overlay` | Compile script (`swiftc -O`) |

### How it works

`event-prompt.sh` background-calls `~/site/meeting-prompt.sh`, which:

1. **Parses the triggered meeting** from stdin.
2. **Fetches OTHER upcoming meetings** from Google Calendar (via the `gws` CLI tool) for the next 15 minutes.
3. **Builds a JSON array** of all meetings starting soon (triggered one + any others).
4. **Launches the Swift overlay binary:**
   ```bash
   ~/bin/meeting-overlay \
     --meetings-json '[{"title":"...","url":"...","time":"..."}]' \
     --cal-url "https://calendar.google.com/calendar/r/day/YYYY/M/D"
   ```

### What the overlay does

- **Borderless, full-screen, always-on-top** Cocoa window (screen-saver window level).
- **Single meeting mode:** Big 📅 icon, title, time, large green "Join" button.
- **Multi-meeting mode:** Warning banner "⚠️ N MEETINGS STARTING NOW", plus rows for each meeting with individual join buttons.
- **Bottom controls:**
  - **"Snooze 2 min"** — hides overlay, re-shows in 2 minutes
  - **"Dismiss"** — quits the app
  - **"Open in Google Calendar"** — opens the day's calendar view
- **Join behavior:** Clicking a Join button opens the meeting URL via `NSWorkspace.shared.open()` and immediately terminates the overlay app.
- **Safety delay:** Buttons are visually disabled for 1 second on show to prevent accidental clicks.

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

`event-prompt.sh` converts `https://meet.google.com/...` links to `gmeet://...` so they open in the Meety/Google Meet app instead of the browser.

---

## 6. Supporting Scripts & Debug Tools

| File | Purpose |
|------|---------|
| `~/bin/test-meeting-trigger.sh` | Simulates the full MeetingBar trigger chain for testing |
| `~/bin/debug-meetingbar-timing.sh` | Analyzes whether a meeting at a specific time would trigger given MeetingBar's 10s timer granularity |
| `~/bin/raiseMeeting.scpt` | Old AppleScript to raise Zoom/Google Meet windows |
| `~/bin/event-prompt.applescript` | Fallback dialog box if `notifyctl` fails |

---

## Data Flow Diagram

```
┌─────────────────┐
│   MeetingBar    │  (checks every 10s for upcoming meetings)
│   (macOS app)   │
└────────┬────────┘
         │ runs AppleScript hook
         ▼
┌─────────────────────────────┐
│ eventStartScript.scpt       │  (in ~/Library/Application Scripts/leits.MeetingBar/)
│ Calls ~/bin/event-prompt.sh │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   ~/bin/event-prompt.sh     │  (main orchestrator)
│  ├─ Logs to ~/event-log.txt │
│  ├─ Pipes data to           │
│  │   ~/site/meeting-prompt.sh (BACKGROUND) ──► Overlay Path
│  ├─ Generates LLM summary     │
│  └─ Calls notifyctl send meety ──────────────► Native Notification Path
└─────────────────────────────┘
```

### Overlay Path

```
event-prompt.sh
    │
    ▼
~/site/meeting-prompt.sh
    │
    ├─ fetches other meetings from GCal via `gws`
    ├─ builds JSON array
    │
    ▼
~/bin/meeting-overlay --meetings-json [...] --cal-url [...]
    │
    ▼
Full-screen Cocoa overlay window
```

### Native Notification Path

```
event-prompt.sh
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

## History: The "New Stuff"

The overlay is the newest piece. Before it, the system only had:

1. The old AppleScript dialog fallback (`event-prompt.applescript`)
2. The native `notifyctl` notifications

### What was added

| Component | File | Purpose |
|-----------|------|---------|
| Overlay app | `~/bin/meeting-overlay.swift` | From-scratch Cocoa overlay |
| Overlay launcher | `~/site/meeting-prompt.sh` | Bridges trigger to overlay, enriches with other upcoming meetings |
| Compile helper | `~/bin/build-meeting-overlay` | `swiftc -O` wrapper |

### Behavior today

The overlay and the native notification now fire **in parallel** when a meeting starts:

- The **overlay** grabs fullscreen attention with a dark modal UI
- The **native notification** gives you a persistent, actionable banner in Notification Center (with Join and Snooze actions)
