//! Turns a Doorstop document (a directory with `.doorstop.yml`) and its
//! items into what skein reads: item files with TOML front matter, and
//! an item type.
//!
//! What becomes of a Doorstop item:
//!
//! | Doorstop | skein |
//! | --- | --- |
//! | the file's name (`SRS-001`) | `id` |
//! | `active: false` | `status = "removed"` |
//! | `links` | `parent` links; one with a stamp is recorded as reviewed |
//! | `normative`, `derived`, `level`, `ref` | attributes of the same names |
//! | `references` | the attribute `references`: the paths, with commas |
//! | `category` | the category, when every active item has one |
//! | every other attribute | an attribute of the same name |
//! | `reviewed` | left out: skein's fingerprints are not Doorstop's |
//! | `header` and `text` (YAML items) | a heading and the text |

const std = @import("std");

const names = @import("../../schema/names.zig");
const write = @import("../../toml/write.zig");
const yaml = @import("yaml.zig");

pub const Error = error{
    /// the file is not what Doorstop writes
    NotDoorstop,
} || yaml.Error;

/// What `.doorstop.yml` says
pub const Document = struct {
    prefix: []const u8,
    digits: u8 = 3,
    separator: []const u8 = "",
    title: []const u8 = "",
    /// whether some items have a name in the place of their number
    names: bool = false,
    /// the attributes Doorstop counts as part of what an item says
    reviewed: []const []const u8 = &.{},

    /// The name of the item type the document becomes
    pub fn typeName(self: Document, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const lower = try std.ascii.allocLowerString(arena, self.prefix);
        for (lower) |*c| {
            if (!std.ascii.isLower(c.*) and !std.ascii.isDigit(c.*) and c.* != '-' and c.* != '_') c.* = '-';
        }
        return if (lower.len > 0 and std.ascii.isLower(lower[0])) lower else try arena.print("d{s}", .{lower});
    }
};

pub fn readDocument(arena: std.mem.Allocator, text: []const u8, line: *u32) Error!Document {
    const root = try yaml.parse(arena, text, line);
    const settings = root.get("settings") orelse return error.NotDoorstop;
    var out: Document = .{ .prefix = settings.string("prefix") orelse return error.NotDoorstop };
    if (settings.string("digits")) |d| out.digits = std.fmt.parseInt(u8, d, 10) catch return error.NotDoorstop;
    if (settings.string("sep")) |s| out.separator = s;
    if (root.get("attributes")) |attributes| {
        if (attributes.get("defaults")) |defaults| {
            if (defaults.get("doc")) |doc| out.title = doc.string("title") orelse "";
        }
        if (attributes.get("reviewed")) |reviewed| {
            if (reviewed == .list) {
                var list: std.ArrayList([]const u8) = .empty;
                for (reviewed.list) |r| {
                    if (r == .scalar) try list.append(arena, r.scalar);
                }
                out.reviewed = list.items;
            }
        }
    }
    return out;
}

pub const Link = struct {
    target: []const u8,
    /// Doorstop had recorded a review of it
    stamped: bool,
};

/// A Doorstop item, read
pub const Item = struct {
    id: []const u8,
    front: yaml.Value,
    /// the Markdown after the front matter, or made from `header` and `text`
    body: []const u8,
    active: bool = true,
    category: []const u8 = "",
    links: []const Link = &.{},
};

/// The fields skein has a place of its own for, or leaves out
const handled = [_][]const u8{ "active", "links", "reviewed", "text", "header", "category" };

/// Reads the item `id` from its file: Markdown with YAML front matter, or
/// all YAML (`is_yaml`)
pub fn readItem(arena: std.mem.Allocator, id: []const u8, source: []const u8, is_yaml: bool, line: *u32) Error!Item {
    var out: Item = .{ .id = id, .front = .empty, .body = "" };
    if (is_yaml) {
        out.front = try yaml.parse(arena, source, line);
        const header = out.front.string("header") orelse "";
        const text = out.front.string("text") orelse "";
        out.body = if (header.len > 0) try arena.print("# {s}\n\n{s}", .{ header, text }) else text;
    } else {
        const normalized = try std.mem.replaceOwned(u8, arena, source, "\r\n", "\n");
        if (!std.mem.startsWith(u8, normalized, "---\n")) return error.NotDoorstop;
        const end = std.mem.find(u8, normalized, "\n---\n") orelse return error.NotDoorstop;
        out.front = try yaml.parse(arena, normalized[4 .. end + 1], line);
        out.body = std.mem.trim(u8, normalized[end + 5 ..], "\n");
    }
    if (out.front != .map) return error.NotDoorstop;
    if (out.front.string("active")) |active| out.active = !std.mem.eql(u8, active, "false");
    out.category = out.front.string("category") orelse "";

    var links: std.ArrayList(Link) = .empty;
    if (out.front.get("links")) |list| {
        if (list == .list) for (list.list) |link| switch (link) {
            .scalar => |target| try links.append(arena, .{ .target = target, .stamped = false }),
            .map => |entries| for (entries) |e| {
                try links.append(arena, .{ .target = e.key, .stamped = e.value == .scalar and e.value.scalar.len > 0 });
            },
            .list => {},
        };
    }
    out.links = links.items;
    return out;
}

/// What an attribute is called in skein: its own name, unless skein
/// reads a key of that name itself or the name is not one skein allows
pub fn attributeName(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    const lower = try std.ascii.allocLowerString(arena, name);
    for (lower) |*c| {
        if (!std.ascii.isLower(c.*) and !std.ascii.isDigit(c.*) and c.* != '-' and c.* != '_') c.* = '-';
    }
    if (names.contains(&names.reserved, lower) or std.mem.eql(u8, lower, "parent") or !names.valid(lower)) {
        return arena.print("doorstop-{s}", .{lower});
    }
    return lower;
}

/// The attributes of `item` as skein takes them: name and value, in the
/// order Doorstop wrote them. Empty ones are left out, and so are
/// booleans at Doorstop's defaults.
pub fn attributesOf(arena: std.mem.Allocator, item: Item, use_category: bool) std.mem.Allocator.Error![]const [2][]const u8 {
    var out: std.ArrayList([2][]const u8) = .empty;
    for (item.front.map) |e| {
        if (names.contains(&handled, e.key) and !(std.mem.eql(u8, e.key, "category") and !use_category)) continue;
        const value: []const u8 = switch (e.value) {
            .scalar => |s| s,
            .list => |list| blk: {
                // `references`: the paths; any other list: its scalars
                var parts: std.ArrayList([]const u8) = .empty;
                for (list) |v| switch (v) {
                    .scalar => |s| try parts.append(arena, s),
                    .map => if (v.string("path")) |path| try parts.append(arena, path),
                    .list => {},
                };
                break :blk try std.mem.join(arena, ", ", parts.items);
            },
            .map => continue,
        };
        if (value.len == 0) continue;
        if (std.mem.eql(u8, e.key, "normative") and std.mem.eql(u8, value, "true")) continue;
        if (std.mem.eql(u8, e.key, "derived") and std.mem.eql(u8, value, "false")) continue;
        try out.append(arena, .{ try attributeName(arena, e.key), value });
    }
    return out.items;
}

/// The item as a skein item file. `use_category`: whether the document's
/// categories become skein's.
pub fn render(arena: std.mem.Allocator, item: Item, use_category: bool) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "+++\nid = {s}\n", .{try write.string(arena, item.id)});
    if (!item.active) try out.appendSlice(arena, "status = \"removed\"\n");
    if (use_category and item.category.len > 0) try out.print(arena, "category = {s}\n", .{try write.string(arena, item.category)});
    if (item.links.len > 0) {
        var targets: std.ArrayList([]const u8) = .empty;
        for (item.links) |link| try targets.append(arena, link.target);
        try out.print(arena, "parent = {s}\n", .{try write.strings(arena, targets.items)});
    }
    for (try attributesOf(arena, item, use_category)) |attribute| {
        const boolean = std.mem.eql(u8, attribute[0], "normative") or std.mem.eql(u8, attribute[0], "derived");
        try out.print(arena, "{s} = {s}\n", .{ attribute[0], if (boolean) attribute[1] else try write.string(arena, attribute[1]) });
    }
    try out.appendSlice(arena, "+++\n\n");
    try out.appendSlice(arena, item.body);
    try out.append(arena, '\n');
    return out.items;
}

/// The item type for `document`, as the text of its file. `attributes`
/// are the names its items use; `categories` its categories, when used.
pub fn renderType(
    arena: std.mem.Allocator,
    document: Document,
    attributes: []const []const u8,
    categories: []const []const u8,
) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    if (document.title.len > 0) try out.print(arena, "description = {s}\n", .{try write.string(arena, document.title)});
    try out.print(arena, "id = \"numbered\"\nprefix = {s}\ndigits = {d}\n", .{ try write.string(arena, document.prefix), document.digits });
    if (!std.mem.eql(u8, document.separator, "-")) try out.print(arena, "separator = {s}\n", .{try write.string(arena, document.separator)});
    if (document.names) try out.appendSlice(arena, "names = true\n");
    if (categories.len > 0) try out.print(arena, "categories = {s}\n", .{try write.strings(arena, categories)});
    for (attributes) |name| {
        try out.print(arena, "\n[attributes.{s}]\n", .{name});
        if (std.mem.eql(u8, name, "normative") or std.mem.eql(u8, name, "derived")) try out.appendSlice(arena, "type = \"boolean\"\n");
        for (document.reviewed) |reviewed| {
            if (std.mem.eql(u8, try attributeName(arena, reviewed), name)) try out.appendSlice(arena, "normative = true\n");
        }
    }
    return out.items;
}

// req: import.doorstop.items, import.doorstop.type, import.doorstop.fields
const testing = std.testing;

test "a Markdown item becomes a skein item file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var line: u32 = 0;
    const item = try readItem(a, "SRS-001",
        \\---
        \\active: true
        \\category: functional
        \\derived: false
        \\level: 2.1.1
        \\links:
        \\- SYS-001: ItJnz4iOh-o61yl1qcExgZFnsE9aDaUKq3ZxblNJ4Zw=
        \\- SYS-002
        \\normative: true
        \\ref: ''
        \\references:
        \\- keyword: SRS-001
        \\  path: src/Problem.zig
        \\  type: file
        \\reviewed: 05pVFZeSMd2hhmfjFbySVtYUj8CHIj33lgH-udK-YQg=
        \\status: surface
        \\verification-method: Test
        \\rationale: |
        \\  Two lines of
        \\  "rationale".
        \\---
        \\
        \\# Problem form
        \\
        \\The solver **shall** solve it.
    , false, &line);
    try testing.expect(item.active);
    try testing.expect(item.links[0].stamped and !item.links[1].stamped);
    try testing.expectEqualStrings(
        \\+++
        \\id = "SRS-001"
        \\category = "functional"
        \\parent = ["SYS-001", "SYS-002"]
        \\level = "2.1.1"
        \\references = "src/Problem.zig"
        \\doorstop-status = "surface"
        \\verification-method = "Test"
        \\rationale = """
        \\Two lines of
        \\\"rationale\"."""
        \\+++
        \\
        \\# Problem form
        \\
        \\The solver **shall** solve it.
        \\
    , try render(a, item, true));
}

test "a YAML item: inactive, not normative, without a category" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var line: u32 = 0;
    const item = try readItem(a, "REQ002",
        \\active: false
        \\derived: true
        \\header: |
        \\  An overview
        \\level: 1.0
        \\links: []
        \\normative: false
        \\ref: OLD-7
        \\reviewed: null
        \\text: |
        \\  The text, on
        \\  two lines.
    , true, &line);
    try testing.expectEqualStrings(
        \\+++
        \\id = "REQ002"
        \\status = "removed"
        \\derived = true
        \\level = "1.0"
        \\normative = false
        \\ref = "OLD-7"
        \\+++
        \\
        \\# An overview
        \\
        \\The text, on
        \\two lines.
        \\
    , try render(a, item, false));
}

test "a document becomes an item type" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var line: u32 = 0;
    const document = try readDocument(a,
        \\settings:
        \\  digits: 3
        \\  prefix: SRS
        \\  sep: '-'
        \\  parent: SYS
        \\attributes:
        \\  defaults:
        \\    doc:
        \\      title: "Software Requirements"
        \\  reviewed:
        \\  - category
        \\  - verification-method
    , &line);
    try testing.expectEqualStrings("srs", try document.typeName(a));
    try testing.expectEqualStrings(
        \\description = "Software Requirements"
        \\id = "numbered"
        \\prefix = "SRS"
        \\digits = 3
        \\categories = ["functional", "performance"]
        \\
        \\[attributes.level]
        \\
        \\[attributes.normative]
        \\type = "boolean"
        \\
        \\[attributes.verification-method]
        \\normative = true
        \\
    , try renderType(a, document, &.{ "level", "normative", "verification-method" }, &.{ "functional", "performance" }));

    const bare = try readDocument(a, "settings:\n  prefix: REQ\n  digits: 4\n", &line);
    try testing.expectEqualStrings(
        \\id = "numbered"
        \\prefix = "REQ"
        \\digits = 4
        \\separator = ""
        \\
    , try renderType(a, bare, &.{}, &.{}));
    try testing.expectError(error.NotDoorstop, readDocument(a, "something: else\n", &line));
}

test {
    _ = yaml;
    _ = write;
}
