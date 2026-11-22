//! The TOML document parser: tables, keys, arrays and inline tables.
//! Strings are in strings.zig, the other values in scalars.zig.

const std = @import("std");

const scalars = @import("scalars.zig");
const strings = @import("strings.zig");
const value = @import("value.zig");
const Array = value.Array;
const Table = value.Table;
const Value = value.Value;

const Parser = @This();

pub const Error = error{InvalidToml} || std.mem.Allocator.Error;

/// Where and why a document was refused
pub const Diagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    message: []const u8 = "",
};

arena: std.mem.Allocator,
src: []const u8,
pos: usize = 0,
diag: *Diagnostic,

pub fn parseDocument(self: *Parser) Error!*Table {
    if (!std.unicode.utf8ValidateSlice(self.src)) return self.failAt(0, "the file is not valid UTF-8");
    const root = try self.newTable(.root);
    var current = root;
    while (true) {
        try self.skipTrivia();
        if (self.eof()) return root;
        if (self.peek() == '[') {
            current = try self.parseHeader(root);
        } else {
            try self.parseKeyValue(current);
        }
        try self.endOfLine();
    }
}

// --------------------------------------------------------------------------
// Used by strings.zig and scalars.zig too

pub fn fail(self: *Parser, message: []const u8) error{InvalidToml} {
    return self.failAt(self.pos, message);
}

pub fn failAt(self: *Parser, at: usize, message: []const u8) error{InvalidToml} {
    const place = self.placeAt(at);
    self.diag.* = .{ .line = place.line, .column = place.column, .message = message };
    return error.InvalidToml;
}

/// The line and column of the offset `at`
fn placeAt(self: *const Parser, at: usize) value.Place {
    var line: u32 = 1;
    var column: u32 = 1;
    for (self.src[0..@min(at, self.src.len)]) |c| {
        if (c == '\n') {
            line += 1;
            column = 1;
        } else column += 1;
    }
    return .{ .line = line, .column = column };
}

pub fn eof(self: *const Parser) bool {
    return self.pos >= self.src.len;
}

pub fn peek(self: *const Parser) ?u8 {
    return if (self.pos < self.src.len) self.src[self.pos] else null;
}

pub fn startsWith(self: *const Parser, text: []const u8) bool {
    return std.mem.startsWith(u8, self.src[self.pos..], text);
}

// --------------------------------------------------------------------------
// White space, comments, line ends

fn skipSpaces(self: *Parser) void {
    while (self.peek()) |c| : (self.pos += 1) {
        if (c != ' ' and c != '\t') return;
    }
}

fn skipComment(self: *Parser) void {
    while (self.peek()) |c| : (self.pos += 1) {
        if (c == '\n' or c == '\r') return;
    }
}

/// Spaces, comments and line ends
fn skipTrivia(self: *Parser) Error!void {
    while (self.peek()) |c| switch (c) {
        ' ', '\t', '\n' => self.pos += 1,
        '\r' => {
            if (!self.startsWith("\r\n")) return self.fail("a carriage return must be followed by a line feed");
            self.pos += 2;
        },
        '#' => self.skipComment(),
        else => return,
    };
}

/// What may follow a key and value, or a table header, on its line
fn endOfLine(self: *Parser) Error!void {
    self.skipSpaces();
    if (self.peek() == '#') self.skipComment();
    if (self.eof() or self.peek() == '\n' or self.startsWith("\r\n")) return;
    return self.fail("expected the end of the line");
}

// --------------------------------------------------------------------------
// Keys

/// `a`, `a.b`, `"a b".c`: the parts
fn parseKey(self: *Parser) Error![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    while (true) {
        self.skipSpaces();
        try parts.append(self.arena, try self.parseKeyPart());
        self.skipSpaces();
        if (self.peek() != '.') return parts.items;
        self.pos += 1;
    }
}

fn parseKeyPart(self: *Parser) Error![]const u8 {
    const c = self.peek() orelse return self.fail("expected a key");
    if (c == '"') return strings.basic(self);
    if (c == '\'') return strings.literal(self);
    const start = self.pos;
    while (self.peek()) |k| : (self.pos += 1) {
        if (!std.ascii.isAlphanumeric(k) and k != '_' and k != '-') break;
    }
    if (self.pos == start) return self.fail("expected a key");
    return self.src[start..self.pos];
}

/// `key = value`, put into `table`
fn parseKeyValue(self: *Parser, table: *Table) Error!void {
    const start = self.pos;
    const key = try self.parseKey();
    if (self.peek() != '=') return self.fail("expected '=' after the key");
    self.pos += 1;
    self.skipSpaces();
    const v = try self.parseValue();

    var t = table;
    for (key[0 .. key.len - 1]) |part| {
        if (t.get(part)) |existing| switch (existing) {
            .table => |sub| {
                if (sub.kind != .dotted) return self.failAt(start, "the key adds to a table that is already defined");
                t = sub;
            },
            else => return self.failAt(start, "the key passes through a value that is not a table"),
        } else {
            const sub = try self.newTable(.dotted);
            sub.place = self.placeAt(start);
            try t.map.put(self.arena, part, .{ .table = sub });
            try t.places.put(self.arena, part, sub.place);
            t = sub;
        }
    }
    const last = key[key.len - 1];
    if (t.map.contains(last)) return self.failAt(start, "the key is defined twice");
    try t.map.put(self.arena, last, v);
    try t.places.put(self.arena, last, self.placeAt(start));
}

// --------------------------------------------------------------------------
// Table headers

/// `[a.b]` or `[[a.b]]`: the table that the lines after it fill
fn parseHeader(self: *Parser, root: *Table) Error!*Table {
    const start = self.pos;
    self.pos += 1;
    const is_array = self.peek() == '[';
    if (is_array) self.pos += 1;
    const key = try self.parseKey();
    if (self.peek() != ']') return self.fail("expected ']' after the table name");
    self.pos += 1;
    if (is_array) {
        if (self.peek() != ']') return self.fail("expected ']]' after the table name");
        self.pos += 1;
    }

    var t = root;
    for (key[0 .. key.len - 1]) |part| {
        if (t.get(part)) |existing| switch (existing) {
            .table => |sub| {
                if (sub.kind == .inline_table) return self.failAt(start, "an inline table cannot be added to");
                t = sub;
            },
            .array => |arr| {
                if (!arr.of_tables) return self.failAt(start, "the table name passes through a value that is not a table");
                t = arr.items.items[arr.items.items.len - 1].table;
            },
            else => return self.failAt(start, "the table name passes through a value that is not a table"),
        } else {
            const sub = try self.newTable(.implicit);
            try t.map.put(self.arena, part, .{ .table = sub });
            t = sub;
        }
    }

    const last = key[key.len - 1];
    if (is_array) {
        const arr = if (t.get(last)) |existing| switch (existing) {
            .array => |arr| if (arr.of_tables) arr else return self.failAt(start, "this name is already an array written in brackets"),
            else => return self.failAt(start, "this name is already defined and is not an array of tables"),
        } else blk: {
            const arr = try self.arena.create(Array);
            arr.* = .{ .of_tables = true };
            try t.map.put(self.arena, last, .{ .array = arr });
            break :blk arr;
        };
        const element = try self.newTable(.header);
        element.place = self.placeAt(start);
        try arr.items.append(self.arena, .{ .table = element });
        return element;
    }
    if (t.get(last)) |existing| switch (existing) {
        .table => |sub| {
            if (sub.kind != .implicit) return self.failAt(start, "the table is defined twice");
            sub.kind = .header;
            sub.place = self.placeAt(start);
            return sub;
        },
        else => return self.failAt(start, "this name is already defined and is not a table"),
    };
    const sub = try self.newTable(.header);
    sub.place = self.placeAt(start);
    try t.map.put(self.arena, last, .{ .table = sub });
    return sub;
}

// --------------------------------------------------------------------------
// Values

fn parseValue(self: *Parser) Error!Value {
    const c = self.peek() orelse return self.fail("expected a value");
    return switch (c) {
        '"' => .{ .string = if (self.startsWith("\"\"\"")) try strings.multilineBasic(self) else try strings.basic(self) },
        '\'' => .{ .string = if (self.startsWith("'''")) try strings.multilineLiteral(self) else try strings.literal(self) },
        '[' => self.parseArray(),
        '{' => self.parseInlineTable(),
        else => scalars.parse(self),
    };
}

/// `[ value, ... ]`, over any number of lines
fn parseArray(self: *Parser) Error!Value {
    self.pos += 1;
    const arr = try self.arena.create(Array);
    arr.* = .{};
    while (true) {
        try self.skipTrivia();
        const c = self.peek() orelse return self.fail("the array is not closed");
        if (c == ']') break;
        try arr.items.append(self.arena, try self.parseValue());
        try self.skipTrivia();
        const next = self.peek() orelse return self.fail("the array is not closed");
        if (next == ']') break;
        if (next != ',') return self.fail("expected ',' or ']' in the array");
        self.pos += 1;
    }
    self.pos += 1;
    return .{ .array = arr };
}

/// `{ key = value, ... }`, over any number of lines (TOML 1.1)
fn parseInlineTable(self: *Parser) Error!Value {
    self.pos += 1;
    const table = try self.newTable(.inline_table);
    while (true) {
        try self.skipTrivia();
        const c = self.peek() orelse return self.fail("the inline table is not closed");
        if (c == '}') break;
        try self.parseKeyValue(table);
        try self.skipTrivia();
        const next = self.peek() orelse return self.fail("the inline table is not closed");
        if (next == '}') break;
        if (next != ',') return self.fail("expected ',' or '}' in the inline table");
        self.pos += 1;
    }
    self.pos += 1;
    return .{ .table = table };
}

fn newTable(self: *Parser, kind: Table.Kind) Error!*Table {
    const t = try self.arena.create(Table);
    t.* = .{ .kind = kind };
    return t;
}
