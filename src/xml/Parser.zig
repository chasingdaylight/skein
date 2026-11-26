//! The XML parser: one pass over the source, building the element tree.
//! Well-formedness it needs to read the tree is checked (names, quotes,
//! matching end tags, entities); validity against a schema is not.

const std = @import("std");

const Element = @import("Element.zig");

const Parser = @This();

arena: std.mem.Allocator,
src: []const u8,
diag: *Diagnostic,
pos: usize = 0,
line: u32 = 1,
line_start: usize = 0,

pub const Error = error{InvalidXml} || std.mem.Allocator.Error;

pub const Diagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    message: []const u8 = "",
};

/// deeper elements are refused rather than risk the stack
const max_depth = 256;

pub fn document(p: *Parser) Error!*const Element {
    if (std.mem.startsWith(u8, p.src, "\xEF\xBB\xBF")) p.pos = 3;
    try p.misc(true);
    if (!p.at("<")) return p.fail("expected the root element");
    const root = try p.element(0);
    try p.misc(false);
    if (p.pos < p.src.len) return p.fail("text after the root element");
    return root;
}

/// Whitespace, comments and processing instructions, and before the root
/// a document type declaration
fn misc(p: *Parser, prolog: bool) Error!void {
    while (true) {
        _ = p.skipSpace();
        if (p.at("<?")) {
            try p.skipPast("?>", "a processing instruction that does not end");
        } else if (p.at("<!--")) {
            try p.skipPast("-->", "a comment that does not end");
        } else if (prolog and p.at("<!DOCTYPE")) {
            try p.doctype();
        } else return;
    }
}

fn doctype(p: *Parser) Error!void {
    var depth: usize = 0;
    while (p.pos < p.src.len) : (p.advance()) {
        switch (p.src[p.pos]) {
            '[' => depth += 1,
            ']' => depth -|= 1,
            '>' => if (depth == 0) {
                p.advance();
                return;
            },
            else => {},
        }
    }
    return p.fail("a document type declaration that does not end");
}

fn element(p: *Parser, depth: usize) Error!*const Element {
    if (depth >= max_depth) return p.fail("elements nested too deeply");
    const line = p.line;
    p.pos += 1; // <
    const name = try p.readName();
    var attributes: std.ArrayList(Element.Attribute) = .empty;
    while (true) {
        const spaced = p.skipSpace();
        if (p.at("/>")) {
            p.pos += 2;
            return p.make(name, attributes.items, &.{}, line);
        }
        if (p.at(">")) {
            p.pos += 1;
            break;
        }
        if (!spaced) return p.fail("expected a space, '>' or '/>' after a name");
        const attr = try p.readName();
        _ = p.skipSpace();
        if (!p.at("=")) return p.fail("expected '=' after an attribute's name");
        p.pos += 1;
        _ = p.skipSpace();
        try attributes.append(p.arena, .{ .name = attr, .value = try p.quoted() });
    }
    const content = try p.contentOf(name, depth);
    return p.make(name, attributes.items, content, line);
}

fn make(p: *Parser, name: []const u8, attributes: []const Element.Attribute, content: []const Element.Node, line: u32) Error!*const Element {
    const e = try p.arena.create(Element);
    e.* = .{ .name = name, .attributes = attributes, .content = content, .line = line };
    return e;
}

/// The content up to the end tag of `name`, which it consumes
fn contentOf(p: *Parser, name: []const u8, depth: usize) Error![]const Element.Node {
    var nodes: std.ArrayList(Element.Node) = .empty;
    var text: std.ArrayList(u8) = .empty;
    while (true) {
        if (p.pos >= p.src.len) return p.fail(try p.arena.print("'{s}' does not end", .{name}));
        if (p.at("</")) {
            const tag = p.pos;
            p.pos += 2;
            const end = try p.readName();
            if (!std.mem.eql(u8, end, name)) {
                p.pos = tag;
                return p.fail(try p.arena.print("'{s}' ends with '</{s}>'", .{ name, end }));
            }
            _ = p.skipSpace();
            if (!p.at(">")) return p.fail("expected '>' after the name of an end tag");
            p.pos += 1;
            break;
        } else if (p.at("<!--")) {
            try p.skipPast("-->", "a comment that does not end");
        } else if (p.at("<![CDATA[")) {
            p.pos += 9;
            const end = std.mem.findPos(u8, p.src, p.pos, "]]>") orelse return p.fail("a CDATA section that does not end");
            try text.appendSlice(p.arena, p.src[p.pos..end]);
            p.countLines(p.pos, end);
            p.pos = end + 3;
        } else if (p.at("<?")) {
            try p.skipPast("?>", "a processing instruction that does not end");
        } else if (p.at("<")) {
            try flush(p, &nodes, &text);
            try nodes.append(p.arena, .{ .element = try p.element(depth + 1) });
        } else if (p.at("&")) {
            try p.entity(&text);
        } else {
            try text.append(p.arena, p.src[p.pos]);
            p.advance();
        }
    }
    try flush(p, &nodes, &text);
    return nodes.items;
}

fn flush(p: *Parser, nodes: *std.ArrayList(Element.Node), text: *std.ArrayList(u8)) Error!void {
    if (text.items.len == 0) return;
    try nodes.append(p.arena, .{ .text = text.items });
    text.* = .empty;
}

fn quoted(p: *Parser) Error![]const u8 {
    if (p.pos >= p.src.len or (p.src[p.pos] != '"' and p.src[p.pos] != '\'')) return p.fail("expected a quoted value");
    const quote = p.src[p.pos];
    p.pos += 1;
    const start = p.pos;
    const end = std.mem.findScalarPos(u8, p.src, start, quote) orelse return p.fail("a value whose quote does not close");
    const raw = p.src[start..end];
    if (std.mem.findScalar(u8, raw, '<') != null) return p.fail("'<' in a value");
    if (std.mem.findScalar(u8, raw, '&') == null) {
        p.countLines(start, end);
        p.pos = end + 1;
        return raw;
    }
    var out: std.ArrayList(u8) = .empty;
    while (p.pos < end) {
        if (p.src[p.pos] == '&') try p.entity(&out) else {
            try out.append(p.arena, p.src[p.pos]);
            p.advance();
        }
    }
    p.pos = end + 1;
    return out.items;
}

fn entity(p: *Parser, out: *std.ArrayList(u8)) Error!void {
    const end = std.mem.findScalarPos(u8, p.src, p.pos, ';') orelse return p.fail("an entity without ';'");
    const ref = p.src[p.pos + 1 .. end];
    const named = [_]struct { []const u8, u8 }{ .{ "lt", '<' }, .{ "gt", '>' }, .{ "amp", '&' }, .{ "quot", '"' }, .{ "apos", '\'' } };
    for (named) |n| if (std.mem.eql(u8, ref, n[0])) {
        try out.append(p.arena, n[1]);
        p.pos = end + 1;
        return;
    };
    if (ref.len < 2 or ref[0] != '#') return p.fail(try p.arena.print("'&{s};' is not an entity skein knows", .{ref}));
    const code = (if (ref[1] == 'x') std.fmt.parseInt(u21, ref[2..], 16) else std.fmt.parseInt(u21, ref[1..], 10)) catch
        return p.fail(try p.arena.print("'&{s};' is not a character", .{ref}));
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(code, &buf) catch return p.fail(try p.arena.print("'&{s};' is not a character", .{ref}));
    try out.appendSlice(p.arena, buf[0..n]);
    p.pos = end + 1;
}

fn readName(p: *Parser) Error![]const u8 {
    const start = p.pos;
    while (p.pos < p.src.len) : (p.pos += 1) {
        const c = p.src[p.pos];
        const ok = std.ascii.isAlphanumeric(c) or c == '_' or c == ':' or c >= 0x80 or
            (p.pos > start and (c == '-' or c == '.'));
        if (!ok) break;
    }
    if (p.pos == start or std.ascii.isDigit(p.src[start])) return p.fail("expected a name");
    return p.src[start..p.pos];
}

fn at(p: *const Parser, s: []const u8) bool {
    return std.mem.startsWith(u8, p.src[p.pos..], s);
}

/// Whether there was any
fn skipSpace(p: *Parser) bool {
    const start = p.pos;
    while (p.pos < p.src.len and std.ascii.isWhitespace(p.src[p.pos])) p.advance();
    return p.pos > start;
}

fn skipPast(p: *Parser, end: []const u8, message: []const u8) Error!void {
    const i = std.mem.findPos(u8, p.src, p.pos, end) orelse return p.fail(message);
    p.countLines(p.pos, i);
    p.pos = i + end.len;
}

fn advance(p: *Parser) void {
    if (p.src[p.pos] == '\n') {
        p.line += 1;
        p.line_start = p.pos + 1;
    }
    p.pos += 1;
}

fn countLines(p: *Parser, from: usize, to: usize) void {
    for (p.src[from..to], from..) |c, i| if (c == '\n') {
        p.line += 1;
        p.line_start = i + 1;
    };
}

fn fail(p: *Parser, message: []const u8) error{InvalidXml} {
    p.diag.* = .{ .line = p.line, .column = @intCast(p.pos -| p.line_start + 1), .message = message };
    return error.InvalidXml;
}
