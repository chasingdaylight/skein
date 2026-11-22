//! `skein render`: the project's documents and item files as Markdown
//! for a site generator, written to a directory under their own paths,
//! or, with `--format html`, the static site itself (render/site.zig).

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Results = @import("../results/Results.zig");
const Workspace = @import("Workspace.zig");
const files = @import("../files.zig");
const markdown = @import("../render/markdown.zig");
const order = @import("../render/order.zig");
const site = @import("../render/site.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Render) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    // what is wrong with the items is for `check`; the schema must be sound
    if (!ws.items_read) return ws.problems();

    var item_sources: std.ArrayList([]const u8) = .empty;
    for (ws.project.sources) |source| {
        if (source.kind == .items) try item_sources.append(arena, source.path);
    }
    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return .{
        .text = try arena.print("skein: there is no profile '{s}'\n", .{name}),
        .status = .misuse,
    } else null;
    // results that cannot be read are the command's to report
    const before = ws.report.problems.items.len;
    const results = try Results.load(io, arena, ws.root, &ws.project, &ws.graph, options.results, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const idx = try results.index(arena, &ws.graph, &ws.citations);
    const ctx: markdown.Context = .{
        .arena = arena,
        .graph = &ws.graph,
        .schema = &ws.project.schema,
        .item_sources = item_sources.items,
        .project = &ws.project,
        .citations = &ws.citations,
        .profile = profile,
        .results = if (results.all.len > 0) .{ .results = &results, .index = &idx } else null,
    };

    var out = Io.Dir.cwd().createDirPathOpen(io, options.out, .{}) catch |e| return .{
        .text = try arena.print("skein: cannot make the directory '{s}' ({s})\n", .{ options.out, @errorName(e) }),
        .status = .misuse,
    };
    defer out.close(io);

    if (options.format == .document) {
        const written = try site.documents(io, arena, &ws, ctx, out);
        return .{ .text = try arena.print("skein: {d} document{s} rendered to {s}\n", .{ written, if (written == 1) "" else "s", options.out }) };
    }
    if (options.format == .html) {
        const pages = try site.build(io, arena, &ws, ctx, out);
        return .{ .text = try arena.print("skein: {d} page{s} rendered to {s}\n", .{ pages, if (pages == 1) "" else "s", options.out }) };
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
        .text = try arena.print("skein: {d} file{s} rendered to {s}\n", .{ count, if (count == 1) "" else "s", options.out }),
    };
}

test {
    _ = @import("_test/render.zig");
}
