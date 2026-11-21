//! TOML values written without quotes or brackets: booleans, numbers,
//! dates and times.

const std = @import("std");

const Parser = @import("Parser.zig");
const datetime = @import("datetime.zig");
const Value = @import("value.zig").Value;

/// The value at the parser's place; leaves the parser after it.
pub fn parse(p: *Parser) Parser.Error!Value {
    const start = p.pos;
    var end = start;
    while (end < p.src.len and isTokenChar(p.src[end])) end += 1;
    // a date and a time may be separated by one space
    if (end - start == 10 and datetime.startsWithDate(p.src[start..end]) and
        end + 3 < p.src.len and p.src[end] == ' ' and datetime.startsWithTime(p.src[end + 1 ..]))
    {
        end += 1;
        while (end < p.src.len and isTokenChar(p.src[end])) end += 1;
    }
    const tok = p.src[start..end];
    if (tok.len == 0) return p.fail("expected a value");
    const v = try classify(p, tok);
    p.pos = end;
    return v;
}

fn isTokenChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '+' or c == '-' or c == '_' or c == '.' or c == ':';
}

fn classify(p: *Parser, tok: []const u8) Parser.Error!Value {
    if (eql(tok, "true")) return .{ .boolean = true };
    if (eql(tok, "false")) return .{ .boolean = false };
    if (datetime.startsWithDate(tok) or datetime.startsWithTime(tok)) {
        const dt = datetime.parse(tok) orelse return p.fail("this is no valid date or time");
        return .{ .datetime = dt };
    }
    return number(p, tok);
}

fn number(p: *Parser, tok: []const u8) Parser.Error!Value {
    const signed = tok[0] == '+' or tok[0] == '-';
    const body = if (signed) tok[1..] else tok;
    if (eql(body, "inf")) return .{ .float = if (tok[0] == '-') -std.math.inf(f64) else std.math.inf(f64) };
    if (eql(body, "nan")) return .{ .float = std.math.nan(f64) };
    if (body.len == 0 or !std.ascii.isDigit(body[0])) return p.fail("expected a value");

    if (!signed and body.len > 2 and body[0] == '0') {
        const base: ?u8 = switch (body[1]) {
            'x' => 16,
            'o' => 8,
            'b' => 2,
            else => null,
        };
        if (base) |b| return radix(p, body[2..], b);
    }

    var is_float = false;
    for (body, 0..) |c, i| switch (c) {
        '0'...'9' => {},
        '_' => if (!betweenDigits(body, i)) return p.fail("an underscore in a number must be between digits"),
        '.' => {
            if (!betweenDigits(body, i)) return p.fail("a decimal point must be between digits");
            is_float = true;
        },
        'e', 'E', '+', '-' => is_float = true,
        else => return p.fail("this is no valid number"),
    };
    var whole: usize = 0;
    while (whole < body.len and (std.ascii.isDigit(body[whole]) or body[whole] == '_')) whole += 1;
    if (whole > 1 and body[0] == '0') return p.fail("a number cannot start with a zero");

    const clean = try strip(p, tok);
    if (is_float) {
        const f = std.fmt.parseFloat(f64, clean) catch return p.fail("this is no valid number");
        return .{ .float = f };
    }
    const n = std.fmt.parseInt(i64, clean, 10) catch return p.fail("the integer does not fit in 64 bits");
    return .{ .integer = n };
}

/// The digits after `0x`, `0o` or `0b`
fn radix(p: *Parser, digits: []const u8, base: u8) Parser.Error!Value {
    if (digits.len == 0) return p.fail("this is no valid number");
    for (digits, 0..) |c, i| {
        if (c == '_') {
            if (i == 0 or i + 1 == digits.len or digits[i - 1] == '_' or digits[i + 1] == '_')
                return p.fail("an underscore in a number must be between digits");
            continue;
        }
        const d = std.fmt.charToDigit(c, base) catch return p.fail("this is no valid number");
        _ = d;
    }
    const clean = try strip(p, digits);
    const n = std.fmt.parseInt(i64, clean, base) catch return p.fail("the integer does not fit in 64 bits");
    return .{ .integer = n };
}

fn betweenDigits(s: []const u8, i: usize) bool {
    return i > 0 and i + 1 < s.len and std.ascii.isDigit(s[i - 1]) and std.ascii.isDigit(s[i + 1]);
}

/// `s` without its underscores
fn strip(p: *Parser, s: []const u8) Parser.Error![]const u8 {
    if (std.mem.findScalar(u8, s, '_') == null) return s;
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (c != '_') try out.append(p.arena, c);
    }
    return out.items;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
