//! One kind of link, as `.skein/links/<name>.toml` declares it.

const Planning = @import("Planning.zig");
const Profile = @import("Profile.zig");
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
/// which of the `to` items it is expected of, when not all
expected_of: Profile.Expected = .{},
/// a link of this kind is reviewed: it records its target as last
/// reviewed, and is suspect when the target has changed since
review: bool = false,
/// an issue or pull request it points to must be open
open: bool = false,
/// a link of this kind counts as one of that type, for coverage: a waiver
/// that is as good as compliance
counts_as: ?[]const u8 = null,
/// a link of this kind excuses its target from the expectation of that
/// type: shown as waived, and counted neither as covered nor as not
excuses: ?[]const u8 = null,
/// what a link of this kind is to the schedule (`[planning] role`)
planning: ?Planning.LinkRole = null,

/// The link type that the table of `r` declares; problems go to its report.
pub fn read(r: Reader, name: []const u8) Reader.Error!LinkType {
    const expected = try Profile.readExpected(r);
    try r.known(&.{ "description", "from", "to", "required", "expected", "review", "open", "counts_as", "excuses", "planning" });
    return .{
        .planning = if (try r.child("planning")) |p| try Planning.readLink(p) else null,
        .name = name,
        .description = try r.string("description") orelse "",
        .from = try r.strings("from"),
        .to = try r.strings("to"),
        .required = try r.boolean("required", false),
        .expected = expected.on,
        .expected_of = expected,
        .review = try r.boolean("review", false),
        .open = try r.boolean("open", false),
        .counts_as = try r.string("counts_as"),
        .excuses = try r.string("excuses"),
    };
}
