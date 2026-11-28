//! Who is asking `skein serve`, when it serves a team (#281):
//!
//! - `--sign-in proxy`: a reverse proxy in front signs people in and names
//!   them in a header (`X-Forwarded-User`, and `X-Forwarded-Email`), which
//!   is believed only from the proxy's own addresses (`--proxy`, by
//!   default this computer's)
//! - `--sign-in forge`: the project's forge, through OAuth (serve/oauth.zig);
//!   a session is a cookie
//! - `--sign-in oidc --issuer URL`: any OpenID Connect provider, the same
//!   way; it can also be asked to make the person sign in again, for an
//!   approval that must be signed (`[serve] approve_sign_in = "again"`, #288)
//!
//! Anyone may read; changing or approving anything needs someone signed
//! in (emanspeaks, 2026-11-27, #288).

const std = @import("std");
const Io = std.Io;

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
    /// with `forge` and `oidc`: where people sign in
    provider: ?oauth.Provider = null,
    app: ?oauth.App = null,
};

/// How long a sign-in asked for again counts as fresh, in seconds
pub const fresh_seconds = 300;

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
    /// when it came, in seconds: sessions and sign-ins under way end (#303)
    now: i64 = 0,
};

/// Who sent the request; null when nobody signed in, or nobody signs in,
/// or their session has ended
pub fn who(setup: Setup, people: *People, seen: Seen) ?People.User {
    switch (setup.mode) {
        .none => return null,
        .proxy => {
            const peer = seen.peer orelse return null;
            if (!trusted(setup.proxies, peer)) return null;
            const login = std.mem.trim(u8, seen.user orelse return null, " ");
            if (login.len == 0) return null;
            return .{ .login = login, .name = login, .email = if (seen.email) |e| std.mem.trim(u8, e, " ") else login, .provider = "proxy", .subject = login };
        },
        .forge, .oidc => return people.session(cookieValue(seen.cookie orelse return null) orelse return null, seen.now),
    }
}

/// The answer for someone who has not signed in, and to the sign-in's own
/// requests; null when the request goes on to be answered
pub fn gate(io: Io, arena: std.mem.Allocator, setup: Setup, people: *People, seen: Seen, user: ?People.User) !?answer.Answer {
    if (setup.mode == .none) return null;
    if (setup.mode == .forge or setup.mode == .oidc) {
        if (std.mem.eql(u8, seen.path, sign_in_path)) {
            const back = try query.param(arena, seen.query, "back") orelse "/";
            const again = std.mem.eql(u8, try query.param(arena, seen.query, "again") orelse "", "1");
            const state = try people.begin(io, if (std.mem.startsWith(u8, back, "/") and !std.mem.startsWith(u8, back, "//")) back else "/", again, seen.now);
            return .{ .status = .found, .body = "", .location = try oauth.authorizeUrl(arena, setup.provider.?, setup.app.?, try backUrl(arena, setup), state, again) };
        }
        if (std.mem.eql(u8, seen.path, back_path)) return try comeBack(io, arena, setup, people, seen);
    }
    // reading needs nobody to sign in; changing or approving anything does
    if (user != null or !seen.change) return null;
    return .{ .status = .unauthorized, .content_type = "application/json", .body = switch (setup.mode) {
        .forge, .oidc => "{\"error\":\"skein serve: sign in to change or approve anything\",\"signIn\":true}",
        else => "{\"error\":\"skein serve: sign in to change or approve anything: nobody is signed in on this request (the proxy names nobody)\"}",
    } };
}

/// The forge sent the person back with a code: who they are, a session,
/// and the page they began on
fn comeBack(io: Io, arena: std.mem.Allocator, setup: Setup, people: *People, seen: Seen) !answer.Answer {
    const state = try query.param(arena, seen.query, "state") orelse "";
    const pending = try people.finish(arena, state, seen.now) orelse return failed(arena, "this sign-in was not begun here, was used already, or was begun more than ten minutes ago; sign in again");
    const code = try query.param(arena, seen.query, "code") orelse return failed(arena, "the provider gave no code (was access refused?)");
    const now = seen.now;
    return switch (try oauth.exchange(io, arena, setup.provider.?, setup.app.?, try backUrl(arena, setup), code, now)) {
        .failed => |why| failed(arena, why),
        .user => |signed| blk: {
            var u = signed;
            // asked for again: the provider must say it was just now
            if (pending.again) {
                if (u.at_unix < now - fresh_seconds) break :blk failed(arena, "the provider did not ask you to sign in again (its sign-in is older than five minutes)");
                u.again = true;
            }
            break :blk .{
                .status = .found,
                .body = "",
                .location = pending.page,
                .set_cookie = try arena.print("{s}={s}; Path=/; HttpOnly; SameSite=Lax{s}", .{ cookie_name, try people.signIn(io, u, now), if (std.mem.startsWith(u8, setup.url, "https:")) "; Secure" else "" }),
            };
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
pub fn cookieValue(header: []const u8) ?[]const u8 {
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
