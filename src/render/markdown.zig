//! Rendering to Markdown, for a site generator: a source file with its
//! markers turned into anchors and visible IDs, and its references into
//! links. Everything else is kept byte for byte.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Marker = @import("../markdown/Marker.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const coverage = @import("../graph/coverage.zig");
const generated = @import("generated.zig");
const markdown = @import("../markdown.zig");

pub const Error = std.mem.Allocator.Error;

pub const Context = struct {
    arena: std.mem.Allocator,
    graph: *const Graph,
    schema: *const Schema,
    /// the directories of the sources that hold one item per file
    item_sources: []const []const u8 = &.{},
    /// for the pages a document asks for (generated.zig); without them
    /// such a request is left as it is
    project: ?*const Project = null,
    citations: ?*const Graph.Citations = null,
    /// only the items of this profile are rendered; the others are left
    /// out, with their parts, and references to them are plain words
    profile: ?*const Schema.Profile = null,
};

/// The document `file`, whose text is `source`, rendered.
pub fn document(ctx: Context, file: []const u8, source: []const u8) Error![]const u8 {
    var page: Page = .{ .ctx = ctx, .file = file };
    for (ctx.graph.items) |*item| {
        if (!std.mem.eql(u8, item.file, file)) continue;
        if (!included(ctx, item)) {
            try page.left_out.append(ctx.arena, .{ .first = item.line, .last = @max(item.line, item.last_line) });
            continue;
        }
        try page.markers.put(ctx.arena, item.line, item);
        try page.addReferences(item);
    }
    try page.addMentions();
    try page.addGenerated(source);
    return page.render(source, 1);
}

/// Whether `item` is rendered: it is in the profile, when there is one,
/// and so is the item it is a part of
pub fn included(ctx: Context, item: *const Item) bool {
    const profile = ctx.profile orelse return true;
    const item_type = ctx.schema.itemType(item.type_name) orelse return false;
    if (!coverage.inProfile(profile, item, item_type)) return false;
    const whole = ctx.graph.find(item.parent orelse return true) orelse return true;
    return included(ctx, whole);
}

/// Whether the file `file` of a source of item files is rendered: it is
/// no item, or its item is rendered
pub fn fileIncluded(ctx: Context, file: []const u8) bool {
    for (ctx.graph.items) |*item| {
        if (std.mem.eql(u8, item.file, file)) return included(ctx, item);
    }
    return true;
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
    /// by the first line of the code block that asks for it: the
    /// generated page, and the block's last line
    generated: std.AutoHashMapUnmanaged(u32, Generated) = .empty,
    /// the lines of the items that are left out, and of their parts
    left_out: std.ArrayList(Lines) = .empty,

    const Generated = struct { last_line: u32, text: []const u8 };
    const Lines = struct { first: u32, last: u32 };

    fn isLeftOut(self: *const Page, line: u32) bool {
        for (self.left_out.items) |r| if (line >= r.first and line <= r.last) return true;
        return false;
    }

    const Place = struct { line: u32, column: u32 };

    fn addReferences(self: *Page, item: *const Item) Error!void {
        for (item.references) |r| try self.references.put(self.ctx.arena, .{ .line = r.line, .column = r.column }, r.target);
    }

    /// The code blocks of `source` that ask for a generated page, and the
    /// Markdown each stands for
    fn addGenerated(self: *Page, source: []const u8) Error!void {
        const project = self.ctx.project orelse return;
        const citations = self.ctx.citations orelse return;
        for (try markdown.scan(self.ctx.arena, source)) |b| {
            if (b.kind != .code) continue;
            const nl = std.mem.findScalar(u8, b.text, '\n') orelse continue;
            if (!generated.isRequest(b.text[0..nl])) continue;
            // the request is the lines between the fences
            const inner_end = std.mem.findScalarLast(u8, b.text, '\n') orelse continue;
            const request = if (inner_end > nl) b.text[nl + 1 .. inner_end] else "";
            const text = try generated.render(.{
                .arena = self.ctx.arena,
                .project = project,
                .graph = self.ctx.graph,
                .citations = citations,
                .href = hrefOf,
                .default_profile = self.ctx.profile,
                .href_ctx = self,
            }, request);
            try self.generated.put(self.ctx.arena, b.first_line, .{ .last_line = b.last_line, .text = std.mem.trimEnd(u8, text, "\n") });
        }
    }

    fn hrefOf(ctx: *const anyopaque, item: *const Item) Error![]const u8 {
        const self: *const Page = @ptrCast(@alignCast(ctx));
        return try self.href(item.id) orelse "";
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
        var skip_to: u32 = 0;
        while (lines.next()) |line| : (number += 1) {
            if (number <= skip_to or self.isLeftOut(number)) continue;
            if (number > first_line) try out.append(a, '\n');
            if (self.generated.get(number)) |g| {
                try out.appendSlice(a, g.text);
                skip_to = g.last_line;
                continue;
            }
            var at: usize = 0;
            if (self.markers.get(number)) |item| {
                if (Marker.startIn(line)) |start| {
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
        // an item that is left out has no page to link to
        if (!included(self.ctx, target)) return null;
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

pub fn isItemFile(ctx: Context, file: []const u8) bool {
    for (ctx.item_sources) |dir| {
        if (std.mem.eql(u8, dir, ".")) return true;
        if (file.len > dir.len and std.mem.startsWith(u8, file, dir) and file[dir.len] == '/') return true;
    }
    return false;
}

/// The path of the file `to` as written in the file `from`; both are
/// paths from the project's root, with forward slashes
pub fn relative(arena: std.mem.Allocator, from: []const u8, to: []const u8) Error![]const u8 {
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
