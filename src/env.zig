//! The environment skein was started with, for the few things it reads
//! from it (a forge's token). Set once by `main`; empty in tests.

const std = @import("std");

pub var map: ?*const std.process.Environ.Map = null;

/// The value of the variable `name`; null when it is not set or empty
pub fn get(name: []const u8) ?[]const u8 {
    const m = map orelse return null;
    const v = m.get(name) orelse return null;
    return if (v.len > 0) v else null;
}
