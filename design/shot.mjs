// Screenshot the preview with headless Chrome, for Claude to look at a design without
// driving anyone's browser. Waits for the page's ready flag (set once the gallery has
// built), then captures the full page at 2x.
//
//   node design/shot.mjs <url> <out.png> [css selector to clip to]
//
// Chrome's own `--headless --screenshot` fires on a virtual-time budget and caught the
// page before the gallery had decoded build/snapshot.png, giving a blank gallery.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, out, selector] = process.argv.slice(2);
if (!url || !out) {
  console.error("usage: node design/shot.mjs <url> <out.png> [selector]");
  process.exit(2);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const profile = mkdtempSync(join(tmpdir(), "dac-shot-"));
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ["--headless=new", "--remote-debugging-port=0", "--hide-scrollbars", `--user-data-dir=${profile}`, "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });

try {
  // Port 0 lets Chrome pick a free port; it announces the address on stderr.
  const browserWs = await new Promise((resolve, reject) => {
    let buf = "";
    chrome.stderr.on("data", (d) => {
      buf += d;
      const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
      if (m) resolve(m[1]);
    });
    // unref: a pending timer would otherwise hold node open for the full 10s after success.
    setTimeout(() => reject(new Error("Chrome didn't start")), 10_000).unref();
  });
  const port = new URL(browserWs).port;
  const page = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    pending.get(m.id)?.(m.result);
  });
  const send = (method, params = {}) => new Promise((r) => { pending.set(++id, r); ws.send(JSON.stringify({ id, method, params })); });
  const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true })).result.value;

  await send("Emulation.setDeviceMetricsOverride", { width: 1600, height: 1000, deviceScaleFactor: 2, mobile: false });
  await send("Page.navigate", { url });
  for (let i = 0; i < 100 && (await evaluate("document.body?.dataset.ready")) !== "1"; i++) await sleep(100);

  let clip;
  if (selector) {
    clip = JSON.parse(await evaluate(`JSON.stringify(document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect())`));
  } else {
    const { cssContentSize: s } = await send("Page.getLayoutMetrics");
    clip = { x: 0, y: 0, width: s.width, height: s.height };
  }
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: { ...clip, scale: 1 } });
  writeFileSync(out, Buffer.from(shot.data, "base64"));
  console.log(`→ ${out}`);
  ws.close();
} finally {
  // Chrome keeps writing its profile until it has actually exited.
  const exited = new Promise((r) => chrome.once("exit", r));
  chrome.kill();
  await exited;
  rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
