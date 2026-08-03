// Live frame-time meter. The examples page does not load this, because it is
// only wanted while chasing a slow frame and every example is better served by
// the plainest possible page. Turn it on by hand from the devtools console, on
// any page the dev server is serving:
//
//   await import('/perf.js')
//
// Each frame splits into:
//   app     everything inside the runtime's enter(), meaning update, render,
//           diff and DOM patching (read from app.perf)
//   render  the browser's main-thread render phase (style, layout, paint,
//           commit), measured from the end of this rAF callback to a message
//           task queued at that moment, which the browser runs right after
//           the frame's rendering work
//   gap     time between consecutive rAF timestamps
//
// Anything gap holds beyond app + render + vsync is other main-thread work the
// page cannot observe directly (hit testing, GC). All three are exponential
// moving averages.
export function meter(app = window.app) {
  // The runtime only keeps timings while this is set, so whatever the app did
  // before the import (its boot render, most of all) is not counted. That is
  // one sample either way in a moving average.
  app.perf.enabled = true;

  const box = document.createElement('pre');
  box.style.cssText =
    'position:fixed;top:8px;right:8px;margin:0;padding:8px 12px;' +
    'font:13px/1.5 monospace;background:#000c;color:#7f7;' +
    'border-radius:6px;contain:layout paint;z-index:9999';
  document.body.append(box);

  const ema = (old, v) => (old === 0 ? v : old * 0.9 + v * 0.1);
  let gap = 0, appMs = 0, render = 0;
  let lastT = 0, lastBusy = app.perf.busyMs, sentAt = 0, frames = 0;
  const chan = new MessageChannel();
  chan.port1.onmessage = () => { render = ema(render, performance.now() - sentAt); };

  const frame = (t) => {
    if (lastT) gap = ema(gap, t - lastT);
    lastT = t;
    appMs = ema(appMs, app.perf.busyMs - lastBusy);
    lastBusy = app.perf.busyMs;
    // The meter's own text write costs a little, refresh it at ~6 Hz.
    if (++frames % 10 === 0) {
      box.textContent =
        `gap    ${gap.toFixed(1).padStart(5)} ms\n` +
        `app    ${appMs.toFixed(1).padStart(5)} ms\n` +
        `render ${render.toFixed(1).padStart(5)} ms`;
    }
    sentAt = performance.now();
    chan.port2.postMessage(0);
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

// Importing it is the whole gesture, so start as soon as there is an app to
// read. The export is there for a page that mounts more than one.
if (window.app) meter(window.app);
