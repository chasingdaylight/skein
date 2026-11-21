//! The items of a document: each marker line and the text after it.

const std = @import("std");

const Builder = @import("Builder.zig");
const Item = @import("Item.zig");
const markdown = @import("../markdown.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");

/// Adds to `out` the items that the document `source` (the file `file`)
/// declares. An item's text is the block after its marker, with the
/// lists, code blocks, tables and quotes that follow that block directly.
pub fn read(
    arena: std.mem.Allocator,
    schema: *const Schema,
    report: *Report,
    file: []const u8,
    source: []const u8,
    out: *std.ArrayList(Item),
) std.mem.Allocator.Error!void {
    var type_names: std.ArrayList([]const u8) = .empty;
    for (schema.types) |t| try type_names.append(arena, t.name);

    const blocks = try markdown.scan(arena, source, type_names.items);
    var i: usize = 0;
    while (i < blocks.len) : (i += 1) {
        const block = blocks[i];
        if (block.kind != .marker) continue;
        const marker = (try markdown.Marker.parse(arena, block.text, type_names.items)).?;
        const line = block.first_line;
        if (marker.problem) |problem| {
            try report.add(file, line, 1, "{s}: {s}", .{ marker.id, problem });
            continue;
        }
        var b: Builder = .{
            .arena = arena,
            .schema = schema,
            .report = report,
            .item = .{ .id = marker.id, .type_name = marker.type_name, .category = marker.category, .file = file, .line = line },
        };
        for (marker.fields) |f| try b.set(f.key, f.values, line);

        // a removed item is its marker alone
        const item_type = schema.itemType(marker.type_name).?;
        if (!b.item.isTombstone(item_type)) {
            const first = i + 1;
            if (first == blocks.len or !isText(blocks[first].kind)) {
                try report.add(file, line, 1, "{s}: the marker has no text after it", .{marker.id});
                continue;
            }
            var last = first;
            while (last + 1 < blocks.len and hangsOn(blocks[last + 1].kind)) last += 1;
            const start = @intFromPtr(blocks[first].text.ptr) - @intFromPtr(source.ptr);
            const end = @intFromPtr(blocks[last].text.ptr) - @intFromPtr(source.ptr) + blocks[last].text.len;
            try b.setText(source[start..end], blocks[first].first_line);
            i = last;
        }
        try out.append(arena, b.finish());
    }
}

/// Whether a block of this kind can be the first of an item's text
fn isText(kind: markdown.Block.Kind) bool {
    return switch (kind) {
        .paragraph, .list, .code, .quote, .table => true,
        .front_matter, .yaml_front_matter, .marker, .heading, .html, .thematic_break => false,
    };
}

/// Whether a block of this kind, after an item's text, is more of it
fn hangsOn(kind: markdown.Block.Kind) bool {
    return switch (kind) {
        .list, .code, .quote, .table => true,
        .front_matter, .yaml_front_matter, .marker, .heading, .html, .thematic_break, .paragraph => false,
    };
}
