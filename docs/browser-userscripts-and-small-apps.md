# Browser Userscripts And Small Apps

This repo tracks a handful of small browser-facing tools and local apps. They are
not all equally active, but they are real enough that future agents should know
where they live.

## User Scripts

`userScripts/` contains Chrome-oriented scripts and an extension package.

Tracked items include:

- `userScripts/github-pr-link-enhancer.user.js`
- `userScripts/madeline-google.user.js`
- `userScripts/prLinkEnhancer/`
- `userScripts/prLinkEnhancer.zip`

The top-level `userScripts/README.md` describes the older manual Chrome install
flow: download the raw script and drag it onto the Chrome extensions page.

`userScripts/prLinkEnhancer/README.md` points at the Chrome Web Store listing
for GitHub PR Link Enhancer.

## Todo Tracker

`todo-tracker/` is an Electron app for editing a selected `todo.json` file.

Key files:

- `todo-tracker/main.js`: Electron main process, file picker, file watcher, IPC.
- `todo-tracker/preload.js`: safe renderer bridge.
- `todo-tracker/index.html`: app UI.
- `todo-tracker/package.json`: `npm` scripts and Electron Builder config.

Useful commands:

```bash
cd todo-tracker
npm install
npm start
npm run dist
```

Runtime todo data such as `todo.json` is intentionally excluded from the packaged
app. Be careful not to commit personal task data.

## Automator Workflows

`Automate/` contains macOS Automator workflows, including OneDrive share helpers.
These are app bundles/directories, so diffs can be awkward.

Treat workflow edits as macOS artifact edits: inspect carefully and avoid
rewriting binary or plist content unless the task specifically targets it.

## Browser And App Glue In `bin/`

Relevant helpers include:

- `bin/openChromeDevtools`
- `bin/openKeyword`
- `bin/openMeetAndUrl.mjs`
- `bin/openUrl`
- `bin/registerURL`
- `bin/macUrl`

Some of these are older glue scripts. Check current callers before refactoring.

## Agent Guidance

- Do not add broad app docs for projects that are moving to another repo.
- Keep user data out of tracked app directories.
- For Electron app changes, follow that app's own `package.json`, not `bin/ts`
  tooling.
- For userscript changes, inspect the target script directly and avoid packaging
  churn unless asked.
