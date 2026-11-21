//! TOML's four kinds of string. Each function starts at the opening quote
//! and leaves the parser after the closing one.

const std = @import("std");

const Parser = @import("Parser.zig");

/// `"..."`
pub fn basic(p: *Parser) Parser.Error![]const u8 {
    p.pos += 1;
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        const c = p.peek() orelse return p.fail("the string is not closed");
        switch (c) {
            '"' => {
                p.pos += 1;
                return out.items;
            },
            '\\' => try escape(p, &out),
            '\n', '\r' => return p.fail("the string is not closed before the end of the line"),
            else => {
                if (isControl(c)) return p.fail("a control character in a string must be written as an escape");
                try out.append(p.arena, c);
                p.pos += 1;
            },
        }
    }
}

/// `'...'`: no escapes
pub fn literal(p: *Parser) Parser.Error![]const u8 {
    p.pos += 1;
    const start = p.pos;
    while (true) {
        const c = p.peek() orelse return p.fail("the string is not closed");
        switch (c) {
            '\'' => {
                p.pos += 1;
                return p.src[start .. p.pos - 1];
            },
            '\n', '\r' => return p.fail("the string is not closed before the end of the line"),
            else => {
                if (isControl(c)) return p.fail("a control character cannot be in a literal string");
                p.pos += 1;
            },
        }
    }
}

/// `"""..."""`
pub fn multilineBasic(p: *Parser) Parser.Error![]const u8 {
    p.pos += 3;
    skipFirstNewline(p);
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        const c = p.peek() orelse return p.fail("the string is not closed");
        switch (c) {
            '"' => if (try quotes(p, '"', &out)) return out.items,
            '\\' => {
                if (endsLine(p)) {
                    // a backslash at the end of a line joins the next text to it
                    p.pos += 1;
                    while (p.peek()) |w| : (p.pos += 1) {
                        if (w != ' ' and w != '\t' and w != '\n' and w != '\r') break;
                    }
                } else try escape(p, &out);
            },
            else => try text(p, c, &out),
        }
    }
}

/// `'''...'''`: no escapes
pub fn multilineLiteral(p: *Parser) Parser.Error![]const u8 {
    p.pos += 3;
    skipFirstNewline(p);
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        const c = p.peek() orelse return p.fail("the string is not closed");
        switch (c) {
            '\'' => if (try quotes(p, '\'', &out)) return out.items,
            else => try text(p, c, &out),
        }
    }
}

/// A newline right after the opening quotes is not part of the string
fn skipFirstNewline(p: *Parser) void {
    if (p.startsWith("\r\n")) p.pos += 2 else if (p.peek() == '\n') p.pos += 1;
}

/// One character of a multi-line string that is no quote or backslash
fn text(p: *Parser, c: u8, out: *std.ArrayList(u8)) Parser.Error!void {
    switch (c) {
        '\n' => p.pos += 1,
        '\r' => {
            if (!p.startsWith("\r\n")) return p.fail("a carriage return must be followed by a line feed");
            p.pos += 2;
        },
        else => {
            if (isControl(c)) return p.fail("a control character cannot be in a string");
            try out.append(p.arena, c);
            p.pos += 1;
            return;
        },
    }
    // line endings are read as one line feed, however the file spells them
    try out.append(p.arena, '\n');
}

/// A run of quotes in a multi-line string. Three or more close it (true):
/// up to two before the closing three belong to the string.
fn quotes(p: *Parser, quote: u8, out: *std.ArrayList(u8)) Parser.Error!bool {
    var n: usize = 0;
    while (p.pos + n < p.src.len and p.src[p.pos + n] == quote) n += 1;
    if (n < 3) {
        try out.appendNTimes(p.arena, quote, n);
        p.pos += n;
        return false;
    }
    if (n > 5) return p.fail("too many quotes at the end of the string");
    try out.appendNTimes(p.arena, quote, n - 3);
    p.pos += n;
    return true;
}

/// Whether the backslash at the parser's place is the last thing on its
/// line but for spaces and tabs
fn endsLine(p: *Parser) bool {
    var at = p.pos + 1;
    while (at < p.src.len and (p.src[at] == ' ' or p.src[at] == '\t')) at += 1;
    return at < p.src.len and (p.src[at] == '\n' or p.src[at] == '\r');
}

fn escape(p: *Parser, out: *std.ArrayList(u8)) Parser.Error!void {
    p.pos += 1;
    const c = p.peek() orelse return p.fail("the string is not closed");
    p.pos += 1;
    const simple: ?u8 = switch (c) {
        'b' => 0x08,
        't' => '\t',
        'n' => '\n',
        'f' => 0x0c,
        'r' => '\r',
        'e' => 0x1b,
        '"' => '"',
        '\\' => '\\',
        else => null,
    };
    if (simple) |s| return out.append(p.arena, s);
    const digits: usize = switch (c) {
        'x' => 2,
        'u' => 4,
        'U' => 8,
        else => return p.failAt(p.pos - 1, "unknown escape in a string"),
    };
    if (p.pos + digits > p.src.len) return p.fail("the escape is cut short");
    const hex = p.src[p.pos..][0..digits];
    for (hex) |h| {
        if (!std.ascii.isHex(h)) return p.fail("the escape needs hexadecimal digits");
    }
    const code = std.fmt.parseInt(u21, hex, 16) catch return p.fail("the escape names no Unicode character");
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(code, &buf) catch return p.fail("the escape names no Unicode character");
    try out.appendSlice(p.arena, buf[0..len]);
    p.pos += digits;
}

fn isControl(c: u8) bool {
    return (c < 0x20 and c != '\t') or c == 0x7f;
}
