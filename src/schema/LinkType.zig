//! One kind of link, as `.skein/links/<name>.toml` declares it.

const Reader = @import("Reader.zig");

const LinkType = @This();

name: []const u8,
description: []const u8 = "",
/// the item types a link of this kind may start at; empty when any
from: []const []const u8 = &.{},
/// the item types it may point to; empty when any
to: []const []const u8 = &.{},
/// every item of a `from` type must have one: `check` reports the lack
required: bool = false,
/// every item of a `to` type should be pointed to by one: `coverage`
/// counts the ones that are not
expected: bool = false,
/// a link of this kind is reviewed: it records its target as last
/// reviewed, and is suspect when the target has changed since
review: bool = false,
/// an issue or pull request it points to must be open
open: bool = false,

/// The link type that the table of `r` declares; problems go to its report.
pub fn read(r: Reader, name: []const u8) Reader.Error!LinkType {
    try r.known(&.{ "description", "from", "to", "required", "expected", "review", "open" });
    return .{
        .name = name,
        .description = try r.string("description") orelse "",
        .from = try r.strings("from"),
        .to = try r.strings("to"),
        .required = try r.boolean("required", false),
        .expected = try r.boolean("expected", false),
        .review = try r.boolean("review", false),
        .open = try r.boolean("open", false),
    };
}
