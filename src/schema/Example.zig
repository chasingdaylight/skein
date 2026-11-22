//! What makes an item type one of tested examples: `[example]` in its
//! file. Its items are code that the project's own test driver compiles
//! or runs, extracted by `skein examples`.

const std = @import("std");

const Reader = @import("Reader.zig");

const Example = @This();

/// the link type an example that is a part of an item counts as, to that
/// item: `shows`; null when it counts as none
link: ?[]const u8 = null,
/// the category of an example that must be rejected; any other must be
/// accepted
rejects: []const u8 = "rejects",
/// the file name extension of the examples of each language
extensions: []const Extension = &.{},

pub const Extension = struct { language: []const u8, extension: []const u8 };

pub fn read(r: Reader) Reader.Error!Example {
    try r.known(&.{ "link", "rejects", "extensions" });
    var out: Example = .{ .link = try r.string("link") };
    if (try r.string("rejects")) |c| out.rejects = c;
    if (try r.child("extensions")) |e| {
        var list: std.ArrayList(Extension) = .empty;
        for (e.table.keys()) |language| {
            const ext = try e.string(language) orelse continue;
            try list.append(r.arena, .{ .language = language, .extension = std.mem.trimStart(u8, ext, ".") });
        }
        out.extensions = list.items;
    }
    return out;
}

/// The extension of the files of `language`: the one declared, else the
/// language itself
pub fn extensionOf(self: *const Example, language: []const u8) []const u8 {
    for (self.extensions) |e| {
        if (std.mem.eql(u8, e.language, language)) return e.extension;
    }
    return if (language.len > 0) language else "txt";
}
