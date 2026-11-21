//! The names a schema gives its types, links, profiles and attributes.

const std = @import("std");

pub const rule = "a name is lowercase letters, digits, '-' and '_', starting with a letter";

pub fn valid(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isLower(name[0])) return false;
    for (name) |c| {
        if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '-' and c != '_') return false;
    }
    return true;
}

pub fn contains(list: []const []const u8, name: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

test valid {
    try std.testing.expect(valid("rule"));
    try std.testing.expect(valid("derives-from"));
    try std.testing.expect(valid("s0_core"));
    try std.testing.expect(!valid(""));
    try std.testing.expect(!valid("Rule"));
    try std.testing.expect(!valid("0rule"));
    try std.testing.expect(!valid("a b"));
}
