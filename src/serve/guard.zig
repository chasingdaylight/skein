//! What `skein serve` refuses before it reads a request's body: a request
//! for another host than this computer (a page of another site that a name
//! of its own leads here, DNS rebinding), a method it does not answer, and
//! a change without skein's own header, which a page of another site
//! cannot send without the browser asking first, which is refused.

const std = @import("std");

const answer = @import("answer.zig");

/// Under it, the requests of skein's pages (serve/edit_api.zig)
pub const api_prefix = "/_skein/";

pub const Method = enum { get, post };

pub const Request = struct {
    method: std.http.Method,
    /// the target without its query
    path: []const u8,
    /// the `Host` header
    host: ?[]const u8,
    /// whether it has the `x-skein` header
    skein_header: bool,
};

pub const Refused = struct { status: std.http.Status, text: []const u8 };

pub const Allowed = struct { method: Method, api: bool };

/// `public` is the host people reach it at (`--url`), when it is not this computer alone
pub fn check(r: Request, port: u16, public: ?[]const u8) union(enum) { allowed: Allowed, refused: Refused } {
    if (!local(r.host, port) and !samePublic(r.host, public)) return .{ .refused = .{ .status = .misdirected_request, .text = "skein serve answers only for 127.0.0.1, localhost and the address it was given (--url)\n" } };
    const method: Method = switch (r.method) {
        .GET, .HEAD => .get,
        .POST => .post,
        else => return .{ .refused = .{ .status = .method_not_allowed, .text = "skein serve answers GET and POST\n" } },
    };
    const api = std.mem.startsWith(u8, r.path, api_prefix) and !std.mem.eql(u8, r.path, answer.stamp_path) and !std.mem.eql(u8, r.path, answer.script_path);
    if (method == .post and !api) return .{ .refused = .{ .status = .method_not_allowed, .text = "skein serve: nothing to POST to here\n" } };
    if (method == .post and !r.skein_header) return .{ .refused = .{ .status = .forbidden, .text = "skein serve: a change comes from skein's own pages\n" } };
    return .{ .allowed = .{ .method = method, .api = api } };
}

/// Whether `host` names this computer, at `port`
fn local(host: ?[]const u8, port: u16) bool {
    const h = host orelse return false;
    var buf: [32]u8 = undefined;
    for ([_][]const u8{ "127.0.0.1", "localhost" }) |name| {
        const want = std.mem.print(&buf, "{s}:{d}", .{ name, port }) catch return false;
        if (std.ascii.eqlIgnoreCase(h, want)) return true;
    }
    return false;
}

// req: serve.local
test "requests for another host, other methods, and changes from other pages are refused" {
    const t = std.testing;
    const ok = check(.{ .method = .GET, .path = "/spec/a.html", .host = "127.0.0.1:8080", .skein_header = false }, 8080, null);
    try t.expectEqual(false, ok.allowed.api);
    try t.expectEqual(.get, check(.{ .method = .HEAD, .path = "/", .host = "LOCALHOST:8080", .skein_header = false }, 8080, null).allowed.method);
    try t.expectEqual(.misdirected_request, check(.{ .method = .GET, .path = "/", .host = "evil.example:8080", .skein_header = false }, 8080, null).refused.status);
    try t.expectEqual(.misdirected_request, check(.{ .method = .GET, .path = "/", .host = "127.0.0.1:9000", .skein_header = false }, 8080, null).refused.status);
    try t.expectEqual(.misdirected_request, check(.{ .method = .GET, .path = "/", .host = null, .skein_header = false }, 8080, null).refused.status);
    try t.expectEqual(.method_not_allowed, check(.{ .method = .PUT, .path = "/", .host = "127.0.0.1:8080", .skein_header = true }, 8080, null).refused.status);
    try t.expectEqual(.method_not_allowed, check(.{ .method = .POST, .path = "/spec/a.html", .host = "127.0.0.1:8080", .skein_header = true }, 8080, null).refused.status);
    try t.expectEqual(.forbidden, check(.{ .method = .POST, .path = "/_skein/save", .host = "127.0.0.1:8080", .skein_header = false }, 8080, null).refused.status);
    const save = check(.{ .method = .POST, .path = "/_skein/save", .host = "127.0.0.1:8080", .skein_header = true }, 8080, null).allowed;
    try t.expect(save.api and save.method == .post);
    try t.expect(!check(.{ .method = .GET, .path = answer.stamp_path, .host = "127.0.0.1:8080", .skein_header = false }, 8080, null).allowed.api);
}

fn samePublic(host: ?[]const u8, public: ?[]const u8) bool {
    const h = host orelse return false;
    const p = public orelse return false;
    return std.ascii.eqlIgnoreCase(h, p);
}

test "the address people reach it at, behind a proxy" {
    const t = std.testing;
    try t.expect(check(.{ .method = .GET, .path = "/", .host = "reqs.example.com", .skein_header = false }, 8080, "reqs.example.com") == .allowed);
    try t.expectEqual(.misdirected_request, check(.{ .method = .GET, .path = "/", .host = "evil.example", .skein_header = false }, 8080, "reqs.example.com").refused.status);
}
