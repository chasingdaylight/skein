//! An item's fingerprint: a hash of what it says, which changes when its
//! meaning can have changed and not when it is only laid out differently.
//!
//! Fingerprints form a hash tree, as git's do for files and directories:
//! an item with parts is hashed over its own text and the fingerprints of
//! its parts. So a change to a part changes its whole, and the whole of
//! that, and nothing beside them.

const std = @import("std");

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const markdown = @import("../markdown.zig");
const Schema = @import("../schema/Schema.zig");

/// 128 bits of SHA-256, in hexadecimal
pub const Fingerprint = [32]u8;

/// The fingerprint of `item`: over its type, its category, the attributes
/// its type marks as normative, its own text as `normalize` gives it, and
/// the fingerprints of its parts, in order. Its status, its links, its ID
/// and the IDs of its parts are not part of it.
pub fn of(arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema, item: *const Item) std.mem.Allocator.Error!Fingerprint {
    var content: std.ArrayList(u8) = .empty;
    try content.print(arena, "type:{s}\ncategory:{s}\n", .{ item.type_name, item.category orelse "" });
    if (schema.itemType(item.type_name)) |item_type| {
        // in the order the type declares them, so the order written does not count
        for (item_type.attributes) |declared| {
            if (!declared.normative) continue;
            const value = item.attribute(declared.name) orelse continue;
            try content.print(arena, "attribute:{s}={s}\n", .{ declared.name, value });
        }
    }
    try content.appendSlice(arena, "text:\n");
    try content.appendSlice(arena, try normalize(arena, item.text));
    for (item.parts) |id| {
        const part = graph.find(id) orelse continue;
        try content.print(arena, "\npart:{s}", .{&try of(arena, graph, schema, part)});
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content.items, &digest, .{});
    return std.fmt.bytesToHex(digest[0..16].*, .lower);
}

/// `text` (Markdown) with its layout taken out: each block's runs of
/// spaces, tabs and line ends become one space, and blocks are separated
/// by one empty line. Code blocks keep their lines, which can matter, and
/// lose only the spaces at their ends.
pub fn normalize(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (try markdown.scan(arena, text)) |block| {
        if (out.items.len > 0) try out.appendSlice(arena, "\n\n");
        if (block.kind == .code) {
            var lines = std.mem.splitScalar(u8, block.text, '\n');
            var first = true;
            while (lines.next()) |line| {
                if (!first) try out.append(arena, '\n');
                first = false;
                try out.appendSlice(arena, std.mem.trimEnd(u8, line, " \t\r"));
            }
            continue;
        }
        var words = std.mem.tokenizeAny(u8, block.text, " \t\r\n");
        var first = true;
        while (words.next()) |word| {
            if (!first) try out.append(arena, ' ');
            first = false;
            try out.appendSlice(arena, word);
        }
    }
    return out.items;
}

// req: fingerprint.content, fingerprint.layout, fingerprint.parts, markdown.line-ends
const testing = std.testing;
const Report = @import("../Report.zig");

const test_schema: Schema = .{
    .types = &.{.{
        .name = "rule",
        .attributes = &.{ .{ .name = "stage", .normative = true }, .{ .name = "note" } },
    }},
};

/// The fingerprint of the first of `items`, which are a graph
fn firstOf(arena: std.mem.Allocator, items: []const Item) !Fingerprint {
    var report: Report = .{ .arena = arena };
    const graph = try Graph.init(arena, items, &report);
    return of(arena, &graph, &test_schema, &graph.items[0]);
}

fn rule(text: []const u8) Item {
    return .{ .id = "a", .type_name = "rule", .file = "x", .line = 1, .text = text };
}

test "layout does not change a fingerprint" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = try firstOf(a, &.{rule("The keywords are:\n\n- `as`\n- `fn`\n\n```text\nk = \"as\"\n  | \"fn\"\n```")});
    var other = rule("The   keywords\r\nare:\r\n\r\n\r\n-   `as`\r\n-   `fn`\r\n\r\n```text\r\nk = \"as\"  \r\n  | \"fn\"\r\n```");
    other.file = "y";
    other.line = 9;
    try testing.expectEqualStrings(&one, &try firstOf(a, &.{other}));
}

test "what an item says does change it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = rule("A comment starts with `//`.\n\n```text\n  indented\n```");
    const fp = try firstOf(a, &.{base});

    var changed = base;
    changed.text = "A comment starts with `#`.\n\n```text\n  indented\n```";
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{changed})));

    // the lines of a code block are part of what it says
    changed = base;
    changed.text = "A comment starts with `//`.\n\n```text\nindented\n```";
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{changed})));

    changed = base;
    changed.category = "syntax";
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{changed})));

    changed = base;
    changed.attributes = &.{.{ .name = "stage", .value = "s0" }};
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{changed})));
}

test "the status, the links, the ID and other attributes do not" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = rule("Text.");
    var changed = base;
    changed.id = "b";
    changed.status = "approved";
    changed.links = &.{.{ .type_name = "see", .target = "c" }};
    changed.attributes = &.{.{ .name = "note", .value = "not normative" }};
    try testing.expectEqualStrings(&try firstOf(a, &.{base}), &try firstOf(a, &.{changed}));
}

test "a whole's fingerprint is over its parts' fingerprints" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var whole = rule("The keywords are:");
    whole.parts = &.{ "p1", "p2" };
    var p1 = rule("`as`");
    p1.id = "p1";
    var p2 = rule("`fn`");
    p2.id = "p2";
    const fp = try firstOf(a, &.{ whole, p1, p2 });

    // a part says something else: its whole does too
    var p2_changed = p2;
    p2_changed.text = "`func`";
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{ whole, p1, p2_changed })));
    // and the part itself, but not its sibling
    try testing.expect(!std.mem.eql(u8, &try firstOf(a, &.{p2}), &try firstOf(a, &.{p2_changed})));

    // a part's category is part of what the whole says, through the part
    p2_changed = p2;
    p2_changed.category = "syntax";
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{ whole, p1, p2_changed })));

    // a part more or fewer, or in another order
    var fewer = whole;
    fewer.parts = &.{"p1"};
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{ fewer, p1, p2 })));
    var swapped = whole;
    swapped.parts = &.{ "p2", "p1" };
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{ swapped, p1, p2 })));

    // a part renamed, or with another status, says the same
    var renamed = whole;
    renamed.parts = &.{ "p1", "other" };
    var p2_renamed = p2;
    p2_renamed.id = "other";
    p2_renamed.status = "final";
    try testing.expectEqualStrings(&fp, &try firstOf(a, &.{ renamed, p1, p2_renamed }));

    // the same words as one item without parts are not the same item
    try testing.expect(!std.mem.eql(u8, &fp, &try firstOf(a, &.{rule("The keywords are:\n\n`as`\n\n`fn`")})));
}
