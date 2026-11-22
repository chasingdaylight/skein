//! The static site of a project: each document and item file as a page
//! (its markers as anchors, its references as links, as `skein render`
//! writes Markdown, then as HTML), the images and other files beside
//! them, a front page that lists the documents, and an index of all the
//! items with what links to them and refers to them.

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Workspace = @import("../commands/Workspace.zig");
const files = @import("../files.zig");
const html = @import("../html/blocks.zig");
const inline_html = @import("../html/inline.zig");
const layout = @import("layout.zig");
const markdown = @import("markdown.zig");
const walk = @import("../graph/walk.zig");

/// The files of the sources copied as they are, for the pages to use
const assets = [_][]const u8{ ".png", ".svg", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".css" };

/// A page of a document or item file: where it is, and its HTML
const Rendered = struct { file: []const u8, page: layout.Page, body: []const u8 };

/// Writes the site of `ws` to `out`; the number of pages
pub fn build(io: Io, arena: std.mem.Allocator, ws: *Workspace, ctx: markdown.Context, out: Io.Dir) !usize {
    const rendered = try renderAll(io, arena, ws, ctx, out);

    var pages: std.ArrayList(layout.Page) = .empty;
    try pages.append(arena, .{ .path = "index.html", .title = "Overview" });
    for (rendered) |r| try pages.append(arena, r.page);
    try pages.append(arena, .{ .path = "items.html", .title = "All items" });
    const name = if (ws.project.name.len > 0) ws.project.name else "Project";

    for (rendered) |r| try write(io, out, r.page.path, try layout.page(arena, name, pages.items, r.page, r.body));
    try write(io, out, "index.html", try layout.page(arena, name, pages.items, pages.items[0], try front(arena, name, ws, ctx, rendered.len, pages.items)));
    try write(io, out, "items.html", try layout.page(arena, name, pages.items, pages.items[pages.items.len - 1], try index(arena, ws, ctx)));
    return pages.items.len;
}

/// Writes each document of `ws` as one HTML file of its own, its images
/// in it, for delivery; the number of files
pub fn documents(io: Io, arena: std.mem.Allocator, ws: *Workspace, ctx: markdown.Context, out: Io.Dir) !usize {
    var written: usize = 0;
    for (try renderAll(io, arena, ws, ctx, null)) |r| {
        const body = try embedImages(io, arena, ws.root, r.file, r.body);
        try write(io, out, r.page.path, try layout.standalone(arena, r.page.title, body));
        written += 1;
    }
    return written;
}

/// Every document and item file of `ws` as HTML; the files of the
/// sources are copied to `out` when there is one
fn renderAll(io: Io, arena: std.mem.Allocator, ws: *Workspace, ctx: markdown.Context, out: ?Io.Dir) ![]const Rendered {
    var rendered: std.ArrayList(Rendered) = .empty;
    for (ws.project.sources) |source| {
        // a source that cannot be read was reported when the items were
        const paths = files.list(io, arena, ws.root, source.path, &.{".md"}) catch continue;
        for (paths) |file| {
            if (source.kind == .items and !markdown.fileIncluded(ctx, file)) continue;
            const text = ws.root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch continue;
            var doc: html.Document = .{ .arena = arena, .options = .{ .md_links_to_html = true } };
            var title: []const u8 = Io.Dir.path.basenamePosix(file);
            switch (source.kind) {
                .documents => try doc.render(try markdown.document(ctx, file, text)),
                .items => {
                    const item = for (ws.graph.items) |*it| {
                        if (std.mem.eql(u8, it.file, file)) break it;
                    } else null;
                    if (item) |it| {
                        title = it.id;
                        try doc.out.appendSlice(arena, "<h1>");
                        try inline_html.escape(arena, &doc.out, it.id);
                        try doc.out.appendSlice(arena, "</h1>\n");
                    }
                    try doc.render(try markdown.itemFile(ctx, file, text));
                },
            }
            if (doc.title) |t| title = try plain(arena, t);
            try rendered.append(arena, .{ .file = file, .page = .{ .path = try htmlPath(arena, file), .title = title }, .body = doc.out.items });
        }
        if (out) |dir| try copyAssets(io, arena, ws.root, source.path, dir);
    }
    return rendered.items;
}

/// `body` with each image of a relative address put in it, as a `data:`
/// address, so that the file stands alone; an image that cannot be read
/// is left as it is
fn embedImages(io: Io, arena: std.mem.Allocator, root: Io.Dir, file: []const u8, body: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var rest = body;
    const tag = "<img src=\"";
    while (std.mem.find(u8, rest, tag)) |at| {
        const start = at + tag.len;
        const end = std.mem.findScalarPos(u8, rest, start, '"') orelse break;
        const src = rest[start..end];
        try out.appendSlice(arena, rest[0..start]);
        const kind = mimeOf(src);
        const embedded = if (kind == null or std.mem.findScalar(u8, src, ':') != null or std.mem.startsWith(u8, src, "/")) null else blk: {
            const dir = Io.Dir.path.dirnamePosix(file) orelse ".";
            const path = try Io.Dir.path.join(arena, &.{ dir, src });
            std.mem.replaceScalar(u8, path, '\\', '/');
            const data = root.readFileAlloc(io, path, arena, .limited(1 << 26)) catch break :blk null;
            const encoded = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(data.len));
            break :blk try arena.print("data:{s};base64,{s}", .{ kind.?, std.base64.standard.Encoder.encode(encoded, data) });
        };
        try out.appendSlice(arena, embedded orelse src);
        rest = rest[end..];
    }
    try out.appendSlice(arena, rest);
    return out.items;
}

fn mimeOf(src: []const u8) ?[]const u8 {
    const table = [_]struct { []const u8, []const u8 }{
        .{ ".png", "image/png" },   .{ ".svg", "image/svg+xml" }, .{ ".jpg", "image/jpeg" },
        .{ ".jpeg", "image/jpeg" }, .{ ".gif", "image/gif" },     .{ ".webp", "image/webp" },
    };
    for (table) |entry| {
        if (std.ascii.endsWithIgnoreCase(src, entry[0])) return entry[1];
    }
    return null;
}

fn write(io: Io, out: Io.Dir, path: []const u8, data: []const u8) !void {
    if (Io.Dir.path.dirnamePosix(path)) |parent| try out.createDirPath(io, parent);
    try out.writeFile(io, .{ .sub_path = path, .data = data });
}

/// `a/b.md` as `a/b.html`
pub fn htmlPath(arena: std.mem.Allocator, file: []const u8) ![]const u8 {
    return arena.print("{s}.html", .{file[0 .. file.len - 3]});
}

/// The text of a heading without its Markdown, for a title
fn plain(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (std.mem.findScalar(u8, "*_`", c) == null) try out.append(arena, c);
    }
    return out.items;
}

fn copyAssets(io: Io, arena: std.mem.Allocator, root: Io.Dir, dir: []const u8, out: Io.Dir) !void {
    const paths = files.list(io, arena, root, dir, &assets) catch return;
    for (paths) |file| {
        const data = root.readFileAlloc(io, file, arena, .limited(1 << 28)) catch continue;
        try write(io, out, file, data);
    }
}

/// The front page: the project's documents, with their titles
fn front(arena: std.mem.Allocator, name: []const u8, ws: *const Workspace, ctx: markdown.Context, page_count: usize, pages: []const layout.Page) ![]const u8 {
    const items = countIncluded(ws, ctx);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "<h1>");
    try inline_html.escape(arena, &out, name);
    try out.print(arena, "</h1>\n<p>{d} item{s} in {d} page{s}. <a href=\"items.html\">All items</a>.</p>\n<table>\n<thead><tr><th>Page</th><th>File</th></tr></thead>\n<tbody>\n", .{
        items, if (items == 1) "" else "s", page_count, if (page_count == 1) "" else "s",
    });
    for (pages[1 .. pages.len - 1]) |p| {
        try out.appendSlice(arena, "<tr><td><a href=\"");
        try inline_html.attribute(arena, &out, p.path);
        try out.appendSlice(arena, "\">");
        try inline_html.escape(arena, &out, p.title);
        try out.appendSlice(arena, "</a></td><td><code>");
        try inline_html.escape(arena, &out, try std.fmt.allocPrint(arena, "{s}.md", .{p.path[0 .. p.path.len - 5]}));
        try out.appendSlice(arena, "</code></td></tr>\n");
    }
    try out.appendSlice(arena, "</tbody>\n</table>\n");
    return out.items;
}

/// Where the page `from` links to `item`
fn href(arena: std.mem.Allocator, ctx: markdown.Context, from: []const u8, item: *const Item) ![]const u8 {
    const to = try htmlPath(arena, item.file);
    const path = try markdown.relative(arena, from, to);
    return if (markdown.isItemFile(ctx, item.file)) path else arena.print("{s}#{s}", .{ path, item.id });
}

/// The index of all items: each with its type, category and status,
/// where it is, and what links to it, refers to it and mentions it
fn index(arena: std.mem.Allocator, ws: *const Workspace, ctx: markdown.Context) ![]const u8 {
    const graph = &ws.graph;
    var out: std.ArrayList(u8) = .empty;
    const count = countIncluded(ws, ctx);
    try out.print(arena, "<h1>All items</h1>\n<p>{d} item{s}.</p>\n<table>\n<thead><tr><th>Item</th><th>Type</th><th>Category</th><th>Status</th><th>Linked from</th><th>Referred to by</th></tr></thead>\n<tbody>\n", .{ count, if (count == 1) "" else "s" });
    for (graph.items) |*item| {
        if (!markdown.included(ctx, item)) continue;
        try out.print(arena, "<tr id=\"", .{});
        try inline_html.attribute(arena, &out, item.id);
        try out.appendSlice(arena, "\"><td><a href=\"");
        try inline_html.attribute(arena, &out, try href(arena, ctx, "items.html", item));
        try out.appendSlice(arena, "\"><code>");
        try inline_html.escape(arena, &out, item.id);
        try out.appendSlice(arena, "</code></a></td><td>");
        try inline_html.escape(arena, &out, item.type_name);
        try out.appendSlice(arena, "</td><td>");
        try inline_html.escape(arena, &out, item.category orelse "");
        try out.appendSlice(arena, "</td><td>");
        if (ws.project.schema.itemType(item.type_name)) |t| try inline_html.escape(arena, &out, item.effectiveStatus(t));
        try out.appendSlice(arena, "</td><td>");
        var first = true;
        for (try walk.incoming(arena, graph, item.id)) |in| {
            if (!markdown.included(ctx, in.from)) continue;
            if (!first) try out.appendSlice(arena, ", ");
            first = false;
            try ref(arena, &out, ctx, in.from, in.link.type_name);
        }
        try out.appendSlice(arena, "</td><td>");
        first = true;
        for (try walk.referencedBy(arena, graph, item.id)) |id| {
            const from = graph.find(id) orelse continue;
            if (!markdown.included(ctx, from)) continue;
            if (!first) try out.appendSlice(arena, ", ");
            first = false;
            try ref(arena, &out, ctx, from, null);
        }
        const mentions = try walk.mentionsOf(arena, graph, item.id);
        if (mentions.len > 0) {
            if (!first) try out.appendSlice(arena, ", ");
            try out.print(arena, "mentioned {d} time{s}", .{ mentions.len, if (mentions.len == 1) "" else "s" });
        }
        try out.appendSlice(arena, "</td></tr>\n");
    }
    try out.appendSlice(arena, "</tbody>\n</table>\n");
    return out.items;
}

/// A link from the index to `item`, with the link type when there is one
fn ref(arena: std.mem.Allocator, out: *std.ArrayList(u8), ctx: markdown.Context, item: *const Item, link_type: ?[]const u8) !void {
    if (link_type) |t| {
        try inline_html.escape(arena, out, t);
        try out.append(arena, ' ');
    }
    try out.appendSlice(arena, "<a href=\"");
    try inline_html.attribute(arena, out, try href(arena, ctx, "items.html", item));
    try out.appendSlice(arena, "\"><code>");
    try inline_html.escape(arena, out, item.id);
    try out.appendSlice(arena, "</code></a>");
}

test {
    _ = Graph;
    _ = @import("_test/site.zig");
}

/// How many items are rendered
fn countIncluded(ws: *const Workspace, ctx: markdown.Context) usize {
    var n: usize = 0;
    for (ws.graph.items) |*item| {
        if (markdown.included(ctx, item)) n += 1;
    }
    return n;
}
