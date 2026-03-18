# Rectangle (Region) Screen Capture

Electron's `desktopCapturer` API only supports capturing entire screens or
individual windows. There is no built-in way to capture a rectangular region of
the screen. Two approaches can solve this.

## Approach 1: Canvas-based cropping (simpler)

Capture the full screen, then crop in the renderer using a canvas:

1. Capture the full screen via `desktopCapturer` / `getUserMedia` with
   `chromeMediaSource: 'desktop'`.
2. Render the stream into a hidden `<video>` element.
3. Use a `<canvas>` with `drawImage(video, sx, sy, sw, sh, 0, 0, dw, dh)` to
   draw only the desired region on each frame.
4. Call `canvas.captureStream()` to produce a `MediaStream` from the cropped
   output.
5. Send that cropped stream to Meet (or wherever it's needed).

For the selection UI, overlay a transparent full-screen window and let the user
drag a rectangle. Record the coordinates and apply them as the crop region.

**Pros:** Pure JS, no native code, works today.
**Cons:** Captures full screen then discards pixels — slightly more CPU/GPU than
a native crop. Frame rate depends on how often you repaint the canvas.

### Sketch

```js
const video = document.createElement('video');
video.srcObject = fullScreenStream;
video.play();

const canvas = document.createElement('canvas');
canvas.width = regionWidth;
canvas.height = regionHeight;
const ctx = canvas.getContext('2d');

function drawFrame() {
  ctx.drawImage(video,
    regionX, regionY, regionWidth, regionHeight,  // source rect
    0, 0, regionWidth, regionHeight);              // dest rect
  requestAnimationFrame(drawFrame);
}
drawFrame();

const croppedStream = canvas.captureStream(30); // 30 fps
```

## Approach 2: Native ScreenCaptureKit `sourceRect` (more work, more efficient)

macOS's ScreenCaptureKit framework supports a `sourceRect` property on
`SCStreamConfiguration` that captures only a specific rectangle of the screen at
the system level — no wasted pixels.

This requires a native Node addon (Objective-C++ compiled with node-gyp) that:

1. Creates an `SCContentFilter` for the target display.
2. Sets `SCStreamConfiguration.sourceRect` to the desired `CGRect`.
3. Creates and starts an `SCStream`.
4. Receives `CMSampleBuffer` frames via `SCStreamOutput`.
5. Converts frames to a format consumable by Electron (e.g., `IOSurface` or raw
   pixel buffers sent back to JS).

The addon would expose an API like:

```js
const regionCapture = require('./native/region_capture');
const stream = regionCapture.start({
  displayId: 1,
  rect: { x: 100, y: 200, width: 800, height: 600 },
  fps: 30,
});
```

Getting the frames into a `MediaStream` usable by WebRTC is the hard part. Options:
- Write frames to a virtual camera (complex).
- Use `MediaStreamTrackGenerator` (if available in Electron's Chromium).
- Use a `ReadableStream` of `VideoFrame` objects.
- Render frames to a canvas and use `captureStream()` (still simpler than full
  native but avoids capturing the whole screen).

**Pros:** Only captures the pixels you need — lower CPU/GPU usage.
**Cons:** Requires native Objective-C++ code, more complex build, harder to get
frames into WebRTC pipeline.

## Recommendation

Start with Approach 1 (canvas cropping). It's dramatically simpler and performs
well enough for most use cases. Only move to Approach 2 if profiling shows the
full-screen capture + crop is a bottleneck.
