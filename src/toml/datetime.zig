//! TOML dates and times (RFC 3339, with the forms TOML adds).

const std = @import("std");

const value = @import("value.zig");
const Datetime = value.Datetime;
const Date = value.Date;
const Time = value.Time;

/// Whether `s` begins like a date: `YYYY-MM-DD`
pub fn startsWithDate(s: []const u8) bool {
    if (s.len < 10) return false;
    for (s[0..10], 0..) |c, i| {
        const want_dash = i == 4 or i == 7;
        if (want_dash != (c == '-')) return false;
        if (!want_dash and !std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// Whether `s` begins like a time: `HH:`
pub fn startsWithTime(s: []const u8) bool {
    return s.len >= 3 and std.ascii.isDigit(s[0]) and std.ascii.isDigit(s[1]) and s[2] == ':';
}

/// The date, time or both that all of `s` spells; null when it spells none.
pub fn parse(s: []const u8) ?Datetime {
    var rest = s;
    var out: Datetime = .{};
    if (startsWithDate(rest)) {
        out.date = parseDate(rest[0..10]) orelse return null;
        rest = rest[10..];
        if (rest.len == 0) return out;
        switch (rest[0]) {
            'T', 't', ' ' => rest = rest[1..],
            else => return null,
        }
    }
    out.time = parseTime(&rest) orelse return null;
    if (rest.len == 0) return out;
    // an offset needs a date to mean anything
    if (out.date == null) return null;
    out.offset_minutes = parseOffset(rest) orelse return null;
    return out;
}

fn parseDate(s: []const u8) ?Date {
    const year = number(s[0..4]) orelse return null;
    const month = number(s[5..7]) orelse return null;
    const day = number(s[8..10]) orelse return null;
    if (month < 1 or month > 12) return null;
    if (day < 1 or day > daysIn(month, year)) return null;
    return .{ .year = @intCast(year), .month = @intCast(month), .day = @intCast(day) };
}

fn daysIn(month: u32, year: u32) u32 {
    return switch (month) {
        4, 6, 9, 11 => 30,
        2 => if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) 29 else 28,
        else => 31,
    };
}

/// Takes `HH:MM[:SS[.fraction]]` off the front of `rest`
fn parseTime(rest: *[]const u8) ?Time {
    const s = rest.*;
    if (s.len < 5 or s[2] != ':') return null;
    const hour = number(s[0..2]) orelse return null;
    const minute = number(s[3..5]) orelse return null;
    if (hour > 23 or minute > 59) return null;
    var out: Time = .{ .hour = @intCast(hour), .minute = @intCast(minute) };
    var at: usize = 5;
    if (at < s.len and s[at] == ':') {
        if (s.len < at + 3) return null;
        const second = number(s[at + 1 .. at + 3]) orelse return null;
        // 60: a leap second
        if (second > 60) return null;
        out.second = @intCast(second);
        at += 3;
        if (at < s.len and s[at] == '.') {
            at += 1;
            const from = at;
            var nanos: u32 = 0;
            while (at < s.len and std.ascii.isDigit(s[at])) : (at += 1) {
                // digits past the ninth are dropped
                if (at - from < 9) nanos = nanos * 10 + (s[at] - '0');
            }
            if (at == from) return null;
            var digits = at - from;
            while (digits < 9) : (digits += 1) nanos *= 10;
            out.nanosecond = nanos;
        }
    }
    rest.* = s[at..];
    return out;
}

/// `Z`, or `+HH:MM` or `-HH:MM`, in minutes
fn parseOffset(s: []const u8) ?i16 {
    if (s.len == 1 and (s[0] == 'Z' or s[0] == 'z')) return 0;
    if (s.len != 6 or s[3] != ':') return null;
    if (s[0] != '+' and s[0] != '-') return null;
    const hour = number(s[1..3]) orelse return null;
    const minute = number(s[4..6]) orelse return null;
    if (hour > 23 or minute > 59) return null;
    const total: i16 = @intCast(hour * 60 + minute);
    return if (s[0] == '-') -total else total;
}

/// The value of a run of decimal digits; null when one is not a digit
fn number(s: []const u8) ?u32 {
    var n: u32 = 0;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return null;
        n = n * 10 + (c - '0');
    }
    return n;
}
