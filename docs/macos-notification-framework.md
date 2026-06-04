# macOS Notification Framework

This repo has a manifest-driven framework for sending native macOS notifications through real app bundles. Each notification identity is its own `.app`, with its own bundle ID, icon, Notification Center permission, and click actions. The apps all share one Swift runtime.

## Source Files

| File | Role |
| --- | --- |
| `notifications/manifest.json` | Profiles for every notification app identity. |
| `notifications/runtime/NotifyAgent.swift` | Shared Swift runtime embedded in each app bundle. |
| `bin/ts/src/notifyctl.ts` | CLI for listing, creating, building, and sending through profiles. |
| `notifications/README.md` | Short framework overview and examples. |

Built app bundles are installed outside the repo at:

```text
~/Applications/NotificationApps/
```

Do not commit built bundles. The source of truth is the manifest, icons, runtime, and TypeScript helper code.

## Profiles

Profiles live under `profiles` in `notifications/manifest.json`.

Required fields:

| Field | Meaning |
| --- | --- |
| `bundleId` | Notification Center identity. Changing it creates a new macOS notification permission entry. |
| `displayName` | App bundle name and user-visible notification app name. |
| `icon` | `.icns` path, absolute or relative to `notifications/manifest.json`. |

Optional fields:

| Field | Meaning |
| --- | --- |
| `permissionPrompt` | Primer text shown before the first macOS notification permission prompt. |
| `sound` | `default` or a named notification sound. |
| `defaultAction` | Action used when the notification body itself is clicked. |
| `actions` | Up to 4 visible notification buttons. |

Supported action kinds:

| Kind | Required data | Behavior |
| --- | --- | --- |
| `open-url` | `target` | Opens the URL through `NSWorkspace`. |
| `run-command` | `argv` | Launches the executable at `argv[0]` with remaining args. |
| `reschedule` | `minutes` | Posts a copy of the notification after that delay. |

Action values can use `{{name}}` templates. Provide values with repeated `--data key=value` flags when sending.

## Current Profiles

| Profile | Bundle ID | Purpose |
| --- | --- | --- |
| `claude` | `com.benbernard.notify.claudecode` | Claude completion notifications, with Ghostty/transcript actions. |
| `codex` | `com.benbernard.notify.codexassistant` | Codex completion notifications, with Ghostty/ChatGPT actions. |
| `meety` | `com.benbernard.notify.meetingavocado` | Meeting reminders with Join and Snooze actions. |

The `meety` default action and Join button expect `meet_url`. `meeting-notify` converts Google Meet HTTPS URLs to `gmeet://...` before sending so Google Meet links open in the native handler.

## Commands

List profiles and validation status:

```bash
notifyctl list
```

Build all notification apps:

```bash
notifyctl build
```

Build one profile:

```bash
notifyctl build meety
```

Send a meeting notification:

```bash
notifyctl send meety \
  --title "Design Review" \
  --subtitle "2:30 PM-3:00 PM" \
  --message "Meeting starting now" \
  --notification-id "meetingbar-active" \
  --data meet_url=gmeet://meet.google.com/abc-defg-hij
```

Send an informational notification with no click actions:

```bash
notifyctl send meety \
  --title "Focus Block" \
  --subtitle "3:00 PM-3:30 PM" \
  --message "Meeting starting now" \
  --no-default-action \
  --no-actions
```

Create a new profile scaffold:

```bash
notifyctl new foo
```

Then add a real `.icns` file at the printed path, edit `notifications/manifest.json`, and run `notifyctl build foo`.

## Build Behavior

`notifyctl build` creates this bundle layout:

```text
~/Applications/NotificationApps/<Display Name>.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── notify-agent
    └── Resources/
        ├── AppIcon.icns
        └── profile.json
```

Build details:

- `Info.plist` includes the profile display name, bundle ID, icon name, `LSUIElement`, and a bundle version derived from source mtimes.
- `profile.json` stores profile metadata used by the runtime for prompts and logs.
- `NotifyAgent.swift` is compiled with `swiftc` and linked against `AppKit` and `UserNotifications`.
- The bundle is ad-hoc signed with `codesign --sign -` when possible. Signing failure is tolerated for local development.

`notifyctl send` rebuilds a profile automatically when any required output is missing or when the manifest, runtime source, or icon is newer than its generated output.

## Runtime Behavior

`notifyctl send` renders the request, base64-encodes the JSON payload, and launches the app with:

```bash
/usr/bin/open -n "<bundle>.app" --args --send-base64 "<payload>"
```

The Swift runtime then:

1. Reads the base64 payload.
2. Checks Notification Center authorization.
3. Shows the profile primer before the first permission request.
4. Registers any visible button actions.
5. Removes pending and delivered notifications with the same `notificationId`.
6. Schedules a native time-sensitive notification.
7. Dispatches default clicks and button clicks to `open-url`, `run-command`, or `reschedule`.

If permission is denied, the runtime prompts to open System Settings > Notifications. Runtime logs go to:

```text
~/Library/Logs/NotificationApps/<bundle-id>.log
```

## Troubleshooting

Run `notifyctl list` first. It catches common manifest problems: invalid profile names, missing display names, non-`.icns` icons, duplicate action IDs, missing action titles, invalid bundle IDs, and invalid reschedule minutes.

If a notification does not appear:

1. Rebuild the profile with `notifyctl build <profile>`.
2. Send a minimal test notification.
3. Check System Settings > Notifications for the profile display name.
4. Check the runtime log under `~/Library/Logs/NotificationApps/`.

If a click action fails, verify the rendered templates. A missing `--data` key fails before the app is launched; an invalid URL or command is logged by `NotifyAgent.swift`.

If Notification Center shows duplicate app entries, check whether the profile `bundleId` changed. macOS treats each bundle ID as a separate notification identity.
