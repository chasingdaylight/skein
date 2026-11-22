//! The items of a document: each marker and the text that belongs to it.
//!
//! A marker stands at the start of a paragraph or of a list entry. The
//! item's text is the rest of that block, and the lists, code blocks,
//! tables and quotes that follow it directly. An entry of such a list
//! that has a marker of its own is a part of the item: an item itself,
//! whose text is its own and not its whole's.

const std = @import("std");

const Builder = @import("Builder.zig");
const Item = @import("Item.zig");
const markdown = @import("../markdown.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");

pub const Error = std.mem.Allocator.Error;

/// Adds to `out` the items that the document `source` (the file `file`)
/// declares, each whole before its parts.
pub fn read(
    arena: std.mem.Allocator,
    schema: *const Schema,
    report: *Report,
    file: []const u8,
    source: []const u8,
    out: *std.ArrayList(Item),
    mentions: *std.ArrayList(Mention),
) Error!void {
    var reader: Reader = .{ .arena = arena, .schema = schema, .report = report, .file = file, .out = out, .mentions = mentions };
    _ = try reader.region(.{ .text = source, .line = 1, .dedent = 0 }, null, true);
}

/// A reference to an item in narrative text: text that is no item's
pub const Mention = struct {
    target: []const u8,
    file: []const u8,
    line: u32,
    column: u32,
};

/// A stretch of Markdown read on its own: the file, or a list entry
const Region = struct {
    text: []const u8,
    /// the file's line of its first line
    line: u32,
    /// the columns taken off each of its lines
    dedent: u32,
};

const Reader = struct {
    arena: std.mem.Allocator,
    schema: *const Schema,
    report: *Report,
    file: []const u8,
    out: *std.ArrayList(Item),
    mentions: *std.ArrayList(Mention),

    /// Reads the items of `r`; those not inside another item of it become
    /// parts of `whole`, if there is one. Whether it held any item.
    fn region(self: *Reader, r: Region, whole: ?*Builder, narrative: bool) Error!bool {
        const blocks = try markdown.scan(self.arena, r.text);
        var held = false;
        var i: usize = 0;
        while (i < blocks.len) {
            switch (blocks[i].kind) {
                .marker => {
                    held = true;
                    i = try self.item(r, blocks, i, whole);
                },
                // a list that belongs to no item here: its entries may hold some
                .list => {
                    for (try markdown.list.entries(self.arena, blocks[i])) |entry| {
                        if (try self.region(entryRegion(r, entry), whole, narrative)) held = true;
                    }
                    i += 1;
                },
                else => {
                    if (narrative) try self.mention(r, blocks[i]);
                    i += 1;
                },
            }
        }
        return held;
    }

    /// Records the references in a narrative block
    fn mention(self: *Reader, r: Region, block: markdown.Block) Error!void {
        const first_col = columnsBefore(r.text, block.text);
        for (try markdown.references.find(self.arena, block.text)) |found| {
            const at = markdown.references.position(block.text, found.offset);
            try self.mentions.append(self.arena, .{
                .target = found.target,
                .file = self.file,
                .line = r.line + block.first_line - 1 + at.line - 1,
                .column = at.column + r.dedent + (if (at.line == 1) first_col else 0),
            });
        }
    }

    /// Reads the item whose marker is `blocks[at]`; the index after what
    /// it took
    fn item(self: *Reader, r: Region, blocks: []const markdown.Block, at: usize, whole: ?*Builder) Error!usize {
        const line = r.line + blocks[at].first_line - 1;
        const column = r.dedent + 1;
        const marker = (try markdown.Marker.parse(self.arena, blocks[at].text)).?;
        if (marker.problem) |problem| {
            try self.report.add(self.file, line, column, "%{s}[{s}]: {s}", .{ marker.type_name, if (marker.id.len > 0) marker.id else "...", problem });
            return at + 1;
        }
        const item_type = self.schema.itemType(marker.type_name) orelse {
            try self.report.add(self.file, line, column, "{s}: there is no item type '{s}'", .{ marker.id, marker.type_name });
            return at + 1;
        };

        // a part's name: its whole's ID, and what follows the dot
        var id = marker.id;
        if (id[0] == '.') {
            const w = whole orelse {
                try self.report.add(self.file, line, column, "{s}: an ID that starts with a dot extends the ID of a containing item, and this item is not part of another item", .{id});
                return at + 1;
            };
            const whole_type = self.schema.itemType(w.item.type_name).?;
            if (item_type.id != .hierarchical or whole_type.id != .hierarchical) {
                try self.report.add(self.file, line, column, "{s}: an ID that starts with a dot needs hierarchical IDs for this item and for '{s}'", .{ id, w.item.id });
                return at + 1;
            }
            id = try self.arena.print("{s}{s}", .{ w.item.id, id });
        }

        var b: Builder = .{
            .arena = self.arena,
            .schema = self.schema,
            .report = self.report,
            .item = .{ .id = id, .type_name = marker.type_name, .file = self.file, .line = line, .parent = if (whole) |w| w.item.id else null },
        };
        for (marker.words) |word| {
            const is_category = Schema.names.contains(item_type.categories, word);
            const is_status = Schema.names.contains(item_type.statuses, word);
            if (is_category and b.item.category == null) {
                b.item.category = word;
            } else if (is_status and !is_category and b.item.status == null) {
                b.item.status = word;
            } else if (is_category or is_status) {
                try self.report.add(self.file, line, column, "{s}: '{s}' is one category or status too many", .{ id, word });
            } else {
                try self.report.add(self.file, line, column, "{s}: '{s}' is neither a category nor a status of a '{s}'", .{ id, word, item_type.name });
            }
        }
        for (marker.fields) |f| try b.set(f.key, f.values, line);

        // the whole stands before its parts
        const slot = self.out.items.len;
        try self.out.append(self.arena, undefined);
        var next = at + 1;

        // a removed item is its marker alone
        if (!b.item.isTombstone(item_type)) {
            if (next == blocks.len or !isText(blocks[next].kind)) {
                try self.report.add(self.file, line, column, "{s}: the marker has no text after it", .{id});
                _ = self.out.orderedRemove(slot);
                return next;
            }
            var first = true;
            while (next < blocks.len and (first or hangsOn(blocks[next].kind))) : (next += 1) {
                first = false;
                const block = blocks[next];
                if (block.kind == .list) {
                    try self.list(r, block, &b);
                } else try b.addText(block.text, .{
                    .line = r.line + block.first_line - 1,
                    .first_col = columnsBefore(r.text, block.text),
                    .dedent = r.dedent,
                });
            }
        }
        // the item ends where the last block it took ends
        const last = if (next > at + 1) blocks[next - 1].last_line else blocks[at].last_line;
        b.item.last_line = r.line + last - 1;
        const done = try b.finish();
        self.out.items[slot] = done;
        if (whole) |w| try w.addPart(done.id);
        return next;
    }

    /// A list in the text of the item `b`: the entries with markers are
    /// its parts, the others its own text
    fn list(self: *Reader, r: Region, block: markdown.Block, b: *Builder) Error!void {
        const entries = try markdown.list.entries(self.arena, block);
        var any = false;
        for (entries) |entry| {
            // what an entry with a marker leaves over is narrative; the others are the item's
            if (try self.region(entryRegion(r, entry), b, markdown.Marker.startsOne(entry.text))) any = true;
        }
        const place: Builder.Place = .{ .line = r.line + block.first_line - 1, .dedent = r.dedent };
        // the list as it stands, when all of it is the item's own
        if (!any) return b.addText(block.text, place);
        for (entries) |entry| {
            // an entry that only holds parts further in is still its own
            if (markdown.Marker.startsOne(entry.text)) continue;
            try b.addText(entry.raw, .{ .line = r.line + entry.first_line - 1, .dedent = r.dedent });
        }
    }
};

fn entryRegion(r: Region, entry: markdown.list.Entry) Region {
    return .{ .text = entry.text, .line = r.line + entry.first_line - 1, .dedent = r.dedent + entry.dedent };
}

/// How many columns of its line come before `piece`, a slice of `text`
fn columnsBefore(text: []const u8, piece: []const u8) u32 {
    const offset = @intFromPtr(piece.ptr) - @intFromPtr(text.ptr);
    const line_start = if (std.mem.findScalarLast(u8, text[0..offset], '\n')) |nl| nl + 1 else 0;
    return @intCast(offset - line_start);
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
