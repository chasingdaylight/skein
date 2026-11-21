//! skein's TOML reader (TOML 1.1), for the files in `.skein/` and the
//! front matter of items. Its own code: skein takes no dependency for it.

const std = @import("std");

const Parser = @import("toml/Parser.zig");
const value = @import("toml/value.zig");

pub const Array = value.Array;
pub const Date = value.Date;
pub const Datetime = value.Datetime;
pub const Table = value.Table;
pub const Time = value.Time;
pub const Value = value.Value;

pub const Diagnostic = Parser.Diagnostic;
pub const Error = Parser.Error;

/// The root table of the document `source`. Everything returned is
/// allocated in `arena` or points into `source`, which must outlive it.
/// On `error.InvalidToml`, `diag` says where and why.
pub fn parse(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) Error!*Table {
    var p: Parser = .{ .arena = arena, .src = source, .diag = diag };
    return p.parseDocument();
}

test {
    _ = @import("toml/_test/valid.zig");
    _ = @import("toml/_test/invalid.zig");
}
