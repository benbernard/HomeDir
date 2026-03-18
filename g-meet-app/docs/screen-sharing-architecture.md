# Screen Sharing Architecture

## Overview

Meety uses two completely different capture mechanisms depending on what the user
wants to share. This is intentional -- each mechanism is best suited for its use
case. The choice is made via a custom picker window (`picker.html`) that appears
before any native/system UI.

### Path 1: Entire Screen (desktopCapturer + getUserMedia)

**Flow:**

1. Google Meet calls `navigator.mediaDevices.getDisplayMedia(constraints)`.
2. Our interceptor (injected via `executeJavaScript` on `did-finish-load`) catches
   the call and shows the custom picker via `window.meetyShare.showPicker()` (IPC
   to main process).
3. Main process opens `picker.html` as a modal BrowserWindow.
4. User clicks "Entire Screen".
5. `picker-show-sources` IPC fires. Main process calls
   `desktopCapturer.getSources({ types: ['screen'] })` and pushes thumbnails to
   the picker window via `executeJavaScript`.
6. User clicks a screen thumbnail.
7. `picker-select` IPC fires with the source ID (e.g. `screen:0:0`). Picker
   window closes. Promise resolves with the source ID.
8. Back in the renderer interceptor, `getUserMedia` is called with:
   ```js
   { video: { mandatory: { chromeMediaSource: 'desktop', chromeMediaSourceId: id } } }
   ```
9. Electron creates an `SCStream` (ScreenCaptureKit) for that screen and returns
   a `MediaStream` directly. **No `setDisplayMediaRequestHandler` is involved.**
10. The stream is returned to Google Meet as if `getDisplayMedia` produced it.

**Why this path:** `desktopCapturer` lets us show the user a thumbnail grid of
available screens and capture the exact one they chose, without going through the
macOS system picker (which doesn't distinguish well between multiple monitors and
adds an extra click).

### Path 2: Application Window (system picker via getDisplayMedia)

**Flow:**

1. Same as above through step 3.
2. User clicks "Application Window".
3. `picker-use-system` IPC fires. Picker window closes. Promise resolves with the
   sentinel value `'__system_picker__'`.
4. Back in the renderer interceptor, the *original* `getDisplayMedia(constraints)`
   is called (the real browser API, captured before our interceptor replaced it).
5. This triggers Electron's `setDisplayMediaRequestHandler` on the session.
6. Because the handler was registered with `{ useSystemPicker: true }`, Electron
   shows the native macOS `SCContentSharingPicker` (the system picker).
7. User picks a window in the system picker.
8. Electron internally creates an `SCStream` for the chosen window and resolves
   the `getDisplayMedia` promise with a `MediaStream`.
9. That stream is returned to Google Meet.

**Why this path:** The macOS system picker (`SCContentSharingPicker`) natively
supports single-window selection with live previews, app filtering, and the proper
system-level sharing indicator (menu bar icon). It's the best UX for picking
individual app windows.

## Key Components

### Interceptor (injected into renderer)

Installed once on `did-finish-load`. Captures `origGetDisplayMedia` before
replacing `navigator.mediaDevices.getDisplayMedia`. The guard
`window.__meetyInterceptorInstalled` prevents double-installation.

The interceptor is the decision point: based on the picker result, it either calls
`getUserMedia` (Entire Screen) or `origGetDisplayMedia` (Application Window).

### Custom Picker (`picker.html` + `picker-preload.js`)

A modal BrowserWindow with two buttons. Communicates with the main process via
`ipcRenderer.send` (fire-and-forget IPC):

| IPC Channel            | Direction       | Purpose                          |
|------------------------|-----------------|----------------------------------|
| `picker-show-sources`  | picker -> main  | Request screen/window thumbnails |
| `picker-select`        | picker -> main  | User chose a specific source     |
| `picker-use-system`    | picker -> main  | User wants the system picker     |
| `picker-cancel`        | picker -> main  | User cancelled                   |

All four are registered as `ipcMain.once` inside `showSharePicker()` and cleaned
up in the `finish()` helper (plus the `on('closed')` fallback).

### Display Media Request Handler (session-level)

Registered once on `meetSession`:

```js
meetSession.setDisplayMediaRequestHandler((request, callback) => {
  callback({});
}, { useSystemPicker: true });
```

With `useSystemPicker: true`, the handler body is a fallback that should rarely
(never on macOS 15+) be called. The system picker is shown by Electron internally.

### Native Addon (`picker_config.node`)

An Objective-C++ N-API addon that directly manipulates `SCContentSharingPicker`.
Currently used only for cleanup:

- **`cleanupPicker()`** -- sets `SCContentSharingPicker.sharedPicker.active = NO`.
  Called at startup (clear stale state from previous crashes) and at `will-quit`.
- **`configurePicker()`** / **`presentWindowPicker()`** -- configure and present
  the system picker for single-window mode. These are available but **not called**
  in the current flow (Electron's `useSystemPicker` handles presentation).

## Known Issues and Sharp Edges

### CRASH: Entire Screen -> Stop -> Application Window

**Status:** Unresolved.

**Symptom:** If the user shares their entire screen (Path 1), stops sharing, then
tries to share an application window (Path 2), the app crashes.

**Likely cause:** The `getUserMedia` desktop capture (Path 1) creates an `SCStream`
in ScreenCaptureKit. When sharing is stopped, Google Meet may not call
`track.stop()` on the media tracks -- it might just remove the track from the
RTCPeerConnection. This leaves the `SCStream` active at the OS level. When Path 2
then invokes `getDisplayMedia` with `useSystemPicker`, Electron tries to activate
`SCContentSharingPicker`, which may conflict with the still-active `SCStream`
capture session, causing a native crash in ScreenCaptureKit.

**Attempted fix (didn't work):** Tracking the previous stream in the interceptor
and explicitly calling `track.stop()` on all live tracks before starting a new
share. This suggests the issue is deeper than track lifecycle -- possibly an
Electron or ScreenCaptureKit bug where the internal capture session isn't released
even after tracks are stopped.

**Potential investigation paths:**

1. **Add crash reporting** -- wrap the app with Electron's `crashReporter` or
   catch `render-process-gone` / `child-process-gone` events to get stack traces.
   This would confirm whether the crash is in the main process, renderer, or GPU
   process, and narrow down the exact ScreenCaptureKit call that fails.

2. **Delay between shares** -- after stopping tracks, wait (e.g. 500ms) before
   calling `origGetDisplayMedia`. ScreenCaptureKit might need time to fully tear
   down the previous `SCStream`.

3. **Use desktopCapturer for both paths** -- instead of the system picker for
   application windows, use `desktopCapturer.getSources({ types: ['window'] })`
   and `getUserMedia` for both paths. This avoids `getDisplayMedia` and the system
   picker entirely. Downside: no live preview in the picker, no system sharing
   indicator.

4. **Use getDisplayMedia for both paths** -- instead of `getUserMedia` for entire
   screen, route both paths through `getDisplayMedia` and the
   `setDisplayMediaRequestHandler`. For entire screen, the handler callback could
   provide the source directly (via `desktopCapturer.getSources`) instead of using
   `useSystemPicker`. This would require conditionally switching how the handler
   responds, which adds complexity.

5. **Re-register the display media handler** -- call
   `setDisplayMediaRequestHandler` again with a fresh handler before each
   `getDisplayMedia` call. This might reset Electron's internal state.

6. **Native cleanup between shares** -- call `pickerNative.cleanupPicker()` (which
   sets `SCContentSharingPicker.active = NO`) via IPC before invoking the system
   picker. This might reset the singleton's state.

7. **Check Electron version** -- this may be a bug in Electron 35 specifically.
   Test with Electron 33/34 or a newer beta to see if the behavior changes.

### SCContentSharingPicker is a Singleton

`SCContentSharingPicker.sharedPicker` is a process-wide singleton. Both the native
addon and Electron's `useSystemPicker` interact with the same instance. Currently
the addon only touches it at startup/quit, but care must be taken if the addon's
`presentWindowPicker()` is ever used -- it would conflict with Electron's internal
picker management.

### desktopCapturer.getSources() is Deprecated

As of Electron 32+, `desktopCapturer.getSources()` in the renderer is deprecated.
Meety calls it from the main process (which still works) but this API may be
removed in future Electron versions. The long-term replacement is
`getDisplayMedia` with the system picker, but that doesn't support the "show a
thumbnail grid" UX we use for Entire Screen selection.

### ipcMain.once Listener Cleanup

`showSharePicker()` registers four `ipcMain.once` listeners each time it's called.
The `finish()` helper and `on('closed')` handler both call
`ipcMain.removeAllListeners` for those channels. This is safe because:

- The channels (`picker-select`, etc.) are only used by the picker.
- `removeAllListeners` doesn't affect `ipcMain.handle` listeners.
- The `resolved` guard prevents double-resolution of the promise.

But be aware: if any other code ever uses these channel names, the
`removeAllListeners` call will nuke those listeners too.

### callback({}) in the Fallback Handler

The `setDisplayMediaRequestHandler` fallback calls `callback({})` to deny. Per
Electron docs this is valid (empty object = denial). However, `callback()` (no
args) is the more conventional denial pattern. If Electron's behavior changes in a
future version, this could become a problem.

### getUserMedia chromeMediaSource is Legacy

The `chromeMediaSource: 'desktop'` constraint in `getUserMedia` is a
Chrome/Electron-specific extension that predates `getDisplayMedia`. It still works
in Electron 35 but is not part of the web standard and could be removed. If
removed, Entire Screen sharing would need to move to `getDisplayMedia` with the
handler providing the source.

## File Map

| File                  | Role                                                    |
|-----------------------|---------------------------------------------------------|
| `main.js`             | App lifecycle, IPC handlers, interceptor injection,     |
|                       | display media request handler, picker window management |
| `preload.js`          | Exposes `meetyShare.showPicker()` to the renderer       |
| `picker.html`         | Custom share picker UI (two buttons + thumbnail grid)   |
| `picker-preload.js`   | Exposes `pickerIPC` methods to `picker.html`            |
| `native/picker_config.mm` | N-API addon for SCContentSharingPicker management  |
| `binding.gyp`         | Build config for the native addon                       |
