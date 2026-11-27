//! What `skein serve` answers a request for a path with: a file of the
//! site, its pages with a script that loads them again when the files
//! change, or the problems that keep the site from being rendered.

const std = @import("std");

const Site = @import("Site.zig");
const inline_html = @import("../html/inline.zig");

pub const Answer = struct {
    status: std.http.Status = .ok,
    content_type: []const u8 = "text/html; charset=utf-8",
    body: []const u8,
    /// where a redirect goes
    location: ?[]const u8 = null,
};

/// Where a page asks whether the files changed
pub const stamp_path = "/_skein/stamp";
/// The script that edits, which every page loads (edit.js)
pub const script_path = "/_skein/edit.js";

/// The answer to a GET of `target`; the caller holds the site's mutex.
/// The body is in `arena`.
pub fn get(arena: std.mem.Allocator, s: *Site, target: []const u8) !Answer {
    const path_part = target[0 .. std.mem.findAny(u8, target, "?#") orelse target.len];
    if (std.mem.eql(u8, path_part, stamp_path)) return .{ .content_type = "text/plain", .body = try arena.dupe(u8, &(try s.current())) };
    if (std.mem.eql(u8, path_part, script_path)) return .{ .content_type = "text/javascript; charset=utf-8", .body = @embedFile("edit.js") };
    try s.refresh();
    if (s.failed) |why| return .{ .status = .service_unavailable, .body = try problems(arena, s, why) };

    var path = try decode(arena, std.mem.trimStart(u8, path_part, "/")) orelse return notFound(arena, s);
    if (path.len == 0 or path[path.len - 1] == '/') path = try arena.print("{s}index.html", .{path});
    const data = s.files.get(path) orelse {
        // a directory: its index, with the address ending in a slash
        if (s.files.get(try arena.print("{s}/index.html", .{path})) != null) return .{ .status = .moved_permanently, .body = "", .location = try arena.print("{s}/", .{path_part}) };
        return notFound(arena, s);
    };
    const kind = contentType(path);
    if (!std.mem.startsWith(u8, kind, "text/html")) return .{ .content_type = kind, .body = try arena.dupe(u8, data) };
    return .{ .body = try withReload(arena, data, &s.stamp) };
}

/// `page` with the script that loads it again once the files differ from `stamp`
fn withReload(arena: std.mem.Allocator, page: []const u8, stamp: []const u8) ![]const u8 {
    const script = try arena.print(
        \\<script>(function(){{var s="{s}";setInterval(function(){{fetch("{s}",{{cache:"no-store"}}).then(function(r){{return r.text()}}).then(function(t){{if(t!==s&&!window.skeinEditing)location.reload()}}).catch(function(){{}})}},1000)}})();</script>
        \\<script src="{s}"></script>
        \\
    , .{ stamp, stamp_path, script_path });
    const at = std.mem.findLast(u8, page, "</body>") orelse page.len;
    return std.mem.concat(arena, u8, &.{ page[0..at], script, page[at..] });
}

fn problems(arena: std.mem.Allocator, s: *Site, why: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>The site cannot be rendered</title>\n</head>\n<body>\n<h1>The site cannot be rendered</h1>\n<pre>");
    try inline_html.escape(arena, &out, why);
    try out.appendSlice(arena, "</pre>\n<p>This page loads again when the files change.</p>\n</body>\n</html>\n");
    return withReload(arena, out.items, &s.stamp);
}

fn notFound(arena: std.mem.Allocator, s: *Site) !Answer {
    const page = "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Not found</title>\n</head>\n<body>\n<h1>Not found</h1>\n<p><a href=\"/\">The front page</a>.</p>\n</body>\n</html>\n";
    return .{ .status = .not_found, .body = try withReload(arena, page, &s.stamp) };
}

/// `path` with its `%XX` escapes decoded; null when one is not valid
fn decode(arena: std.mem.Allocator, path: []const u8) !?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] != '%') {
            try out.append(arena, path[i]);
            continue;
        }
        if (i + 2 >= path.len) return null;
        const byte = std.fmt.parseInt(u8, path[i + 1 .. i + 3], 16) catch return null;
        try out.append(arena, byte);
        i += 2;
    }
    return out.items;
}

fn contentType(path: []const u8) []const u8 {
    const table = [_]struct { []const u8, []const u8 }{
        .{ ".html", "text/html; charset=utf-8" },     .{ ".css", "text/css; charset=utf-8" },
        .{ ".js", "text/javascript; charset=utf-8" }, .{ ".svg", "image/svg+xml" },
        .{ ".png", "image/png" },                     .{ ".jpg", "image/jpeg" },
        .{ ".jpeg", "image/jpeg" },                   .{ ".gif", "image/gif" },
        .{ ".webp", "image/webp" },                   .{ ".pdf", "application/pdf" },
        .{ ".md", "text/markdown; charset=utf-8" },
    };
    for (table) |entry| {
        if (std.ascii.endsWithIgnoreCase(path, entry[0])) return entry[1];
    }
    return "application/octet-stream";
}

test {
    _ = @import("_test/answer.zig");
}
