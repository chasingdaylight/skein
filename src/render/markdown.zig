//! Rendering to Markdown, for a site generator: a source file with its
//! markers turned into anchors and visible IDs, and its references into
//! links. Everything else is kept byte for byte.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Marker = @import("../markdown/Marker.zig");
const Schema = @import("../schema/Schema.zig");

pub const Error = std.mem.Allocator.Error;

pub const Context = struct {
    arena: std.mem.Allocator,
    graph: *const Graph,
    schema: *const Schema,
    /// the directories of the sources that hold one item per file
    item_sources: []const []const u8 = &.{},
};

/// The document `file`, whose text is `source`, rendered.
pub fn document(ctx: Context, file: []const u8, source: []const u8) Error![]const u8 {
    var page: Page = .{ .ctx = ctx, .file = file };
    for (ctx.graph.items) |*item| {
        if (!std.mem.eql(u8, item.file, file)) continue;
        try page.markers.put(ctx.arena, item.line, item);
        try page.addReferences(item);
    }
    try page.addMentions();
    return page.render(source, 1);
}

/// The item file `file` rendered: its TOML front matter becomes the YAML
/// front matter that site generators read, with the ID as the title. A
/// file that is no item is returned as it is.
pub fn itemFile(ctx: Context, file: []const u8, source: []const u8) Error![]const u8 {
    const item = for (ctx.graph.items) |*item| {
        if (std.mem.eql(u8, item.file, file)) break item;
    } else return source;
    const body = afterFrontMatter(source) orelse return source;

    var page: Page = .{ .ctx = ctx, .file = file };
    try page.addReferences(item);
    var out: std.ArrayList(u8) = .empty;
    try out.print(ctx.arena, "---\ntitle: \"{s}\"\n---\n", .{item.id});
    if (try describe(ctx, item)) |words| try out.print(ctx.arena, "\n*{s}*\n", .{words});
    try out.appendSlice(ctx.arena, try page.render(body.text, body.line));
    return out.items;
}

/// What follows the front matter of `source`, and the line it starts at;
/// null when the file has no closed front matter
fn afterFrontMatter(source: []const u8) ?struct { text: []const u8, line: u32 } {
    var lines = std.mem.splitScalar(u8, source, '\n');
    const first = lines.next() orelse return null;
    if (!std.mem.eql(u8, std.mem.trimEnd(u8, first, " \t\r"), "+++")) return null;
    var line: u32 = 2;
    while (lines.next()) |l| : (line += 1) {
        if (std.mem.eql(u8, std.mem.trimEnd(u8, l, " \t\r"), "+++")) return .{ .text = lines.rest(), .line = line + 1 };
    }
    return null;
}

/// One file being rendered: where its markers and references are
const Page = struct {
    ctx: Context,
    file: []const u8,
    /// by line
    markers: std.AutoHashMapUnmanaged(u32, *const Item) = .empty,
    /// by line and column: the ID referred to
    references: std.AutoHashMapUnmanaged(Place, []const u8) = .empty,

    const Place = struct { line: u32, column: u32 };

    fn addReferences(self: *Page, item: *const Item) Error!void {
        for (item.references) |r| try self.references.put(self.ctx.arena, .{ .line = r.line, .column = r.column }, r.target);
    }

    fn addMentions(self: *Page) Error!void {
        for (self.ctx.graph.mentions) |m| {
            if (!std.mem.eql(u8, m.file, self.file)) continue;
            try self.references.put(self.ctx.arena, .{ .line = m.line, .column = m.column }, m.target);
        }
    }

    /// `text`, whose first line is the file's line `first_line`
    fn render(self: *const Page, text: []const u8, first_line: u32) Error![]const u8 {
        const a = self.ctx.arena;
        var out: std.ArrayList(u8) = .empty;
        var lines = std.mem.splitScalar(u8, text, '\n');
        var number = first_line;
        while (lines.next()) |line| : (number += 1) {
            if (number > first_line) try out.append(a, '\n');
            var at: usize = 0;
            if (self.markers.get(number)) |item| {
                if (markerStart(line)) |start| {
                    try out.appendSlice(a, line[0..start]);
                    try self.label(&out, item);
                    at = start + Marker.extent(line[start..]);
                }
            }
            while (at < line.len) {
                const found = if (line[at] == '%') self.references.get(.{ .line = number, .column = @intCast(at + 1) }) else null;
                const target = found orelse {
                    try out.append(a, line[at]);
                    at += 1;
                    continue;
                };
                const close = std.mem.findScalarPos(u8, line, at, ']') orelse line.len - 1;
                const inner = std.mem.trim(u8, line[at + 2 .. close], " ");
                const words = if (std.mem.findScalar(u8, inner, ' ')) |s| std.mem.trim(u8, inner[s + 1 ..], " ") else target;
                if (try self.href(target)) |link| {
                    try out.print(a, "[{s}]({s})", .{ words, link });
                } else try out.appendSlice(a, words);
                at = close + 1;
            }
        }
        return out.items;
    }

    /// The marker of `item`, as a reader sees it: an anchor, the ID linked
    /// to itself, and the category and status when the marker gives them
    fn label(self: *const Page, out: *std.ArrayList(u8), item: *const Item) Error!void {
        const a = self.ctx.arena;
        try out.print(a, "<a id=\"{s}\"></a>**[{s}](#{s})**", .{ item.id, item.id, item.id });
        if (try describe(self.ctx, item)) |words| try out.print(a, " *({s})*", .{words});
    }

    /// Where a link to the item `id` leads, from this file; null when
    /// there is no such item here to link to
    fn href(self: *const Page, id: []const u8) Error!?[]const u8 {
        const a = self.ctx.arena;
        const target = self.ctx.graph.find(id) orelse return null;
        const in_document = !isItemFile(self.ctx, target.file);
        // an item file that names itself has nowhere else to lead
        if (std.mem.eql(u8, target.file, self.file)) return if (in_document) try a.print("#{s}", .{id}) else null;
        const path = try relative(a, self.file, target.file);
        return if (in_document) try a.print("{s}#{s}", .{ path, id }) else path;
    }
};

/// The category and the status of `item`, as given: "syntax, final"
fn describe(ctx: Context, item: *const Item) Error!?[]const u8 {
    const category = item.category orelse return item.status;
    const status = item.status orelse return category;
    return try ctx.arena.print("{s}, {s}", .{ category, status });
}

fn isItemFile(ctx: Context, file: []const u8) bool {
    for (ctx.item_sources) |dir| {
        if (std.mem.eql(u8, dir, ".")) return true;
        if (file.len > dir.len and std.mem.startsWith(u8, file, dir) and file[dir.len] == '/') return true;
    }
    return false;
}

/// Where the marker of a line starts: after its indentation and the
/// bullets or numbers of the list entries it opens
fn markerStart(line: []const u8) ?usize {
    for (line, 0..) |c, i| {
        if (c == '%') return if (Marker.startsOne(line[i..])) i else null;
        if (std.mem.findScalar(u8, " \t-*+.)0123456789", c) == null) return null;
    }
    return null;
}

/// The path of the file `to` as written in the file `from`; both are
/// paths from the project's root, with forward slashes
fn relative(arena: std.mem.Allocator, from: []const u8, to: []const u8) Error![]const u8 {
    var here = std.mem.splitScalar(u8, std.Io.Dir.path.dirnamePosix(from) orelse "", '/');
    var there = std.mem.splitScalar(u8, to, '/');
    var rest = to;
    var out: std.ArrayList(u8) = .empty;
    var same = true;
    while (here.next()) |dir| {
        if (dir.len == 0) continue;
        if (same) {
            const before = there.index;
            const next = there.next();
            if (next != null and there.index != null and std.mem.eql(u8, next.?, dir)) {
                rest = there.rest();
                continue;
            }
            there.index = before;
            same = false;
        }
        try out.appendSlice(arena, "../");
    }
    try out.appendSlice(arena, rest);
    return out.items;
}

test {
    _ = @import("_test/markdown.zig");
}

test relative {
    const testing = std.testing;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("b.md", try relative(a, "a.md", "b.md"));
    try testing.expectEqualStrings("b.md", try relative(a, "spec/a.md", "spec/b.md"));
    try testing.expectEqualStrings("../terms/b.md", try relative(a, "spec/a.md", "terms/b.md"));
    try testing.expectEqualStrings("../../b.md", try relative(a, "spec/lex/a.md", "b.md"));
    try testing.expectEqualStrings("lex/b.md", try relative(a, "spec/a.md", "spec/lex/b.md"));
    try testing.expectEqualStrings("../b/spec/c.md", try relative(a, "spec/a/x.md", "spec/b/spec/c.md"));
}
