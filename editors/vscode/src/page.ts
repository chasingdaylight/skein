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

/** The planning view's page: its script, from the extension's files, draws it */
export function planPage(scriptUri: string, cspSource: string, scriptNonce: string): string {
  return scriptPage("skein Plan", planStyle, scriptUri, cspSource, scriptNonce);
}

/** The graph view's page, drawn by its script */
export function graphPage(scriptUri: string, cspSource: string, scriptNonce: string): string {
  return scriptPage("skein Graph", graphStyle, scriptUri, cspSource, scriptNonce);
}

/** The item form's page, drawn by its script */
export function formPage(scriptUri: string, cspSource: string, scriptNonce: string): string {
  return scriptPage("skein Item", formStyle, scriptUri, cspSource, scriptNonce);
}

// the form's fields in the theme's colors
const formStyle = `
.fields { display: grid; gap: 8px; max-width: 640px; }
.field { display: grid; grid-template-columns: 140px 1fr; align-items: start; gap: 8px; }
.label { padding-top: 4px; font-family: var(--vscode-editor-font-family); }
input, select, textarea { background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border, transparent); padding: 4px 6px; font: inherit; width: 100%; box-sizing: border-box; }
.buttons { display: flex; gap: 8px; margin-top: 16px; }
button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 5px 14px; cursor: pointer; }
button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
.hint { color: var(--vscode-descriptionForeground); }
.said.error { color: var(--vscode-errorForeground); }
`;

/** A page that its script, from the extension's files, draws into `#root` */
function scriptPage(title: string, extraStyle: string, scriptUri: string, cspSource: string, scriptNonce: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${scriptNonce}' ${cspSource};">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>${style}${extraStyle}</style>
</head>
<body>
<div id="root"></div>
<script nonce="${scriptNonce}" src="${escape(scriptUri)}"></script>
</body>
</html>`;
}

// the Gantt chart and the board, in the theme's colors
const planStyle = `
.tabs { display: flex; gap: 4px; margin: 12px 0; }
.tab { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); border: none; padding: 4px 12px; cursor: pointer; }
.tab.active { background: var(--vscode-button-background); color: var(--vscode-button-foreground); }
.gantt { display: flex; border: 1px solid var(--vscode-panel-border, transparent); }
.names { flex: none; border-right: 1px solid var(--vscode-panel-border, transparent); }
.name { padding: 0 8px; line-height: 26px; white-space: nowrap; cursor: pointer; font-family: var(--vscode-editor-font-family); }
.name:hover { color: var(--vscode-textLink-foreground); }
.scroll { overflow-x: auto; }
.timeline .off { fill: var(--vscode-editor-inactiveSelectionBackground); opacity: 0.5; }
.timeline .week { stroke: var(--vscode-panel-border, var(--vscode-foreground)); stroke-opacity: 0.4; }
.timeline text { fill: var(--vscode-descriptionForeground); font-size: 10px; }
.timeline .day-label { text-anchor: middle; }
.bar .body { fill: var(--vscode-charts-blue); cursor: grab; }
.bar .end { fill: var(--vscode-charts-blue); opacity: 0.6; cursor: ew-resize; }
.bar.critical .body, .bar.critical .end { fill: var(--vscode-charts-red); }
.bar .milestone { fill: var(--vscode-charts-purple); cursor: grab; }
.arrow { fill: none; stroke: var(--vscode-descriptionForeground); stroke-width: 1; }
.hint { color: var(--vscode-descriptionForeground); }
.board { display: flex; gap: 12px; align-items: flex-start; overflow-x: auto; }
.column { flex: 0 0 220px; background: var(--vscode-sideBar-background); padding: 8px; min-height: 80px; border-radius: 4px; }
.column.over { outline: 2px dashed var(--vscode-focusBorder); }
.column h3 { margin: 0 0 8px; font-size: 1em; text-transform: capitalize; }
.card { background: var(--vscode-editor-background); border: 1px solid var(--vscode-panel-border, transparent); border-left: 3px solid var(--vscode-charts-blue); padding: 6px 8px; margin-bottom: 6px; cursor: grab; border-radius: 3px; }
.card.critical { border-left-color: var(--vscode-charts-red); }
.card-id { font-family: var(--vscode-editor-font-family); font-weight: 600; }
.card-meta { color: var(--vscode-descriptionForeground); font-size: 0.9em; }
`;

// the graph, its controls, the details beside it and the context menu
const graphStyle = `
body { padding: 0 12px; }
.controls { display: flex; flex-wrap: wrap; gap: 8px; align-items: flex-start; margin: 10px 0; }
.controls input[type=search], .controls select { background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border, transparent); padding: 3px 6px; }
.choose { background: var(--vscode-input-background); padding: 3px 6px; }
.choose label { display: block; }
.main { display: flex; gap: 12px; height: calc(100vh - 70px); }
.canvas { flex: 1; min-width: 0; border: 1px solid var(--vscode-panel-border, transparent); overflow: hidden; position: relative; }
.zoom { position: absolute; top: 8px; right: 8px; display: flex; gap: 2px; }
.zoom button { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); border: none; min-width: 28px; padding: 3px 8px; cursor: pointer; }
.zoom button:hover { background: var(--vscode-button-secondaryHoverBackground); }
.graph { width: 100%; height: 100%; cursor: grab; }
.node { cursor: pointer; }
.node rect { fill: var(--vscode-editor-background); stroke-width: 2; }
.node text { fill: var(--vscode-foreground); font-family: var(--vscode-editor-font-family); font-size: 12px; }
.node.selected rect { fill: var(--vscode-list-activeSelectionBackground); }
.node.selected text { fill: var(--vscode-list-activeSelectionForeground); }
.node.other rect { stroke-dasharray: 4 3; }
.dim { opacity: 0.25; }
.edge { fill: none; stroke: var(--vscode-descriptionForeground); stroke-width: 1.2; }
.edge.suspect { stroke: var(--vscode-charts-red); stroke-dasharray: 6 3; }
.edge.never-reviewed { stroke-dasharray: 2 3; }
.arrow { fill: var(--vscode-descriptionForeground); }
.details { flex: 0 0 38%; overflow: auto; border-left: 1px solid var(--vscode-panel-border, transparent); padding-left: 12px; }
.actions { display: flex; flex-wrap: wrap; gap: 4px; margin: 6px 0; }
.actions button { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); border: none; padding: 3px 10px; cursor: pointer; }
.menu { position: fixed; background: var(--vscode-menu-background); color: var(--vscode-menu-foreground); border: 1px solid var(--vscode-menu-border, var(--vscode-panel-border)); padding: 4px 0; z-index: 10; }
.menu-item { padding: 3px 16px; cursor: pointer; }
.menu-item:hover { background: var(--vscode-menu-selectionBackground); color: var(--vscode-menu-selectionForeground); }
`;

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
