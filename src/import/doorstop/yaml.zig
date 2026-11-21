//! The YAML that Doorstop writes: block mappings and lists, plain and
//! quoted scalars (folded over lines), and block scalars. Not a YAML
//! parser: only what `.doorstop.yml` and Doorstop's items hold, for the
//! importer.

const std = @import("std");

pub const Error = error{UnsupportedYaml} || std.mem.Allocator.Error;

pub const Value = union(enum) {
    scalar: []const u8,
    list: []const Value,
    map: []const Entry,

    pub const empty: Value = .{ .scalar = "" };

    /// The value of `key`, when this is a mapping that has it
    pub fn get(self: Value, key: []const u8) ?Value {
        if (self != .map) return null;
        for (self.map) |e| {
            if (std.mem.eql(u8, e.key, key)) return e.value;
        }
        return null;
    }

    /// The scalar at `key`; null when there is none or it is not a scalar
    pub fn string(self: Value, key: []const u8) ?[]const u8 {
        const v = self.get(key) orelse return null;
        return if (v == .scalar) v.scalar else null;
    }
};

pub const Entry = struct { key: []const u8, value: Value };

/// The document `text`. On `error.UnsupportedYaml`, `line` is where.
pub fn parse(arena: std.mem.Allocator, text: []const u8, line: *u32) Error!Value {
    var p: Parser = .{ .arena = arena };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |l| try p.lines.append(arena, std.mem.trimEnd(u8, l, "\r"));
    errdefer line.* = @intCast(@min(p.i, p.lines.items.len) + 1);
    const v = try p.value(0);
    p.skipBlank();
    if (p.i < p.lines.items.len) return error.UnsupportedYaml;
    return v;
}

const Parser = struct {
    arena: std.mem.Allocator,
    lines: std.ArrayList([]const u8) = .empty,
    i: usize = 0,

    fn skipBlank(self: *Parser) void {
        while (self.i < self.lines.items.len) : (self.i += 1) {
            const t = std.mem.trim(u8, self.lines.items[self.i], " \t");
            if (t.len > 0 and t[0] != '#' and !std.mem.eql(u8, t, "---")) return;
        }
    }

    /// The line at the parser's place and its indentation; null at the end
    fn peek(self: *Parser) ?struct { indent: usize, text: []const u8 } {
        self.skipBlank();
        if (self.i >= self.lines.items.len) return null;
        const l = self.lines.items[self.i];
        const indent = l.len - std.mem.trimStart(u8, l, " ").len;
        return .{ .indent = indent, .text = l[indent..] };
    }

    /// The value that starts at the next line, when it is indented by
    /// `min` or more; an empty scalar otherwise
    fn value(self: *Parser, min: usize) Error!Value {
        const next = self.peek() orelse return .empty;
        if (next.indent < min) return .empty;
        return if (isListItem(next.text)) self.list(next.indent) else self.map(next.indent);
    }

    fn list(self: *Parser, indent: usize) Error!Value {
        var out: std.ArrayList(Value) = .empty;
        while (self.peek()) |next| {
            if (next.indent != indent or !isListItem(next.text)) break;
            const rest = std.mem.trimStart(u8, next.text[1..], " ");
            if (rest.len == 0) {
                self.i += 1;
                try out.append(self.arena, try self.value(indent + 1));
            } else if (keyEnd(rest) != null) {
                // a mapping that starts on the dash's line: read it as if
                // it started on a line of its own
                const at = next.text.len - rest.len;
                const shifted = try self.arena.alloc(u8, indent + at + rest.len);
                @memset(shifted[0 .. indent + at], ' ');
                @memcpy(shifted[indent + at ..], rest);
                self.lines.items[self.i] = shifted;
                try out.append(self.arena, try self.map(indent + at));
            } else {
                self.i += 1;
                try out.append(self.arena, .{ .scalar = try self.scalar(rest, indent) });
            }
        }
        return .{ .list = out.items };
    }

    fn map(self: *Parser, indent: usize) Error!Value {
        var out: std.ArrayList(Entry) = .empty;
        while (self.peek()) |next| {
            if (next.indent != indent or isListItem(next.text)) break;
            const end = keyEnd(next.text) orelse return error.UnsupportedYaml;
            const key = try unquote(self.arena, next.text[0..end]);
            const rest = std.mem.trim(u8, next.text[end + 1 ..], " \t");
            self.i += 1;
            const v: Value = if (rest.len == 0) blk: {
                // a list may sit at its key's own indentation
                const after = self.peek() orelse break :blk .empty;
                if (after.indent == indent and isListItem(after.text)) break :blk try self.list(indent);
                break :blk try self.value(indent + 1);
            } else if (rest[0] == '|' or rest[0] == '>')
                .{ .scalar = try self.block(indent, rest[0] == '>') }
            else if (std.mem.eql(u8, rest, "[]"))
                .{ .list = &.{} }
            else if (std.mem.eql(u8, rest, "{}"))
                .{ .map = &.{} }
            else
                .{ .scalar = try self.scalar(rest, indent) };
            try out.append(self.arena, .{ .key = key, .value = v });
        }
        return .{ .map = out.items };
    }

    /// A scalar that starts with `first` and goes on over the lines that
    /// are indented more than `indent`: YAML folds them into one line
    fn scalar(self: *Parser, first: []const u8, indent: usize) Error![]const u8 {
        var joined: std.ArrayList(u8) = .empty;
        try joined.appendSlice(self.arena, first);
        while (self.i < self.lines.items.len) : (self.i += 1) {
            const l = self.lines.items[self.i];
            const t = std.mem.trim(u8, l, " \t");
            if (t.len == 0) break;
            if (l.len - std.mem.trimStart(u8, l, " ").len <= indent) break;
            try joined.append(self.arena, ' ');
            try joined.appendSlice(self.arena, t);
        }
        return unquote(self.arena, joined.items);
    }

    /// A block scalar (`|` or `>`): the lines indented more than `indent`,
    /// without their common indentation and without the line ends after
    /// the last of them
    fn block(self: *Parser, indent: usize, folded: bool) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var strip: ?usize = null;
        while (self.i < self.lines.items.len) : (self.i += 1) {
            const l = self.lines.items[self.i];
            const blank = std.mem.trim(u8, l, " \t").len == 0;
            const line_indent = l.len - std.mem.trimStart(u8, l, " ").len;
            if (!blank and line_indent <= indent) break;
            if (strip == null and !blank) strip = line_indent;
            const content = if (blank) "" else l[@min(strip.?, line_indent)..];
            if (out.items.len > 0) try out.append(self.arena, if (folded and !blank) ' ' else '\n');
            try out.appendSlice(self.arena, content);
        }
        return std.mem.trimEnd(u8, out.items, "\n ");
    }
};

fn isListItem(text: []const u8) bool {
    return text.len > 0 and text[0] == '-' and (text.len == 1 or text[1] == ' ');
}

/// Where the colon that ends a mapping's key is in `text`; null when the
/// line is no `key: value`
fn keyEnd(text: []const u8) ?usize {
    var i: usize = 0;
    if (text.len > 0 and (text[0] == '\'' or text[0] == '"')) {
        i = (std.mem.findScalarPos(u8, text, 1, text[0]) orelse return null) + 1;
        return if (i < text.len and text[i] == ':' and (i + 1 == text.len or text[i + 1] == ' ')) i else null;
    }
    while (std.mem.findScalarPos(u8, text, i, ':')) |colon| : (i = colon + 1) {
        if (colon + 1 == text.len or text[colon + 1] == ' ') return colon;
    }
    return null;
}

/// A scalar without its quotes: `'it''s'`, `"a \"b\""`, or as it is
fn unquote(arena: std.mem.Allocator, text: []const u8) Error![]const u8 {
    const t = std.mem.trim(u8, text, " \t");
    if (t.len < 2 or (t[0] != '\'' and t[0] != '"') or t[t.len - 1] != t[0]) return t;
    const inner = t[1 .. t.len - 1];
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < inner.len) : (i += 1) {
        const c = inner[i];
        if (t[0] == '\'' and c == '\'' and i + 1 < inner.len and inner[i + 1] == '\'') {
            i += 1;
        } else if (t[0] == '"' and c == '\\' and i + 1 < inner.len) {
            i += 1;
            try out.append(arena, switch (inner[i]) {
                'n' => '\n',
                't' => '\t',
                else => inner[i],
            });
            continue;
        }
        try out.append(arena, c);
    }
    return out.items;
}

const testing = std.testing;

test "a Doorstop item's front matter" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var line: u32 = 0;
    const v = try parse(arena.allocator(),
        \\active: true
        \\category: functional
        \\level: 2.1.1
        \\links:
        \\- SYS-001: ItJnz4iOh-o61yl1qcExgZFnsE9aDaUKq3ZxblNJ4Zw=
        \\- SYS-002
        \\normative: true
        \\rationale: |
        \\  The form existing users already have models in;
        \\  matching it lets them port.
        \\
        \\  A second paragraph.
        \\ref: ''
        \\references:
        \\- keyword: SRS-001
        \\  path: src/Problem.zig
        \\  type: file
        \\- path: 'src/it''s.zig'
        \\  type: file
        \\reviewed: 05pVFZeSMd2hhmfjFbySVtYUj8CHIj33lgH-udK-YQg=
        \\text: The solver shall solve the problem, a sentence long enough that
        \\  Doorstop folds it over a second line.
        \\empty: []
    , &line);
    try testing.expectEqualStrings("true", v.string("active").?);
    try testing.expectEqualStrings("2.1.1", v.string("level").?);
    const links = v.get("links").?.list;
    try testing.expectEqual(2, links.len);
    try testing.expectEqualStrings("SYS-001", links[0].map[0].key);
    try testing.expectEqualStrings("ItJnz4iOh-o61yl1qcExgZFnsE9aDaUKq3ZxblNJ4Zw=", links[0].map[0].value.scalar);
    try testing.expectEqualStrings("SYS-002", links[1].scalar);
    try testing.expectEqualStrings("The form existing users already have models in;\nmatching it lets them port.\n\nA second paragraph.", v.string("rationale").?);
    try testing.expectEqualStrings("", v.string("ref").?);
    const references = v.get("references").?.list;
    try testing.expectEqualStrings("src/Problem.zig", references[0].string("path").?);
    try testing.expectEqualStrings("SRS-001", references[0].string("keyword").?);
    try testing.expectEqualStrings("src/it's.zig", references[1].string("path").?);
    try testing.expectEqualStrings("The solver shall solve the problem, a sentence long enough that Doorstop folds it over a second line.", v.string("text").?);
    try testing.expectEqual(0, v.get("empty").?.list.len);
}

test "a Doorstop document's settings" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var line: u32 = 0;
    const v = try parse(arena.allocator(),
        \\settings:
        \\  digits: 3
        \\  prefix: SRS
        \\  sep: '-'
        \\  parent: SYS
        \\attributes:
        \\  defaults:
        \\    doc:
        \\      title: "Software Requirements"
        \\    category: ''
        \\  reviewed:
        \\  - category
        \\  - verification-method
    , &line);
    const settings = v.get("settings").?;
    try testing.expectEqualStrings("3", settings.string("digits").?);
    try testing.expectEqualStrings("-", settings.string("sep").?);
    try testing.expectEqualStrings("Software Requirements", v.get("attributes").?.get("defaults").?.get("doc").?.string("title").?);
    try testing.expectEqualStrings("verification-method", v.get("attributes").?.get("reviewed").?.list[1].scalar);
}

test "what is not this YAML is refused with its line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var line: u32 = 0;
    try testing.expectError(error.UnsupportedYaml, parse(arena.allocator(), "key: value\njust a line\n", &line));
    try testing.expectEqual(2, line);
}
