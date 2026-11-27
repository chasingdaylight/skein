//! Who is asking `skein serve`, when it serves a team (#281):
//!
//! - `--sign-in proxy`: a reverse proxy in front signs people in and names
//!   them in a header (`X-Forwarded-User`, and `X-Forwarded-Email`), which
//!   is believed only from the proxy's own addresses (`--proxy`, by
//!   default this computer's)
//! - `--sign-in forge`: the project's forge, through OAuth (serve/oauth.zig);
//!   a session is a cookie
//!
//! Anyone may read; changing or approving anything needs someone signed
//! in (emanspeaks, 2026-11-27, #288).

const std = @import("std");
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const People = @import("People.zig");
const answer = @import("answer.zig");
const cli = @import("../cli.zig");
const inline_html = @import("../html/inline.zig");
const oauth = @import("oauth.zig");
const query = @import("query.zig");

pub const cookie_name = "skein-session";
pub const sign_in_path = "/_skein/sign-in";
pub const back_path = "/_skein/oauth";

/// How people sign in, as `skein serve` was started
pub const Setup = struct {
    mode: cli.Serve.SignIn = .none,
    /// the address people reach it at (`--url`), without a trailing slash
    url: []const u8 = "",
    user_header: []const u8 = "X-Forwarded-User",
    email_header: []const u8 = "X-Forwarded-Email",
    /// the addresses a proxy's header is believed from
    proxies: []const Io.net.IpAddress = &.{},
    forge: ?Forge = null,
    app: ?oauth.App = null,
};

/// What a request shows of who sent it
pub const Seen = struct {
    peer: ?Io.net.IpAddress = null,
    cookie: ?[]const u8 = null,
    user: ?[]const u8 = null,
    email: ?[]const u8 = null,
    path: []const u8,
    query: []const u8 = "",
    /// whether it would change something (a POST)
    change: bool = false,
};

/// Who sent the request; null when nobody signed in, or nobody signs in
pub fn who(setup: Setup, people: *const People, seen: Seen) ?People.User {
    switch (setup.mode) {
        .none => return null,
        .proxy => {
            const peer = seen.peer orelse return null;
            if (!trusted(setup.proxies, peer)) return null;
            const login = std.mem.trim(u8, seen.user orelse return null, " ");
            if (login.len == 0) return null;
            return .{ .login = login, .name = login, .email = if (seen.email) |e| std.mem.trim(u8, e, " ") else login };
        },
        .forge => return people.session(cookieValue(seen.cookie orelse return null) orelse return null),
    }
}

/// The answer for someone who has not signed in, and to the sign-in's own
/// requests; null when the request goes on to be answered
pub fn gate(io: Io, arena: std.mem.Allocator, setup: Setup, people: *People, seen: Seen, user: ?People.User) !?answer.Answer {
    if (setup.mode == .none) return null;
    if (setup.mode == .forge) {
        if (std.mem.eql(u8, seen.path, sign_in_path)) {
            const back = try query.param(arena, seen.query, "back") orelse "/";
            const state = try people.begin(io, if (std.mem.startsWith(u8, back, "/") and !std.mem.startsWith(u8, back, "//")) back else "/");
            return .{ .status = .found, .body = "", .location = try oauth.authorizeUrl(arena, &setup.forge.?, setup.app.?, try backUrl(arena, setup), state) };
        }
        if (std.mem.eql(u8, seen.path, back_path)) return try comeBack(io, arena, setup, people, seen);
    }
    // reading needs nobody to sign in; changing or approving anything does
    if (user != null or !seen.change) return null;
    return .{ .status = .unauthorized, .content_type = "application/json", .body = switch (setup.mode) {
        .forge => "{\"error\":\"skein serve: sign in to change or approve anything\",\"signIn\":true}",
        else => "{\"error\":\"skein serve: sign in to change or approve anything: nobody is signed in on this request (the proxy names nobody)\"}",
    } };
}

/// The forge sent the person back with a code: who they are, a session,
/// and the page they began on
fn comeBack(io: Io, arena: std.mem.Allocator, setup: Setup, people: *People, seen: Seen) !answer.Answer {
    const state = try query.param(arena, seen.query, "state") orelse "";
    const page = people.finish(state) orelse return failed(arena, "this sign-in was not begun here, or was used already; sign in again");
    const code = try query.param(arena, seen.query, "code") orelse return failed(arena, "the forge gave no code (was access refused?)");
    return switch (try oauth.exchange(io, arena, &setup.forge.?, setup.app.?, try backUrl(arena, setup), code)) {
        .failed => |why| failed(arena, why),
        .user => |u| .{
            .status = .found,
            .body = "",
            .location = page,
            .set_cookie = try arena.print("{s}={s}; Path=/; HttpOnly; SameSite=Lax{s}", .{ cookie_name, try people.signIn(io, u), if (std.mem.startsWith(u8, setup.url, "https:")) "; Secure" else "" }),
        },
    };
}

fn failed(arena: std.mem.Allocator, why: []const u8) !answer.Answer {
    var page: std.ArrayList(u8) = .empty;
    try page.appendSlice(arena, "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Not signed in</title>\n</head>\n<body>\n<h1>Not signed in</h1>\n<p>");
    try inline_html.escape(arena, &page, why);
    try page.print(arena, "</p>\n<p><a href=\"{s}\">Sign in again</a>.</p>\n</body>\n</html>\n", .{sign_in_path});
    return .{ .status = .unauthorized, .body = page.items };
}

fn backUrl(arena: std.mem.Allocator, setup: Setup) ![]const u8 {
    return arena.print("{s}{s}", .{ std.mem.trimEnd(u8, setup.url, "/"), back_path });
}

fn trusted(proxies: []const Io.net.IpAddress, peer: Io.net.IpAddress) bool {
    for (proxies) |p| {
        switch (p) {
            .ip4 => |x| if (peer == .ip4 and std.mem.eql(u8, &x.bytes, &peer.ip4.bytes)) return true,
            .ip6 => |x| if (peer == .ip6 and std.mem.eql(u8, &x.bytes, &peer.ip6.bytes)) return true,
        }
    }
    return false;
}

/// The session's token in a `Cookie` header
fn cookieValue(header: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, header, ';');
    while (it.next()) |part| {
        const kv = std.mem.trim(u8, part, " ");
        if (std.mem.startsWith(u8, kv, cookie_name ++ "=")) return kv[cookie_name.len + 1 ..];
    }
    return null;
}

test {
    _ = @import("_test/sign_in.zig");
}
