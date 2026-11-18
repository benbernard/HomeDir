# scrolldebounce

Filters fabricated direction reversals out of mouse-wheel scrolling.

## The problem

A failing scroll-wheel encoder intermittently emits a step in the *opposite*
direction during a single-direction scroll. macOS scroll acceleration then
amplifies that one step into a large visible jump (a ±1 wheel step arrives at an
app as a ±4 to ±70 point scroll), so a barely-there hardware glitch becomes a
page that lurches backwards.

Measured on a Razer Naga X: **59 glitches in 617 notches (~9.6%)**, mostly during
fast scrolling. It has got worse since — glitch notches as a share of wheel notches by
capture: 1.8% (11-03 14:05), 6.3% (11-03 14:29), 11.5% (11-04 10:38, with four
gesture-start spikes in ten minutes where there had been none the day before). That
trend is the encoder dying, not the filter improving.

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
build needs re-approving after every rebuild — and until someone clicks Allow the
filter is silently dead. `scrollfix-build` therefore signs with a stable identity
when it can find one: `$CODESIGN_ID`, else the first name in
`~/.local/scrollfix-signing-identity` (untracked), else the machine's only local
codesigning identity. Ad-hoc is a last resort and the build says so. The grant then
survives rebuilds because the requirement names the certificate, not the cdhash.
If a stale entry exists for this binary, remove it in System Settings and re-add;
the checkbox can look enabled while the stored requirement no longer matches.

## Turning it off for a healthy mouse

The filter is for a failing encoder. After replacing the mouse, stop the agent
and keep it from launching at the next login. This leaves the binary and plist
installed and does not change mouse-button mappings.

```bash
service="gui/$(id -u)/dev.benbernard.scrolldebounce"
launchctl disable "$service"
launchctl bootout "$service"  # only needed if the agent is loaded
```

To use the installed filter again, run `launchctl enable "$service"` in the
same shell and repeat the `launchctl bootstrap` command under Installation.

## How it decides

State machine over discrete wheel events (`isContinuous == 0`); trackpad,
momentum and horizontal scrolling are never touched.

- First event, or after a ≥`--gap` pause → `FRESH`, held for `--lead` (nothing known yet).
- Same direction as the current burst → `PASS`.
- Opposing direction → withheld (`DROP`) until `--confirm` of them arrive.
- Confirmed → the withheld notches are **discarded** and the confirming notch is held
  (`PROVISIONAL`) for `--probation` (default 50ms).
- Original direction resumes → withheld notches were a glitch; discarded (`REVOKED`).

`--confirm` is not enough on its own. Once the encoder starts emitting three
consecutive wrong-direction steps, a burst satisfies `--confirm` and looks exactly
like a deliberate reversal from inside the tap — three notches, same direction, a few
milliseconds apart. Measured: on 2026-11-04 three such bursts in eight minutes each
flipped the committed direction, delivered a backwards jolt and discarded the real
travel; each burst `[4, 4, 7]` or its mirror `[-4, -4, -7]`, and the original direction
came back within ~20ms every time.

What separates the two is the follow-up, not the burst. So a confirmed reversal is
still not believed:

- Wheel continues the new direction → `KEPT`; the held notch's delta is folded into the
  next event and the reversal stands.
- Old direction returns → `REVOKED`; the whole burst is discarded and the committed
  direction is restored, so the jolt never reaches an application.
- Nothing follows within `--probation` → `CONFIRMED`; the held event is re-posted
  unchanged, so a deliberate single-notch reversal still arrives, about 50ms late.

That raises the effective confirmation length to `--confirm + 1` without making genuine
reversals pay a second notch of latency: when the wheel keeps going, the fold delivers
the travel at the next notch rather than waiting out the window.

The first notch of a gesture is not trusted at all, because the glitch most often lands
right after a pause, where there is no committed direction to compare against. The first
notch is withheld for `--lead` (default 50ms), whatever its size:

- Wheel continues the same way → `FOLD`; the held notch's delta is folded into the
  next event so no travel is lost.
- Next event is opposite → it goes through the ordinary withhold path (`DROP`) against
  the held direction; the held notch stays pending and the release timer is re-armed.
  Size is not evidence: after a 04-11 encoder degradation the wrong-direction spike is
  routinely the *largest* event in the neighbourhood (a `+8` spike after a `-1` first
  notch), because macOS acceleration amplifies a step that arrives after a pause. The
  older "opposite and larger means the held notch was the glitch" rule therefore flipped
  the committed direction onto the spike and then withheld the real scroll for `--confirm`
  notches — measured at 4 events in 10 minutes, 3 of 3 verifiable ones wrong. If
  `--confirm` opposite notches then arrive, the held notch was the spike: it is discarded
  and the withheld travel rides along with the still-provisional confirming event, so
  `KEPT` delivers it and `REVOKED` discards it with the rest of the burst.
- Nothing follows → `RELEASE`; the event is re-posted unchanged at
  `cgSessionEventTap` from the run loop, so a deliberate single notch still arrives,
  about 50ms late.

50ms because in a measured capture 92% of follow-up events arrived within 50ms and
that window caught every boundary glitch; the remaining 9% of gestures were lone
notches and took the release path.

Cost: a genuine *fast* reversal loses `--confirm - 1` notches (~40ms), and its first
delivered notch arrives one notch later than before the probation step existed. Every
gesture's first notch is delivered at the next notch or 50ms later, whichever comes
first. A deliberate reversal after a pause costs nothing.

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

Decisions: `FRESH`, `PASS`, `DROP`, `REVERSAL`, `REPLAY`, `HOLDLEAD`, `FOLD`,
`RELEASE`, `PROVISIONAL`, `KEPT`, `REVOKED`, `CONFIRMED`. A `REVOKED`
line is a glitch burst that reached `--confirm` and was caught anyway; a `REVERSAL`
line means something got through the filter.

`d1` is the line delta as seen, `held` the currently withheld amount, and
`discarded` the withheld notches thrown away on this event.

## Measuring

```bash
bin/scrollfix-selftest      # scroll normally for ~60s when prompted
```

Reports notches from hardware, notches delivered, and how many hardware
reversals still reached applications.

## Limitation

This hides a degrading encoder. It does not fix it. `--confirm` plus probation covers
bursts up to four consecutive wrong-direction steps; a five-step burst still gets
through, because once the new direction is sustained past the probation it is
indistinguishable from a deliberate reversal. Watch the `REVOKED` count versus the
`REVERSAL` count — when revocations start arriving back to back, the encoder is
degrading and the real fix is replacing the mouse or the encoder.
