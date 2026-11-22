//! The page around a rendered document: one HTML file with its styles
//! inline, light and dark, a navigation of the site's pages, and nothing
//! loaded from elsewhere. Every link in it is relative, so the site can
//! be served under any address, or opened from disk.

const std = @import("std");

const inline_html = @import("../html/inline.zig");
const markdown = @import("markdown.zig");

pub const Error = std.mem.Allocator.Error;

/// A page of the site
pub const Page = struct {
    /// the page's path in the site, with forward slashes: `spec/lex.html`
    path: []const u8,
    title: []const u8,
};

pub const style =
    \\:root{--bg:#fbfaf8;--panel:#f3f0ea;--fg:#1f1d1a;--muted:#6a645b;--accent:#9a3412;--rule:#e2dcd1;--code:#efebe3;--id:#f6e9dc;--bad:#b42318}
    \\@media (prefers-color-scheme:dark){:root{--bg:#161514;--panel:#1d1b19;--fg:#ece7df;--muted:#a39b8f;--accent:#fdba74;--rule:#302c28;--code:#24211e;--id:#33261b;--bad:#f97066}}
    \\*{box-sizing:border-box}html{scroll-padding-top:1rem}
    \\body{margin:0;background:var(--bg);color:var(--fg);font:1rem/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
    \\.page{display:grid;grid-template-columns:16rem minmax(0,1fr);min-height:100vh}
    \\nav{background:var(--panel);border-right:1px solid var(--rule);padding:1.5rem 1.25rem;font-size:.95rem}
    \\nav .brand{display:block;margin-bottom:1rem;font-size:1.3rem;font-weight:700;color:var(--fg);text-decoration:none}
    \\nav ul{list-style:none;margin:0;padding:0}nav li a{display:block;padding:.25rem .5rem;margin:0 -.5rem;border-radius:.3rem;color:var(--fg);text-decoration:none}
    \\nav li a:hover{background:var(--rule)}nav li a[aria-current=page]{color:var(--accent);font-weight:600}
    \\main{padding:2rem 1.5rem 4rem}article{max-width:48rem;margin:0 auto}
    \\h1,h2,h3{line-height:1.25}h1{font-size:2rem;margin:0 0 1rem}h2{font-size:1.35rem;margin:2.25rem 0 .75rem;padding-top:1.25rem;border-top:1px solid var(--rule)}
    \\a{color:var(--accent);text-underline-offset:.18em}
    \\.skein-unresolved{color:var(--bad);text-decoration:underline wavy;text-underline-offset:.2em;cursor:help}
    \\code,pre{font-family:ui-monospace,"Cascadia Code",Consolas,Menlo,monospace;font-size:.9em}code{background:var(--code);padding:.1em .3em;border-radius:.25rem}
    \\pre{background:var(--code);padding:.9rem 1rem;border-radius:.4rem;overflow-x:auto;line-height:1.5}pre code{background:none;padding:0;font-size:1em}
    \\table{border-collapse:collapse;width:100%;font-size:.95rem;display:block;overflow-x:auto}th,td{text-align:left;vertical-align:top;padding:.45rem .7rem;border-bottom:1px solid var(--rule)}th{color:var(--muted);font-weight:600}
    \\blockquote{margin:1rem 0;padding:.1rem 1rem;border-left:3px solid var(--rule);color:var(--muted)}
    \\a[id]+strong>a{font-family:ui-monospace,Consolas,Menlo,monospace;font-size:.85em;background:var(--id);padding:.1em .4em;border-radius:.25rem;text-decoration:none}a[id]+strong+em{color:var(--muted);font-size:.9em}
    \\footer{max-width:48rem;margin:3rem auto 0;padding-top:1rem;border-top:1px solid var(--rule);color:var(--muted);font-size:.9rem}
    \\@media (max-width:52rem){.page{display:block}nav{border-right:0;border-bottom:1px solid var(--rule);padding:1rem}nav ul{display:flex;flex-wrap:wrap;gap:0 .75rem}nav li a{margin:0}main{padding:1.5rem 1rem 3rem}}
    \\@media print{:root{--bg:#fff;--fg:#000;--muted:#444;--accent:#000;--rule:#bbb;--code:#f2f2f2;--id:#eee}nav,footer{display:none}.page{display:block}main{padding:0}article{max-width:none}body{font-size:11pt}h1,h2,h3{break-after:avoid}pre,table,blockquote{break-inside:avoid}table{display:table}a{text-decoration:none}}
;

/// A document that stands alone, for delivery: the same styles, no
/// navigation and nothing that refers to the rest of the site
pub fn standalone(arena: std.mem.Allocator, title: []const u8, body: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>");
    try inline_html.escape(arena, &out, title);
    try out.appendSlice(arena, "</title>\n<style>\n");
    try out.appendSlice(arena, style);
    try out.appendSlice(arena, "\n.page{display:block}main{padding:2rem 1.5rem}\n</style>\n</head>\n<body>\n<div class=\"page\">\n<main>\n<article>\n");
    try out.appendSlice(arena, body);
    try out.appendSlice(arena, "</article>\n</main>\n</div>\n</body>\n</html>\n");
    return out.items;
}

/// The whole page `current`, with `body` (HTML) in it and links to all of
/// `pages`
pub fn page(arena: std.mem.Allocator, project: []const u8, pages: []const Page, current: Page, body: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>");
    if (!std.mem.eql(u8, current.path, "index.html")) {
        try inline_html.escape(arena, &out, current.title);
        try out.appendSlice(arena, " · ");
    }
    try inline_html.escape(arena, &out, project);
    try out.appendSlice(arena, "</title>\n<style>\n");
    try out.appendSlice(arena, style);
    try out.appendSlice(arena, "\n</style>\n</head>\n<body>\n<div class=\"page\">\n<nav aria-label=\"Pages\">\n<a class=\"brand\" href=\"");
    try out.appendSlice(arena, try markdown.relative(arena, current.path, "index.html"));
    try out.appendSlice(arena, "\">");
    try inline_html.escape(arena, &out, project);
    try out.appendSlice(arena, "</a>\n<ul>\n");
    for (pages) |p| {
        try out.appendSlice(arena, "<li><a href=\"");
        try inline_html.attribute(arena, &out, try markdown.relative(arena, current.path, p.path));
        try out.append(arena, '"');
        if (std.mem.eql(u8, p.path, current.path)) try out.appendSlice(arena, " aria-current=\"page\"");
        try out.append(arena, '>');
        try inline_html.escape(arena, &out, p.title);
        try out.appendSlice(arena, "</a></li>\n");
    }
    try out.appendSlice(arena, "</ul>\n</nav>\n<main>\n<article>\n");
    try out.appendSlice(arena, body);
    try out.appendSlice(arena, "</article>\n<footer>Made with skein.</footer>\n</main>\n</div>\n</body>\n</html>\n");
    return out.items;
}
