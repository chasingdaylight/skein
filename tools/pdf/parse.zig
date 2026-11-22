//! The objects of a PDF file (ISO 32000-1, section 7.3): numbers,
//! strings, names, arrays, dictionaries, references and streams.

const std = @import("std");

pub const Ref = struct { num: u32, gen: u16 = 0 };

pub const Entry = struct { key: []const u8, value: Value };

pub const Stream = struct { dict: []const Entry, raw: []const u8 };

pub const Value = union(enum) {
    null,
    boolean: bool,
    number: f64,
    name: []const u8,
    /// as written, after escapes are undone: bytes, not text
    string: []const u8,
    array: []const Value,
    dict: []const Entry,
    ref: Ref,
    stream: Stream,
    /// an operator of a content stream (`Tj`, `BT`)
    operator: []const u8,

    pub fn get(self: Value, key: []const u8) ?Value {
        const entries = switch (self) {
            .dict => |d| d,
            .stream => |s| s.dict,
            else => return null,
        };
        for (entries) |e| if (std.mem.eql(u8, e.key, key)) return e.value;
        return null;
    }
};

pub const Error = std.mem.Allocator.Error || error{Malformed};

pub const Parser = struct {
    arena: std.mem.Allocator,
    src: []const u8,
    at: usize = 0,

    pub fn skipSpace(self: *Parser) void {
        while (self.at < self.src.len) {
            const c = self.src[self.at];
            if (c == '%') {
                while (self.at < self.src.len and self.src[self.at] != '\n' and self.src[self.at] != '\r') self.at += 1;
            } else if (isSpace(c)) self.at += 1 else break;
        }
    }

    pub fn done(self: *Parser) bool {
        self.skipSpace();
        return self.at >= self.src.len;
    }

    /// The next object; in a content stream, an operator is a value too
    pub fn value(self: *Parser) Error!Value {
        self.skipSpace();
        if (self.at >= self.src.len) return error.Malformed;
        const c = self.src[self.at];
        switch (c) {
            '/' => return .{ .name = try self.name() },
            '(' => return .{ .string = try self.literal() },
            '[' => {
                self.at += 1;
                var items: std.ArrayList(Value) = .empty;
                while (true) {
                    self.skipSpace();
                    if (self.at >= self.src.len) return error.Malformed;
                    if (self.src[self.at] == ']') break;
                    try items.append(self.arena, try self.value());
                }
                self.at += 1;
                return .{ .array = items.items };
            },
            '<' => {
                if (self.at + 1 < self.src.len and self.src[self.at + 1] == '<') return .{ .dict = try self.dict() };
                return .{ .string = try self.hex() };
            },
            '+', '-', '.', '0'...'9' => return self.numberOrRef(),
            else => {
                const start = self.at;
                while (self.at < self.src.len and !isSpace(self.src[self.at]) and !isDelimiter(self.src[self.at])) self.at += 1;
                if (self.at == start) {
                    self.at += 1;
                    return error.Malformed;
                }
                const word = self.src[start..self.at];
                if (std.mem.eql(u8, word, "true")) return .{ .boolean = true };
                if (std.mem.eql(u8, word, "false")) return .{ .boolean = false };
                if (std.mem.eql(u8, word, "null")) return .null;
                return .{ .operator = word };
            },
        }
    }

    fn dict(self: *Parser) Error![]const Entry {
        self.at += 2;
        var entries: std.ArrayList(Entry) = .empty;
        while (true) {
            self.skipSpace();
            if (self.at + 1 >= self.src.len) return error.Malformed;
            if (self.src[self.at] == '>' and self.src[self.at + 1] == '>') break;
            if (self.src[self.at] != '/') return error.Malformed;
            const key = try self.name();
            try entries.append(self.arena, .{ .key = key, .value = try self.value() });
        }
        self.at += 2;
        return entries.items;
    }

    fn name(self: *Parser) Error![]const u8 {
        self.at += 1;
        var out: std.ArrayList(u8) = .empty;
        while (self.at < self.src.len and !isSpace(self.src[self.at]) and !isDelimiter(self.src[self.at])) : (self.at += 1) {
            const c = self.src[self.at];
            if (c == '#' and self.at + 2 < self.src.len) {
                const byte = std.fmt.parseInt(u8, self.src[self.at + 1 .. self.at + 3], 16) catch {
                    try out.append(self.arena, c);
                    continue;
                };
                try out.append(self.arena, byte);
                self.at += 2;
            } else try out.append(self.arena, c);
        }
        return out.items;
    }

    fn literal(self: *Parser) Error![]const u8 {
        self.at += 1;
        var out: std.ArrayList(u8) = .empty;
        var depth: usize = 1;
        while (self.at < self.src.len) : (self.at += 1) {
            const c = self.src[self.at];
            switch (c) {
                '(' => depth += 1,
                ')' => {
                    depth -= 1;
                    if (depth == 0) {
                        self.at += 1;
                        return out.items;
                    }
                },
                '\\' => {
                    self.at += 1;
                    if (self.at >= self.src.len) break;
                    const e = self.src[self.at];
                    switch (e) {
                        'n' => try out.append(self.arena, '\n'),
                        'r' => try out.append(self.arena, '\r'),
                        't' => try out.append(self.arena, '\t'),
                        'b' => try out.append(self.arena, 8),
                        'f' => try out.append(self.arena, 12),
                        '\r', '\n' => {
                            if (e == '\r' and self.at + 1 < self.src.len and self.src[self.at + 1] == '\n') self.at += 1;
                        },
                        '0'...'7' => {
                            var v: u32 = 0;
                            var k: usize = 0;
                            while (k < 3 and self.at < self.src.len and self.src[self.at] >= '0' and self.src[self.at] <= '7') : (k += 1) {
                                v = v * 8 + (self.src[self.at] - '0');
                                self.at += 1;
                            }
                            self.at -= 1;
                            try out.append(self.arena, @truncate(v));
                        },
                        else => try out.append(self.arena, e),
                    }
                    continue;
                },
                else => {},
            }
            try out.append(self.arena, c);
        }
        return error.Malformed;
    }

    fn hex(self: *Parser) Error![]const u8 {
        self.at += 1;
        var out: std.ArrayList(u8) = .empty;
        var half: ?u8 = null;
        while (self.at < self.src.len and self.src[self.at] != '>') : (self.at += 1) {
            const d = std.fmt.charToDigit(self.src[self.at], 16) catch continue;
            if (half) |h| {
                try out.append(self.arena, h * 16 + d);
                half = null;
            } else half = d;
        }
        if (half) |h| try out.append(self.arena, h * 16);
        self.at += 1;
        return out.items;
    }

    /// A number, or `N G R`, a reference
    fn numberOrRef(self: *Parser) Error!Value {
        const first = self.number();
        const save = self.at;
        if (isInteger(first)) {
            self.skipSpace();
            if (self.at < self.src.len and std.ascii.isDigit(self.src[self.at])) {
                const second = self.number();
                self.skipSpace();
                if (isInteger(second) and self.at < self.src.len and self.src[self.at] == 'R' and (self.at + 1 == self.src.len or isSpace(self.src[self.at + 1]) or isDelimiter(self.src[self.at + 1]))) {
                    self.at += 1;
                    return .{ .ref = .{ .num = @intFromFloat(first), .gen = @intFromFloat(second) } };
                }
            }
        }
        self.at = save;
        return .{ .number = first };
    }

    fn number(self: *Parser) f64 {
        const start = self.at;
        while (self.at < self.src.len and (std.ascii.isDigit(self.src[self.at]) or self.src[self.at] == '.' or self.src[self.at] == '-' or self.src[self.at] == '+')) self.at += 1;
        return std.fmt.parseFloat(f64, self.src[start..self.at]) catch 0;
    }
};

fn isInteger(x: f64) bool {
    return x >= 0 and x == @floor(x) and x < 1e9;
}

pub fn isSpace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\r' or c == '\t' or c == 0 or c == 12;
}

pub fn isDelimiter(c: u8) bool {
    return switch (c) {
        '(', ')', '<', '>', '[', ']', '{', '}', '/', '%' => true,
        else => false,
    };
}

test Parser {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var p: Parser = .{ .arena = arena.allocator(), .src = "<< /Type /Page /Kids [3 0 R 4 0 R] /T (a\\(b\\)) /H <48 69> /N -1.5 >> BT" };
    const v = try p.value();
    try std.testing.expectEqualStrings("Page", v.get("Type").?.name);
    try std.testing.expectEqual(4, v.get("Kids").?.array[1].ref.num);
    try std.testing.expectEqualStrings("a(b)", v.get("T").?.string);
    try std.testing.expectEqualStrings("Hi", v.get("H").?.string);
    try std.testing.expectEqual(-1.5, v.get("N").?.number);
    try std.testing.expectEqualStrings("BT", (try p.value()).operator);
}
