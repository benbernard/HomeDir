# Meeting Notification Operations

This is the operational guide for the MeetingBar-triggered meeting overlay and native notification path. For the full system diagram, see `docs/meeting-notification-architecture.md`; do not treat this doc as a replacement for that architecture reference.

## Runtime Path

At meeting start, the flow is:

```text
MeetingBar
  -> ~/Library/Application Scripts/leits.MeetingBar/eventStartScript.scpt
  -> ~/bin/ts/bin/meeting-notify <temp plist>
  -> ~/bin/meeting-overlay
  -> notifyctl send meety
```

Canonical tracked files:

| File | Role |
| --- | --- |
| `bin/eventStartScript.scpt` | AppleScript bridge called by MeetingBar. |
| `bin/ts/src/meeting-notify.ts` | Main orchestrator. |
| `bin/meeting-overlay.swift` | Full-screen overlay source. |
| `bin/build-meeting-overlay` | Swift overlay build script. |
| `bin/event-prompt.sh` | Backward-compatible wrapper to `meeting-notify`. |
| `notifications/manifest.json` | Defines the `meety` native notification app. |
| `notifications/runtime/NotifyAgent.swift` | Runtime that posts and dispatches notification actions. |

## Installation Checks

MeetingBar should run this AppleScript from its application scripts directory:

```text
~/Library/Application Scripts/leits.MeetingBar/eventStartScript.scpt
```

The tracked canonical source is:

```text
~/bin/eventStartScript.scpt
```

The normal setup is a symlink from the MeetingBar script path back to the tracked file.

Important: MeetingBar caches the AppleScript in its preferences. After changing `bin/eventStartScript.scpt`, quit and restart MeetingBar so it reloads the script.

Required executables:

```bash
test -x ~/bin/ts/bin/meeting-notify
test -x ~/bin/meeting-overlay
test -x ~/bin/ts/bin/notifyctl
```

Optional calendar enrichment uses:

```text
~/.config/gohan/bin/gws
```

If `gws` is missing or fails, the triggered meeting can still show; the overlay just loses the extra upcoming-meetings context.

## Rebuilds

Rebuild the overlay after editing `bin/meeting-overlay.swift`:

```bash
~/bin/build-meeting-overlay
```

Rebuild the TypeScript utilities after changing `bin/ts/src/meeting-notify.ts` or notification helpers:

```bash
cd ~/bin/ts
bun run build
```

The wrapper in `~/bin/ts/bin/meeting-notify` normally auto-rebuilds on execution when source changed, but an explicit build is cleaner when validating an operational fix.

Rebuild the native meeting notification app after changing `notifications/manifest.json`, `notifications/runtime/NotifyAgent.swift`, or the meeting icon:

```bash
notifyctl build meety
```

`notifyctl send meety` also auto-rebuilds when generated outputs are missing or stale.

## Manual Tests

Send only the native notification:

```bash
notifyctl send meety \
  --title "Test Meeting" \
  --subtitle "2:30 PM-3:00 PM" \
  --message "Meeting starting now" \
  --notification-id "meetingbar-active" \
  --data meet_url=gmeet://meet.google.com/test-room
```

Launch only the overlay:

```bash
~/bin/meeting-overlay \
  --meetings-json '[{"title":"Test Meeting","url":"https://meet.google.com/test-room","time":"Thursday, May 21, 2026 at 2:30:00 PM"}]' \
  --cal-url "https://calendar.google.com/calendar/r/day/2026/5/21"
```

Exercise `meeting-notify` without opening overlay windows:

```bash
plist=/tmp/meetingbar-event-test.plist
rm -f "$plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/libexec/PlistBuddy -c 'Add :eventId string test-event' "$plist"
/usr/libexec/PlistBuddy -c 'Add :title string Test Meeting' "$plist"
/usr/libexec/PlistBuddy -c 'Add :allday string false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :startDate string Thursday, May 21, 2026 at 2:30:00 PM' "$plist"
/usr/libexec/PlistBuddy -c 'Add :endDate string Thursday, May 21, 2026 at 3:00:00 PM' "$plist"
/usr/libexec/PlistBuddy -c 'Add :eventLocation string EMPTY' "$plist"
/usr/libexec/PlistBuddy -c 'Add :repeatingEvent string false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :attendeeCount string 2' "$plist"
/usr/libexec/PlistBuddy -c 'Add :meetingUrl string https://meet.google.com/test-room' "$plist"
/usr/libexec/PlistBuddy -c 'Add :meetingService string Google Meet' "$plist"
/usr/libexec/PlistBuddy -c 'Add :meetingNotes string EMPTY' "$plist"
~/bin/ts/bin/meeting-notify --dry-run "$plist"
```

`meeting-notify` deletes the plist after reading it, including in dry-run mode.

## Logs

Main orchestrator log:

```text
~/event-log.txt
```

Entries are JSON lines with `timestamp`, `level`, `component`, `message`, and optional `details`.

Useful components:

| Component | Meaning |
| --- | --- |
| `main` | Plist read, filtering, processing lifecycle. |
| `calendar` | `gws` fetch and parsing. |
| `overlay` | Overlay launch or missing binary. |
| `notification` | `notifyctl` send success or failure. |

Native notification runtime logs:

```text
~/Library/Logs/NotificationApps/com.benbernard.notify.meetingavocado.log
```

This is where permission, scheduling, invalid URL, and action dispatch errors from `NotifyAgent.swift` appear.

Legacy log path still present in source:

```text
~/meeting-prompt.log
```

The current `meeting-notify.ts` declares it but does not write to it. Use `~/event-log.txt` first.

## Expected Behavior

`eventStartScript.scpt` writes all 11 MeetingBar fields to a temporary plist and starts `meeting-notify` with `nohup` in the background. This avoids shell quoting problems with titles, locations, and notes.

`meeting-notify`:

- Reads the plist with `plutil -convert json`.
- Deletes the temporary plist immediately.
- Skips `"Focus Time (via Clockwise)"` and `"Lunch (via Clockwise)"`.
- Fetches calendar events starting within the next 15 minutes.
- Filters all-day events by requiring `start.dateTime`.
- Kills any existing `meeting-overlay` process before launching a new one.
- Sends notification ID `meetingbar-active`, replacing the previous active meeting alert.
- Sends no click actions when the event has no usable meeting URL.
- Converts Google Meet HTTPS URLs to `gmeet://...`.

The overlay:

- Uses a borderless, always-on-top full-screen Cocoa window.
- Shows one meeting or a multi-meeting warning list.
- Disables buttons for 1 second after show to prevent accidental clicks.
- Has Join, Snooze 2 min, Dismiss, and Open in Google Calendar controls.

The native notification:

- Uses the `meety` profile.
- Opens `meet_url` on default click or Join.
- Offers Snooze 5m through a native notification action.

## Troubleshooting

If nothing happens at meeting start:

1. Restart MeetingBar to refresh its cached AppleScript.
2. Confirm the script path under `~/Library/Application Scripts/leits.MeetingBar/`.
3. Check `~/event-log.txt` for a `Received event data` entry.
4. Run `~/bin/ts/bin/meeting-notify --dry-run <plist>` with a test plist.

If the overlay does not show:

1. Run `~/bin/build-meeting-overlay`.
2. Test `~/bin/meeting-overlay` manually.
3. Check `~/event-log.txt` for `overlay` warnings or errors.
4. Check whether another `meeting-overlay` process is being killed and relaunched.

If the native notification does not show:

1. Run `notifyctl list`.
2. Run `notifyctl build meety`.
3. Send the manual `notifyctl send meety` test above.
4. Check System Settings > Notifications for `Meeting Notification`.
5. Check `~/Library/Logs/NotificationApps/com.benbernard.notify.meetingavocado.log`.

If Join opens the wrong app:

1. Check the URL in `~/event-log.txt` under the `notification` and `main` entries.
2. Google Meet HTTPS links should become `gmeet://meet.google.com/...`.
3. Non-Google links are passed through unchanged.

If duplicate or stale notifications appear:

1. Confirm `meeting-notify` sends `--notification-id meetingbar-active`.
2. Rebuild `meety` so the latest runtime is used.
3. Check whether the `meety` bundle ID changed; a new bundle ID creates a separate Notification Center identity.

If the notification has no buttons:

This is expected when MeetingBar provides `EMPTY` or no meeting URL. In that case `meeting-notify` sends `--no-default-action --no-actions` so the alert is informational only.
