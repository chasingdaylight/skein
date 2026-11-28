// Drives a VS Code window over the Chrome DevTools Protocol: keys, clicks
// on elements found by a selector or by their text, and screenshots.
import { writeFileSync } from "node:fs";

export async function connect(port = 9333) {
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === "page" && t.url.includes("workbench"));
  if (!page) throw new Error("no workbench page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, e) => { ws.onopen = r; ws.onerror = e; });
  let n = 0;
  const waiting = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) {
      const { resolve, reject } = waiting.get(msg.id);
      waiting.delete(msg.id);
      msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++n;
    waiting.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const evaluate = async (expr) => {
    const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    return r.result.value;
  };
  const keyCodes = { Enter: 13, Escape: 27, Tab: 9, ArrowDown: 40, ArrowUp: 38, Backspace: 8, F1: 112, End: 35, Home: 36 };
  const key = async (k, mods = 0) => {
    const code = keyCodes[k] ?? k.toUpperCase().charCodeAt(0);
    const base = { modifiers: mods, windowsVirtualKeyCode: code, key: k, code: k.length === 1 ? `Key${k.toUpperCase()}` : k };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...base });
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
    await sleep(150);
  };
  const type = async (text) => { await send("Input.insertText", { text }); await sleep(300); };
  /** the center of the first element matching `selector` whose text includes `text` */
  const where = (selector, text = "") => evaluate(`(() => {
    const els = [...document.querySelectorAll(${JSON.stringify(selector)})].filter((e) => e.getBoundingClientRect().width > 0 && (e.textContent || e.getAttribute('aria-label') || '').includes(${JSON.stringify(text)}));
    if (!els.length) return null;
    const r = els[0].getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height, left: r.x, top: r.y };
  })()`);
  const clickAt = async (x, y, button = "left") => {
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button, clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button, clickCount: 1 });
    await sleep(400);
  };
  const click = async (selector, text = "", button = "left") => {
    const at = await where(selector, text);
    if (!at) throw new Error(`nothing to click: ${selector} ${text}`);
    await clickAt(at.x, at.y, button);
    return at;
  };
  const hover = async (selector, text = "") => {
    const at = await where(selector, text);
    if (!at) throw new Error(`nothing to hover: ${selector} ${text}`);
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: at.x, y: at.y });
    await sleep(600);
  };
  /** runs a command through the command palette, by its title */
  const command = async (title, wait = 1200) => {
    await key("p", 2 | 8); // ctrl+shift+p
    await sleep(400);
    await type(">" + title);
    await sleep(500);
    await key("Enter");
    await sleep(wait);
  };
  /** a PNG of the window, or of a part of it */
  const shot = async (file, clip) => {
    const params = { format: "png" };
    if (clip) params.clip = { ...clip, scale: 1 };
    const r = await send("Page.captureScreenshot", params);
    writeFileSync(file, Buffer.from(r.data, "base64"));
  };
  const size = async (width, height) => {
    await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await sleep(800);
  };
  const sizeWindow = async (width, height) => {
    const { windowId } = await send("Browser.getWindowForTarget");
    await send("Browser.setWindowBounds", { windowId, bounds: { windowState: "normal" } });
    await send("Browser.setWindowBounds", { windowId, bounds: { width, height } });
    await sleep(800);
  };
  /** runs `fn` (source of a function of the document) in the newest webview, inside its frame */
  const inWebview = async (fn) => {
    const all = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const view = all.filter((t) => t.type === "iframe" && t.url.startsWith("vscode-webview://")).pop();
    if (!view) throw new Error("no webview");
    const vws = new WebSocket(view.webSocketDebuggerUrl);
    await new Promise((r, e) => { vws.onopen = r; vws.onerror = e; });
    const expression = `(() => { const d = document.querySelector("iframe#active-frame")?.contentDocument ?? document; return (${fn})(d); })()`;
    const result = await new Promise((r) => {
      vws.onmessage = (m) => r(JSON.parse(m.data).result?.result?.value);
      vws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression, returnByValue: true } }));
    });
    vws.close();
    await sleep(800);
    return result;
  };
  return { send, evaluate, inWebview, key, type, click, clickAt, hover, where, command, shot, size, sleep, close: () => ws.close() };
}
