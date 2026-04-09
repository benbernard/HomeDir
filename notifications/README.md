# Native Notification Apps

This directory is the source-controlled side of a manifest-driven notification
framework.

The goal is simple:

- each notification identity is a real macOS app bundle with its own icon
- all apps share the same Swift runtime
- new notification apps are defined in `manifest.json`
- `notifyctl` in `bin/ts` creates, builds, and sends notifications

## Layout

```text
notifications/
├── manifest.json          # Profile definitions
├── runtime/
│   └── NotifyAgent.swift  # Shared native runtime
└── README.md
```

Built apps are installed outside the repo in `~/Applications/NotificationApps/`.

## Profile Model

Each profile in `manifest.json` defines:

- `bundleId`: app identity used by Notification Center
- `displayName`: app name shown in Finder / app bundle
- `icon`: `.icns` path, absolute or relative to this manifest
- `permissionPrompt`: optional first-run copy shown before requesting notification permission
- `sound`: default notification sound
- `defaultAction`: what happens on notification click
- `actions`: optional notification buttons

Supported action kinds:

- `open-url`
- `run-command`
- `reschedule`

Template values use `{{name}}` syntax and are filled by `notifyctl send --data`.

On first send, each built app can guide the user through notification
permission. If notifications are denied or alerts are disabled, the runtime
offers to open macOS Notification settings for that app.

## Examples

Build all apps:

```bash
notifyctl build
```

Send a meeting notification:

```bash
notifyctl send meety \
  --title "Design Review" \
  --subtitle "2:30 PM" \
  --message "Click to join" \
  --data meet_url=gmeet://meet.google.com/kue-sdni-ymb
```

Send an informational meeting reminder with no click action:

```bash
notifyctl send meety \
  --title "Focus Block" \
  --subtitle "3:00 PM - 3:30 PM" \
  --message "Meeting starting now" \
  --no-default-action \
  --no-actions
```

Send a Claude notification with a transcript action:

```bash
notifyctl send claude \
  --title "Claude finished" \
  --message "Review the latest output" \
  --data transcript_path=/tmp/session.md
```

Send a Codex notification manually:

```bash
notifyctl send codex \
  --title "Codex finished" \
  --message "Implemented the notification adapter"
```

## Adding A New App

The fastest path is:

```bash
notifyctl new foo
```

That adds a profile scaffold pointing at `notifications/icons/foo.icns`. Put a
real `.icns` there, edit the action definitions in `manifest.json`, then run
`notifyctl build foo`.

If you want custom onboarding copy for the first permission request, set
`permissionPrompt` in the profile or pass `--permission-prompt` to
`notifyctl new`.

## Wiring Codex CLI

Codex now supports an external `notify` command in `config.toml`. The local
setup uses the `codex-notify` script from `bin/ts`, which translates Codex's
JSON payload into the native app defined in this manifest:

```toml
notify = ["codex-notify"]

[tui]
notifications = true
```

`codex-notify` expects the `codex` profile to be built already:

```bash
notifyctl build codex
```

In practice, `notifyctl send` auto-builds a stale app bundle before sending, so
most callers can just invoke `send` and let the framework refresh the native
app when the manifest, icon, or runtime changed.
