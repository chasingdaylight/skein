//! `skein render`: the project's documents and item files as Markdown
//! for a site generator, written to a directory under their own paths,
//! or, with `--format html`, the static site itself (render/site.zig).
//! With `--editions`, each baseline is rendered too, under
//! `editions/NAME/`, with a page that lists them, so that readers can pick
//! the edition that matches a release.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Workspace = @import("Workspace.zig");
const context = @import("../render/context.zig");
const files = @import("../files.zig");
const history = @import("../history.zig");
const markdown = @import("../render/markdown.zig");
const order = @import("../render/order.zig");
const site = @import("../render/site.zig");
const xml = @import("../xml.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Render) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    const current = try renderInto(io, arena, &ws, options, options.out);
    if (!options.editions or current.status != .ok) return current;
    return editions(io, arena, &ws, options, current.text);
}

/// The project of `ws`, rendered to `out_path`
fn renderInto(io: Io, arena: std.mem.Allocator, ws: *Workspace, options: cli.Render, out_path: []const u8) !Workspace.Outcome {
    // what is wrong with the items is for `check`; the schema must be sound
    if (!ws.items_read) return ws.problems();

    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return .{
        .text = try arena.print("skein: there is no profile '{s}'\n", .{name}),
        .status = .misuse,
    } else null;
    // results that cannot be read are the command's to report
    const before = ws.report.problems.items.len;
    const ctx = try context.build(io, arena, ws, .{ .profile = profile, .results = options.results, .offline = options.common.offline });
    if (ws.report.problems.items.len > before) return ws.problems();

    var out = Io.Dir.cwd().createDirPathOpen(io, out_path, .{}) catch |e| return .{
        .text = try arena.print("skein: cannot make the directory '{s}' ({s})\n", .{ out_path, @errorName(e) }),
        .status = .misuse,
    };
    defer out.close(io);

    if (options.format == .document) {
        const written = try site.documents(io, arena, ws, ctx, out, options.controlled);
        return .{ .text = try arena.print("skein: {d} document{s} rendered to {s}\n", .{ written, if (written == 1) "" else "s", out_path }) };
    }
    if (options.format == .html) {
        const pages = try site.build(io, arena, ws, ctx, out);
        return .{ .text = try arena.print("skein: {d} page{s} rendered to {s}\n", .{ pages, if (pages == 1) "" else "s", out_path }) };
    }

    var count: usize = 0;
    for (ws.project.sources) |source| {
        // a source that cannot be read was reported when the items were
        const listed = files.list(io, arena, ws.root, source.path, &.{".md"}) catch continue;
        const paths = if (source.order_by) |attribute| try order.sortFiles(arena, &ws.graph, listed, attribute) else listed;
        for (paths) |file| {
            if (source.kind == .items and !markdown.fileIncluded(ctx, file)) continue;
            const text = ws.root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch continue;
            const rendered = switch (source.kind) {
                .documents => try markdown.document(ctx, file, text),
                .items => try markdown.itemFile(ctx, file, text),
            };
            if (std.Io.Dir.path.dirnamePosix(file)) |parent| try out.createDirPath(io, parent);
            try out.writeFile(io, .{ .sub_path = file, .data = rendered });
            count += 1;
        }
    }
    return .{
        .text = try arena.print("skein: {d} file{s} rendered to {s}\n", .{ count, if (count == 1) "" else "s", out_path }),
    };
}

/// Each baseline, rendered from its snapshot under `editions/NAME/`, and
/// the page that lists them; results are of the files now, so an edition
/// has none
fn editions(io: Io, arena: std.mem.Allocator, ws: *Workspace, options: cli.Render, current: []const u8) !Workspace.Outcome {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(arena, current);
    const list = try history.baselines(io, arena, ws.root);
    var rendered: std.ArrayList(history.Baseline) = .empty;
    for (list) |b| {
        var snap = history.snapshot(io, arena, ws.root, b.name) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try text.print(arena, "skein: edition {s}: could not take it out of git ({t})\n", .{ b.name, e });
                continue;
            },
        };
        defer snap.deinit();
        var old = switch (try Workspace.open(io, arena, .{ .root = snap.path, .offline = true })) {
            .ok => |w| w,
            .failed => |outcome| {
                try text.print(arena, "skein: edition {s} cannot be rendered:\n{s}", .{ b.name, outcome.text });
                continue;
            },
        };
        defer old.close();
        var o = options;
        o.results = .{};
        const sub = try Io.Dir.path.join(arena, &.{ options.out, "editions", b.name });
        const r = try renderInto(io, arena, &old, o, sub);
        if (r.status != .ok) {
            try text.print(arena, "skein: edition {s} cannot be rendered:\n{s}", .{ b.name, r.text });
            continue;
        }
        try text.appendSlice(arena, r.text);
        try rendered.append(arena, b);
    }
    const page = try indexPage(arena, ws.name(), options.format, rendered.items);
    const index_path = try Io.Dir.path.join(arena, &.{ options.out, "editions", if (options.format == .markdown) "index.md" else "index.html" });
    if (Io.Dir.path.dirname(index_path)) |parent| try Io.Dir.cwd().createDirPath(io, parent);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = index_path, .data = page });
    try text.print(arena, "skein: {d} edition{s} listed in {s}\n", .{ rendered.items.len, if (rendered.items.len == 1) "" else "s", index_path });
    return .{ .text = text.items };
}

/// The page that lists the editions, newest first, after the files as
/// they are now
fn indexPage(arena: std.mem.Allocator, project: []const u8, format: cli.Render.Format, list: []const history.Baseline) ![]const u8 {
    var buf: Io.Writer.Allocating = .init(arena);
    const w = &buf.writer;
    if (format == .markdown) {
        try w.print("# Editions of {s}\n\n- [Current](../): the files as they are now\n", .{project});
        var i = list.len;
        while (i > 0) : (i -= 1) try w.print("- [{s}]({s}/): baseline of {s}\n", .{ list[i - 1].name, list[i - 1].name, list[i - 1].date });
        return buf.written();
    }
    const entry = if (format == .html) "index.html" else "";
    try w.writeAll("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Editions of ");
    try xml.escape(w, project);
    try w.writeAll("</title>\n</head>\n<body>\n<h1>Editions of ");
    try xml.escape(w, project);
    try w.print("</h1>\n<ul>\n<li><a href=\"../{s}\">Current</a>: the files as they are now</li>\n", .{entry});
    var i = list.len;
    while (i > 0) : (i -= 1) {
        try w.writeAll("<li><a href=\"");
        try xml.escape(w, list[i - 1].name);
        try w.print("/{s}\">", .{entry});
        try xml.escape(w, list[i - 1].name);
        try w.print("</a>: baseline of {s}</li>\n", .{list[i - 1].date});
    }
    try w.writeAll("</ul>\n</body>\n</html>\n");
    return buf.written();
}

test {
    _ = @import("_test/render.zig");
}
