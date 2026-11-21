//! An item's fingerprint: a hash of what it says, which changes when its
//! meaning can have changed and not when it is only laid out differently.

const std = @import("std");

const Item = @import("Item.zig");
const markdown = @import("../markdown.zig");
const Schema = @import("../schema/Schema.zig");

/// 128 bits of SHA-256, in hexadecimal
pub const Fingerprint = [32]u8;

/// The fingerprint of `item`: over its type, its category, the attributes
/// its type marks as normative, and its text as `normalize` gives it.
/// Its status and its links are not part of it.
pub fn of(arena: std.mem.Allocator, item: *const Item, item_type: *const Schema.ItemType) std.mem.Allocator.Error!Fingerprint {
    var content: std.ArrayList(u8) = .empty;
    try content.print(arena, "type:{s}\ncategory:{s}\n", .{ item.type_name, item.category orelse "" });
    // in the order the type declares them, so the order written does not count
    for (item_type.attributes) |declared| {
        if (!declared.normative) continue;
        const value = item.attribute(declared.name) orelse continue;
        try content.print(arena, "attribute:{s}={s}\n", .{ declared.name, value });
    }
    try content.appendSlice(arena, "text:\n");
    try content.appendSlice(arena, try normalize(arena, item.text));

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
    for (try markdown.scan(arena, text, &.{})) |block| {
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

const testing = std.testing;

fn fingerprintOf(arena: std.mem.Allocator, item: Item) !Fingerprint {
    const item_type: Schema.ItemType = .{
        .name = "rule",
        .attributes = &.{ .{ .name = "stage", .normative = true }, .{ .name = "note" } },
    };
    return of(arena, &item, &item_type);
}

test "layout does not change a fingerprint" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = try fingerprintOf(a, .{ .id = "a", .type_name = "rule", .file = "x", .line = 1, .text = "The keywords are:\n\n- `as`\n- `fn`\n\n```text\nk = \"as\"\n  | \"fn\"\n```" });
    const two = try fingerprintOf(a, .{ .id = "a", .type_name = "rule", .file = "y", .line = 9, .text = "The   keywords\r\nare:\r\n\r\n\r\n-   `as`\r\n-   `fn`\r\n\r\n```text\r\nk = \"as\"  \r\n  | \"fn\"\r\n```" });
    try testing.expectEqualStrings(&one, &two);
}

test "what an item says does change it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base: Item = .{ .id = "a", .type_name = "rule", .file = "x", .line = 1, .text = "A comment starts with `//`.\n\n```text\n  indented\n```" };
    const fp = try fingerprintOf(a, base);

    var changed = base;
    changed.text = "A comment starts with `#`.\n\n```text\n  indented\n```";
    try testing.expect(!std.mem.eql(u8, &fp, &try fingerprintOf(a, changed)));

    // the lines of a code block are part of what it says
    changed = base;
    changed.text = "A comment starts with `//`.\n\n```text\nindented\n```";
    try testing.expect(!std.mem.eql(u8, &fp, &try fingerprintOf(a, changed)));

    changed = base;
    changed.category = "syntax";
    try testing.expect(!std.mem.eql(u8, &fp, &try fingerprintOf(a, changed)));

    changed = base;
    changed.attributes = &.{.{ .name = "stage", .value = "s0" }};
    try testing.expect(!std.mem.eql(u8, &fp, &try fingerprintOf(a, changed)));
}

test "the status, the links, the ID and other attributes do not" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base: Item = .{ .id = "a", .type_name = "rule", .file = "x", .line = 1, .text = "Text." };
    var changed = base;
    changed.id = "b";
    changed.status = "approved";
    changed.links = &.{.{ .type_name = "see", .target = "c" }};
    changed.attributes = &.{.{ .name = "note", .value = "not normative" }};
    try testing.expectEqualStrings(&try fingerprintOf(a, base), &try fingerprintOf(a, changed));
}
