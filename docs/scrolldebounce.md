# scrolldebounce

Filters fabricated direction reversals out of mouse-wheel scrolling.

## The problem

A failing scroll-wheel encoder intermittently emits a step in the *opposite*
direction during a single-direction scroll. macOS scroll acceleration then
amplifies that one step into a large visible jump (a ±1 wheel step arrives at an
app as a ±4 to ±70 point scroll), so a barely-there hardware glitch becomes a
page that lurches backwards.

Measured on a Razer Naga X: **59 glitches in 617 notches (~9.6%)**, mostly during
fast scrolling.

## Why this is the mouse and not macOS

`bin/scrolltrace` captures both layers at once:

- `RAW` — `IOHIDDevice` input values, i.e. the report bytes off the USB pipe,
  before macOS acceleration, before any event tap.
- `CG` — the scroll events actually delivered to applications.

On an affected mouse the wrong-direction step is already present in `RAW`, so
the OS is faithfully forwarding what the hardware reported. The wheel is an
8-bit signed delta (−127..127), so a reversal means `0xFF` → `0x01`: all eight
bits change. USB HID reports are CRC-protected and retried, so a transport error
cannot produce that — the device really did report "up".

Rule out software first: check that no scroll-modifying tool has rules for the
device (`mouse_key` in `~/.config/karabiner/karabiner.json`, scroll triggers in
BetterTouchTool).

## Installation

```bash
bin/scrollfix-build                  # or: CODESIGN_ID="…" bin/scrollfix-build
cp bin/scrolldebounce.plist ~/Library/LaunchAgents/dev.benbernard.scrolldebounce.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.benbernard.scrolldebounce.plist
```

The first launch needs a manual **Accessibility** grant. The daemon requests it
and then retries every 3s, so no restart is needed after granting.

Signing identity matters: TCC pins ad-hoc binaries to their cdhash, so an ad-hoc
build needs re-approving after every rebuild. `CODESIGN_ID` signs with a stable
identity instead, and the grant survives rebuilds. If a stale entry exists for
this binary, remove it in System Settings and re-add; the checkbox can look
enabled while the stored requirement no longer matches.

## How it decides

State machine over discrete wheel events (`isContinuous == 0`); trackpad,
momentum and horizontal scrolling are never touched.

- First event, or after a ≥`--gap` pause → `FRESH`, believed immediately.
- Same direction as the current burst → `PASS`.
- Opposing direction → withheld (`DROP`) until `--confirm` of them arrive.
- Confirmed → real reversal; the withheld notches are **discarded**.
- Original direction resumes → withheld notches were a glitch; discarded.

Cost: a genuine *fast* reversal loses `--confirm - 1` notches (~40ms). A
deliberate reversal after a pause costs nothing.

There is a `--replay` flag that re-posts withheld notches on a confirmed
reversal. It is off by default and should stay off: posting at `cghidEventTap`
from inside a session-height tap was observed to silently stop *other* taps on
the system from delivering events, which would disturb anything else using
event taps.

## Rolling log

The daemon keeps the last `--log-window` seconds (default 600) in memory and
rewrites the snapshot file atomically every 10s, so there is always a valid
capture without having started one in advance.

```bash
kill -USR1 $(pgrep -x scrolldebounce)   # force a snapshot now
cp ~/Library/Logs/scrolldebounce-events.log ~/Desktop/scroll-$(date +%H%M).log
```

```
ts  decision  d1  d2  continuous  committed  opposites  held  discarded
```

`d1` is the line delta as seen, `held` the currently withheld amount, and
`discarded` the withheld notches thrown away on this event.

## Measuring

```bash
bin/scrollfix-selftest      # scroll normally for ~60s when prompted
```

Reports notches from hardware, notches delivered, and how many hardware
reversals still reached applications.

## Limitation

This hides a degrading encoder. It does not fix it. If glitches start arriving
as three or more consecutive steps they will get through, and the real fix is
replacing the mouse or the encoder.
