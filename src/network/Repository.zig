//! Another repository whose items this project's items refer to
//! (`name:id`), as `.skein/config.toml` declares it under
//! `[[repositories]]`.

const std = @import("std");

const Schema = @import("../schema/Schema.zig");

const Repository = @This();

/// the short name this project gives it, before the colon
name: []const u8,
/// a checkout on disk, from the project's root, with forward slashes
path: ?[]const u8 = null,
/// an address git can fetch from
url: ?[]const u8 = null,
/// the branch or tag `--current` follows for a `url`; its default branch
/// when not given
ref: ?[]const u8 = null,

/// The repositories declared in `[[repositories]]` of `r`, the root table
/// of the configuration. Mistakes are reported, and those entries left out.
pub fn readAll(r: Schema.Reader) Schema.Reader.Error![]const Repository {
    var out: std.ArrayList(Repository) = .empty;
    for (try r.children("repositories")) |c| {
        try c.known(&.{ "name", "path", "url", "ref" });
        const name = try c.string("name") orelse "";
        const path = try c.string("path");
        const url = try c.string("url");
        if (!Schema.names.valid(name)) {
            try c.complain("name", "a repository needs a name: {s}", .{Schema.names.rule});
            continue;
        }
        for (out.items) |other| {
            if (std.mem.eql(u8, other.name, name)) {
                try c.complain("name", "'{s}' is the name of another repository too", .{name});
                break;
            }
        } else if ((path == null) == (url == null)) {
            try c.complain("", "a repository has a path (a checkout on disk) or a url, one of the two", .{});
        } else if (path != null and (std.Io.Dir.path.isAbsolute(path.?) or std.mem.findScalar(u8, path.?, '\\') != null)) {
            try c.complain("path", "a path is written from the project's root, with forward slashes", .{});
        } else {
            try out.append(r.arena, .{
                .name = name,
                .path = if (path) |p| std.mem.trimEnd(u8, p, "/") else null,
                .url = url,
                .ref = try c.string("ref"),
            });
        }
    }
    return out.items;
}
