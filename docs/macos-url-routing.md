# macOS URL Routing

This repo owns several pieces of local URL routing. They decide which browser or
app opens links, which Chrome profile should be used, and how meeting links are
handled before they leave the shell or notification stack.

## Finicky

`.finicky.js` is the main macOS URL router.

Current behavior includes:

- Default browser is Google Chrome.
- Slack archive web URLs are rewritten to `slack://` deep links.
- `slack:` URLs open Slack.
- Google Meet URLs route to a dedicated meeting app target.
- Work-ish URLs such as GitHub, Instacart, Linear, AWS, `go/`, and `golinks.io`
  route to the work Chrome profile or native app.
- Personal URLs such as YouTube, Amazon, MyChart, LinkedIn, and Airtable route
  to the home Chrome profile.

Be careful editing match order. Some rules are intentionally before broader
rules, for example Linear before the broader Instacart/work routing.

## Browser Profile Constants

`.finicky.js` defines reusable browser targets:

- `WORK_CHROME`: Google Chrome profile `Default`.
- `HOME_CHROME`: Google Chrome profile `Profile 1`.
- `LINEAR_APP`: native Linear app.
- a meeting app target for Google Meet links.

The profile names are local machine conventions. Do not assume they are portable.

## Meeting URLs

The meeting notification stack may normalize Google Meet URLs to `gmeet://` so
clicks open the intended local meeting app instead of a normal browser tab.

Relevant files:

- `bin/ts/src/meeting-notify.ts`
- `bin/openMeetAndUrl.mjs`
- `.finicky.js`
- `docs/meeting-notification-architecture.md`

Do not add broad documentation for the meeting Electron app here. That app is
moving out of this repo. This doc should only describe routing behavior owned by
this home-directory repo.

## Legacy URL Opener

`bin/openUrl` is a Perl entry point that delegates to
`bin/perl/lib/UrlOpener.pm`. Older scripts may still use it.

Treat this as legacy unless a task specifically targets it. If modern URL
routing needs a change, check Finicky first.

## Operational Notes

When URL routing is broken, check:

1. Whether Finicky is running.
2. Whether `.finicky.js` syntax is valid.
3. Whether the target app path exists.
4. Whether a broader rule is matching before the intended rule.
5. Whether the caller passes `https://meet.google.com/...`, `gmeet://...`, or a
   different meeting URL shape.

Use targeted tests. Do not rewrite the routing table wholesale.
