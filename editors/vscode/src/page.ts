// The pages of the trace and coverage views: the HTML skein renders, in a
// page styled by VS Code's theme, whose links are sent to the extension.
// No VS Code here, so that it is tested with Node alone.

/** Where a link of a page leads */
export type Link =
  | { kind: "item"; id: string }
  | { kind: "file"; file: string; line: number }
  | { kind: "external"; href: string };

/** The link `href` of a page: `skein:item/ID`, `skein:file/PATH#LINE`, or another */
export function parseLink(href: string): Link | undefined {
  if (href.startsWith("skein:item/")) {
    const id = decodeURIComponent(href.slice("skein:item/".length));
    return id ? { kind: "item", id } : undefined;
  }
  if (href.startsWith("skein:file/")) {
    const rest = href.slice("skein:file/".length);
    const hash = rest.lastIndexOf("#");
    const file = decodeURIComponent(hash < 0 ? rest : rest.slice(0, hash));
    const line = hash < 0 ? 1 : Number.parseInt(rest.slice(hash + 1), 10);
    return file ? { kind: "file", file, line: Number.isFinite(line) && line > 0 ? line : 1 } : undefined;
  }
  if (/^(https?|mailto):/.test(href)) return { kind: "external", href };
  return undefined;
}

/** A nonce for the page's script */
export function nonce(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let out = "";
  for (let i = 0; i < 32; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
  return out;
}

/** The page around `body`, the HTML skein rendered */
export function page(title: string, body: string, scriptNonce: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>${style}</style>
</head>
<body>
${body}
<script nonce="${scriptNonce}">${script}</script>
</body>
</html>`;
}

function escape(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// the colors and fonts of VS Code's theme
const style = `
body { font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground); background: var(--vscode-editor-background); padding: 0 20px 20px; line-height: 1.5; }
a { color: var(--vscode-textLink-foreground); text-decoration: none; }
a:hover { color: var(--vscode-textLink-activeForeground); text-decoration: underline; }
code, pre { font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size); }
code { background: var(--vscode-textCodeBlock-background); padding: 0 3px; border-radius: 3px; }
pre { background: var(--vscode-textCodeBlock-background); padding: 8px; overflow-x: auto; }
blockquote { margin: 0 0 1em; padding: 4px 12px; border-left: 3px solid var(--vscode-textBlockQuote-border); background: var(--vscode-textBlockQuote-background); }
table { border-collapse: collapse; margin: 0 0 1em; }
th, td { border: 1px solid var(--vscode-panel-border, var(--vscode-editorWidget-border)); padding: 3px 8px; text-align: left; vertical-align: top; }
th { background: var(--vscode-keybindingTable-headerBackground, transparent); }
h1, h2, h3 { font-weight: 600; }
h1 { font-size: 1.6em; border-bottom: 1px solid var(--vscode-panel-border, transparent); padding-bottom: 4px; }
h2 { font-size: 1.25em; margin-top: 1.4em; }
`;

// links go to the extension, which opens them in the editor
const script = `
const vscode = acquireVsCodeApi();
document.addEventListener("click", (event) => {
  const a = event.target instanceof Element ? event.target.closest("a") : null;
  if (!a) return;
  const href = a.getAttribute("href") || "";
  if (href.startsWith("#")) return;
  event.preventDefault();
  vscode.postMessage({ href });
});
`;
