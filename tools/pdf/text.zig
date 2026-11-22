//! The text of a PDF's pages, in reading order as written: lines where
//! the text moves to a new line, spaces where it jumps along one, the
//! running headers and footers (artifacts of a tagged PDF) left out.

const std = @import("std");

const Document = @import("Document.zig");
const parse = @import("parse.zig");

const Value = parse.Value;
const Error = Document.Error;

/// A piece of text as one operator shows it, where it starts on its page
/// (in the page's units, y up), for reading tables by column
pub const Run = struct { page: usize, x: f64, y: f64, text: []const u8 };

/// The text of every page, a form feed between pages; with `runs`, each
/// piece of text with its position as well
pub fn all(doc: *const Document, runs: ?*std.ArrayList(Run)) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const catalog = findCatalog(doc) orelse return error.Malformed;
    const root = doc.resolve(catalog.get("Pages")) orelse return error.Malformed;
    var pages: std.ArrayList(Page) = .empty;
    try walk(doc, root, null, &pages, 0);
    for (pages.items, 0..) |p, i| {
        if (i > 0) try out.appendSlice(doc.arena, "\n\x0c\n");
        try page(doc, p, &out, .{ .list = runs, .page = i + 1 });
    }
    return out.items;
}

const Sink = struct { list: ?*std.ArrayList(Run), page: usize };

const Page = struct { node: Value, resources: ?Value };

fn findCatalog(doc: *const Document) ?Value {
    var it = doc.objects.valueIterator();
    while (it.next()) |v| {
        const t = v.get("Type") orelse continue;
        if (t == .name and std.mem.eql(u8, t.name, "Catalog")) return v.*;
    }
    return null;
}

fn walk(doc: *const Document, node: Value, inherited: ?Value, out: *std.ArrayList(Page), depth: usize) Error!void {
    if (depth > 64) return error.Malformed;
    const resources = doc.resolve(node.get("Resources")) orelse inherited;
    if (node.get("Kids")) |kids| {
        const list = doc.resolve(kids) orelse return;
        if (list != .array) return;
        for (list.array) |k| if (doc.resolve(k)) |child| try walk(doc, child, resources, out, depth + 1);
        return;
    }
    try out.append(doc.arena, .{ .node = node, .resources = resources });
}

/// How a font's codes become text, and how far each moves the pen
const Font = struct {
    /// bytes per code: 2 for the usual CID fonts (Identity-H)
    width: u8 = 1,
    map: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,
    /// advance of each code, in thousandths of the font size
    advances: std.AutoHashMapUnmanaged(u32, f64) = .empty,
    default_advance: f64 = 500,

    fn advance(self: Font, c: u32) f64 {
        return self.advances.get(c) orelse self.default_advance;
    }
};

/// Where the pen is, in the units of the page: enough of the text state
/// to tell a gap between words from letters set apart
const Pen = struct {
    /// the text matrix's scale and the start of the line
    scale: f64 = 1,
    line_x: f64 = 0,
    line_y: f64 = 0,
    x: f64 = 0,
    size: f64 = 10,
    leading: f64 = 0,
    /// where the last text shown ended, on which line
    end_x: ?f64 = null,
    end_y: f64 = 0,
};

fn page(doc: *const Document, p: Page, out: *std.ArrayList(u8), sink: Sink) Error!void {
    const a = doc.arena;
    var fonts: std.StringHashMapUnmanaged(Font) = .empty;
    if (p.resources) |r| if (doc.resolve(r.get("Font"))) |f| if (f == .dict) {
        for (f.dict) |e| try fonts.put(a, e.key, try fontOf(doc, doc.resolve(e.value) orelse continue));
    };

    // the content: one stream, or several read as one
    var content: std.ArrayList(u8) = .empty;
    if (doc.resolve(p.node.get("Contents"))) |c| switch (c) {
        .stream => try content.appendSlice(a, doc.decode(c) catch ""),
        .array => |list| for (list) |item| if (doc.resolve(item)) |s| {
            try content.appendSlice(a, doc.decode(s) catch "");
            try content.append(a, '\n');
        },
        else => {},
    };

    var parser: parse.Parser = .{ .arena = a, .src = content.items };
    var operands: std.ArrayList(Value) = .empty;
    var current: ?Font = null;
    var artifact: std.ArrayList(bool) = .empty;
    var pen: Pen = .{};
    while (!parser.done()) {
        const v = parser.value() catch {
            parser.at += 1;
            continue;
        };
        if (v != .operator) {
            try operands.append(a, v);
            continue;
        }
        defer operands.clearRetainingCapacity();
        const op = v.operator;
        const hidden = for (artifact.items) |h| {
            if (h) break true;
        } else false;
        if (eq(op, "BDC") or eq(op, "BMC")) {
            const tag = if (operands.items.len > 0 and operands.items[0] == .name) operands.items[0].name else "";
            try artifact.append(a, eq(tag, "Artifact"));
        } else if (eq(op, "EMC")) {
            _ = artifact.pop();
        } else if (eq(op, "Tf")) {
            if (operands.items.len >= 2 and operands.items[0] == .name) {
                current = fonts.get(operands.items[0].name);
                pen.size = num(operands.items[1]);
            }
        } else if (eq(op, "TL")) {
            if (operands.items.len >= 1) pen.leading = num(operands.items[0]);
        } else if (eq(op, "Td") or eq(op, "TD")) {
            if (operands.items.len < 2) continue;
            pen.line_x += num(operands.items[0]) * pen.scale;
            pen.line_y += num(operands.items[1]) * pen.scale;
            if (eq(op, "TD")) pen.leading = -num(operands.items[1]);
            pen.x = pen.line_x;
        } else if (eq(op, "Tm")) {
            if (operands.items.len < 6) continue;
            pen.scale = num(operands.items[3]);
            if (pen.scale == 0) pen.scale = 1;
            pen.line_x = num(operands.items[4]);
            pen.line_y = num(operands.items[5]);
            pen.x = pen.line_x;
        } else if (eq(op, "BT")) {
            pen.scale = 1;
            pen.line_x = 0;
            pen.line_y = 0;
            pen.x = 0;
        } else if (eq(op, "T*") or eq(op, "'") or eq(op, "\"")) {
            pen.line_y -= pen.leading * pen.scale;
            pen.x = pen.line_x;
            if (!eq(op, "T*") and !hidden and operands.items.len > 0) {
                const s = operands.items[operands.items.len - 1];
                if (s == .string) try show(a, out, current, s.string, &pen, sink);
            }
        } else if (eq(op, "Tj")) {
            if (hidden or operands.items.len == 0) continue;
            const s = operands.items[operands.items.len - 1];
            if (s == .string) try show(a, out, current, s.string, &pen, sink);
        } else if (eq(op, "TJ")) {
            if (hidden or operands.items.len == 0 or operands.items[0] != .array) continue;
            for (operands.items[0].array) |item| switch (item) {
                .string => |s| try show(a, out, current, s, &pen, sink),
                // a move along the line, in thousandths of the font size
                .number => |n| pen.x -= n / 1000 * pen.size * pen.scale,
                else => {},
            };
        }
    }
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn num(v: Value) f64 {
    return if (v == .number) v.number else 0;
}

fn newline(a: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
    if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(a, '\n');
}

fn space(a: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (out.items.len > 0 and out.items[out.items.len - 1] != ' ' and out.items[out.items.len - 1] != '\n') try out.append(a, ' ');
}

/// The text of the codes `s` in `font`, after a line break or a space
/// where the pen has moved to a new line or jumped along this one
fn show(a: std.mem.Allocator, out: *std.ArrayList(u8), font: ?Font, s: []const u8, pen: *Pen, sink: Sink) !void {
    const em = pen.size * pen.scale;
    // a run keeps the space put before it, so that runs join back into words
    const before = out.items.len;
    if (pen.end_x) |end| {
        if (@abs(pen.line_y - pen.end_y) > em * 0.5) {
            try newline(a, out);
        } else if (pen.x - end > em * 0.15 or pen.x < end - em * 2) try space(a, out);
    }
    const start_x = pen.x;
    const start = @min(before, out.items.len);
    defer if (sink.list) |list| if (out.items.len > start) {
        const piece = std.mem.trimStart(u8, out.items[start..], "\n");
        if (piece.len > 0) list.append(a, .{ .page = sink.page, .x = start_x, .y = pen.line_y, .text = a.dupe(u8, piece) catch "" }) catch {};
    };
    const f = font orelse {
        try out.appendSlice(a, s);
        return;
    };
    var i: usize = 0;
    while (i + f.width <= s.len) : (i += f.width) {
        const code: u32 = if (f.width == 2) (@as(u32, s[i]) << 8) | s[i + 1] else s[i];
        if (f.map.get(code)) |t| {
            try out.appendSlice(a, t);
        } else if (f.width == 1) {
            try out.appendSlice(a, winAnsi(@intCast(code)));
        }
        pen.x += f.advance(code) / 1000 * em;
    }
    pen.end_x = pen.x;
    pen.end_y = pen.line_y;
}

/// How far each code of a font moves the pen: `FirstChar` and `Widths` for
/// a simple font; `DW` and `W` of its descendant for a composite one
fn readWidths(doc: *const Document, f: Value, out: *Font) Error!void {
    const a = doc.arena;
    if (out.width == 2) {
        const descendants = doc.resolve(f.get("DescendantFonts")) orelse return;
        if (descendants != .array or descendants.array.len == 0) return;
        const cid = doc.resolve(descendants.array[0]) orelse return;
        out.default_advance = if (doc.resolve(cid.get("DW"))) |dw| num(dw) else 1000;
        const w = doc.resolve(cid.get("W")) orelse return;
        if (w != .array) return;
        var i: usize = 0;
        while (i < w.array.len) {
            const first: u32 = @intFromFloat(num(doc.resolve(w.array[i]) orelse break));
            const next = doc.resolve(if (i + 1 < w.array.len) w.array[i + 1] else break) orelse break;
            if (next == .array) {
                for (next.array, 0..) |adv, k| try out.advances.put(a, first + @as(u32, @intCast(k)), num(doc.resolve(adv) orelse continue));
                i += 2;
            } else {
                if (i + 2 >= w.array.len) break;
                const last: u32 = @intFromFloat(num(next));
                const adv = num(doc.resolve(w.array[i + 2]) orelse break);
                if (last >= first and last - first < 0x10000) for (first..last + 1) |c| try out.advances.put(a, @intCast(c), adv);
                i += 3;
            }
        }
        return;
    }
    const first: u32 = if (doc.resolve(f.get("FirstChar"))) |fc| @intFromFloat(num(fc)) else 0;
    const widths = doc.resolve(f.get("Widths")) orelse return;
    if (widths != .array) return;
    for (widths.array, 0..) |adv, k| try out.advances.put(a, first + @as(u32, @intCast(k)), num(doc.resolve(adv) orelse continue));
}

/// A font's codes: its ToUnicode map, else WinAnsi with its differences
fn fontOf(doc: *const Document, f: Value) Error!Font {
    var out: Font = .{};
    const subtype = f.get("Subtype");
    if (subtype != null and subtype.? == .name and eq(subtype.?.name, "Type0")) out.width = 2;
    try readWidths(doc, f, &out);
    if (doc.resolve(f.get("ToUnicode"))) |cmap| if (cmap == .stream) {
        try readCmap(doc.arena, doc.decode(cmap) catch "", &out);
        return out;
    };
    if (doc.resolve(f.get("Encoding"))) |enc| if (enc == .dict) {
        if (doc.resolve(enc.get("Differences"))) |d| if (d == .array) {
            var code: u32 = 0;
            for (d.array) |item| switch (item) {
                .number => |n| code = @intFromFloat(n),
                .name => |n| {
                    try out.map.put(doc.arena, code, glyph(n));
                    code += 1;
                },
                else => {},
            };
        };
    };
    return out;
}

/// The `bfchar` and `bfrange` mappings of a ToUnicode CMap
fn readCmap(a: std.mem.Allocator, data: []const u8, f: *Font) Error!void {
    var p: parse.Parser = .{ .arena = a, .src = data };
    var operands: std.ArrayList(Value) = .empty;
    var mode: enum { none, char, range, space } = .none;
    while (!p.done()) {
        const v = p.value() catch {
            p.at += 1;
            continue;
        };
        if (v != .operator) {
            try operands.append(a, v);
            continue;
        }
        const op = v.operator;
        if (eq(op, "beginbfchar")) mode = .char else if (eq(op, "beginbfrange")) mode = .range else if (eq(op, "begincodespacerange")) mode = .space else if (eq(op, "endbfchar") or eq(op, "endbfrange") or eq(op, "endcodespacerange")) {
            const items = operands.items;
            switch (mode) {
                .space => if (items.len >= 1 and items[0] == .string) {
                    f.width = @intCast(@max(1, @min(2, items[0].string.len)));
                },
                .char => {
                    var i: usize = 0;
                    while (i + 1 < items.len) : (i += 2) {
                        if (items[i] != .string or items[i + 1] != .string) continue;
                        try f.map.put(a, codeOf(items[i].string), try utf16(a, items[i + 1].string));
                    }
                },
                .range => {
                    var i: usize = 0;
                    while (i + 2 < items.len) : (i += 3) {
                        if (items[i] != .string or items[i + 1] != .string) continue;
                        const lo = codeOf(items[i].string);
                        const hi = codeOf(items[i + 1].string);
                        if (hi < lo or hi - lo > 0xffff) continue;
                        switch (items[i + 2]) {
                            .string => |dst| for (lo..hi + 1, 0..) |c, k| {
                                var bytes = try a.dupe(u8, dst);
                                if (bytes.len >= 2) bytes[bytes.len - 1] +%= @truncate(k);
                                try f.map.put(a, @intCast(c), try utf16(a, bytes));
                            },
                            .array => |list| for (list, 0..) |d, k| if (d == .string) {
                                try f.map.put(a, lo + @as(u32, @intCast(k)), try utf16(a, d.string));
                            },
                            else => {},
                        }
                    }
                },
                .none => {},
            }
            mode = .none;
        }
        operands.clearRetainingCapacity();
    }
}

fn codeOf(bytes: []const u8) u32 {
    var c: u32 = 0;
    for (bytes) |b| c = (c << 8) | b;
    return c;
}

/// UTF-16BE, as a ToUnicode map gives text, as UTF-8
fn utf16(a: std.mem.Allocator, be: []const u8) ![]const u8 {
    var units: std.ArrayList(u16) = .empty;
    var i: usize = 0;
    while (i + 1 < be.len) : (i += 2) try units.append(a, (@as(u16, be[i]) << 8) | be[i + 1]);
    return std.unicode.utf16LeToUtf8Alloc(a, units.items) catch "?";
}

/// Each byte, to slice one character out of
const ascii = blk: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*b, i| b.* = @intCast(i);
    break :blk t;
};

/// The characters of WinAnsiEncoding: ASCII, and those beyond it that occur
fn winAnsi(c: u8) []const u8 {
    return switch (c) {
        32...126 => ascii[c .. c + 1],
        0x91 => "\u{2018}",
        0x92 => "\u{2019}",
        0x93 => "\u{201C}",
        0x94 => "\u{201D}",
        0x95 => "\u{2022}",
        0x96 => "\u{2013}",
        0x97 => "\u{2014}",
        0xA0 => " ",
        0xA7 => "\u{00A7}",
        0xAE => "\u{00AE}",
        else => "",
    };
}

/// The text of a glyph name of the standard Latin set
fn glyph(name: []const u8) []const u8 {
    if (name.len == 1) return name;
    const table = [_]struct { []const u8, []const u8 }{
        .{ "space", " " },                .{ "period", "." },           .{ "comma", "," },
        .{ "hyphen", "-" },               .{ "colon", ":" },            .{ "semicolon", ";" },
        .{ "parenleft", "(" },            .{ "parenright", ")" },       .{ "slash", "/" },
        .{ "quoteright", "\u{2019}" },    .{ "quoteleft", "\u{2018}" }, .{ "quotedblleft", "\u{201C}" },
        .{ "quotedblright", "\u{201D}" }, .{ "endash", "\u{2013}" },    .{ "bullet", "\u{2022}" },
        .{ "zero", "0" },                 .{ "one", "1" },              .{ "two", "2" },
        .{ "three", "3" },                .{ "four", "4" },             .{ "five", "5" },
        .{ "six", "6" },                  .{ "seven", "7" },            .{ "eight", "8" },
        .{ "nine", "9" },
    };
    for (table) |t| if (eq(t[0], name)) return t[1];
    return "";
}
