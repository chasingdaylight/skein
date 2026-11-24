//! `file` URIs and the paths they name. Only local files (an empty
//! authority) have paths; on Windows `file:///c%3A/x/a.csm` is
//! `c:\x\a.csm`.
//!
//! From cesiumlang/vscode-cesium, server/uri.zig (MIT), commit 047aa50.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Style = enum { posix, windows };

/// The path of a `file` URI, or null for another scheme or a remote file
pub fn toPath(a: Allocator, uri: []const u8, style: Style) Allocator.Error!?[]u8 {
    const prefix = "file://";
    if (uri.len < prefix.len or !std.ascii.eqlIgnoreCase(uri[0..prefix.len], prefix)) return null;
    const rest = uri[prefix.len..];
    if (rest.len == 0 or rest[0] != '/') return null;
    var path = try decode(a, rest);
    if (style == .windows) {
        // "/c:/x" is "c:\x"
        if (path.len >= 3 and path[0] == '/' and std.ascii.isAlphabetic(path[1]) and path[2] == ':') {
            const drive = a.dupe(u8, path[1..]) catch |e| {
                a.free(path);
                return e;
            };
            a.free(path);
            path = drive;
        }
        std.mem.replaceScalar(u8, path, '/', '\\');
    }
    return path;
}

/// The `file` URI of an absolute path, as VS Code writes them
pub fn fromPath(a: Allocator, path: []const u8, style: Style) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, "file://");
    if (style == .windows and (path.len == 0 or (path[0] != '/' and path[0] != '\\'))) try out.append(a, '/');
    for (path, 0..) |c, i| {
        if (style == .windows and c == '\\') {
            try out.append(a, '/');
        } else if (style == .windows and i == 0 and std.ascii.isAlphabetic(c) and path.len > 1 and path[1] == ':') {
            try out.append(a, std.ascii.toLower(c));
        } else if (std.ascii.isAlphanumeric(c) or std.mem.findScalar(u8, "-._~/", c) != null) {
            try out.append(a, c);
        } else {
            try out.print(a, "%{X:0>2}", .{c});
        }
    }
    return out.toOwnedSlice(a);
}

/// Whether two paths name the same file, Windows's without regard to case
pub fn samePath(style: Style, x: []const u8, y: []const u8) bool {
    return if (style == .windows) std.ascii.eqlIgnoreCase(x, y) else std.mem.eql(u8, x, y);
}

/// `s` with its `%XX` escapes decoded
fn decode(a: Allocator, s: []const u8) Allocator.Error![]u8 {
    var out = try a.alloc(u8, s.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) {
        if (s[i] == '%' and i + 2 < s.len) {
            if (std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16)) |byte| {
                out[n] = byte;
                i += 3;
                continue;
            } else |_| {}
        }
        out[n] = s[i];
        i += 1;
    }
    return a.realloc(out, n);
}

const testing = std.testing;

test toPath {
    const a = testing.allocator;
    const win = (try toPath(a, "file:///c%3A/Program%20Files/a.csm", .windows)).?;
    defer a.free(win);
    try testing.expectEqualStrings("c:\\Program Files\\a.csm", win);
    const posix = (try toPath(a, "file:///home/me/a%23b.csm", .posix)).?;
    defer a.free(posix);
    try testing.expectEqualStrings("/home/me/a#b.csm", posix);
    try testing.expect((try toPath(a, "untitled:Untitled-1", .posix)) == null);
    try testing.expect((try toPath(a, "file://server/share/a.csm", .windows)) == null);
}

test fromPath {
    const a = testing.allocator;
    const win = try fromPath(a, "C:\\Program Files\\a.csm", .windows);
    defer a.free(win);
    try testing.expectEqualStrings("file:///c%3A/Program%20Files/a.csm", win);
    const posix = try fromPath(a, "/home/me/a#b.csm", .posix);
    defer a.free(posix);
    try testing.expectEqualStrings("file:///home/me/a%23b.csm", posix);
}

test "fromPath and toPath round trip" {
    const a = testing.allocator;
    const uri = try fromPath(a, "c:\\x y\\%z.csm", .windows);
    defer a.free(uri);
    const path = (try toPath(a, uri, .windows)).?;
    defer a.free(path);
    try testing.expectEqualStrings("c:\\x y\\%z.csm", path);
}
