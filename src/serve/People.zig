//! Who uses `skein serve`, and where each works (#281): the sessions of
//! those signed in through the forge, the sign-ins under way, and the
//! change each person has open. On this computer alone, one person, with
//! the login "". A session ends when it has not been used for a while, and
//! after a longest life; a sign-in under way is forgotten when it is not
//! finished in ten minutes, and there are never more than a thousand under
//! way (#303). What ends is freed, so that the memory held stays bounded.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const People = @This();

pub const User = struct {
    /// what they are known by: the forge's login, or the proxy's header
    login: []const u8,
    name: []const u8,
    email: []const u8,
    /// where they signed in (`forge:github`, `oidc:ISSUER`, `proxy`), who
    /// it says they are, and when, as RFC 3339 and in seconds
    provider: []const u8 = "",
    subject: []const u8 = "",
    at: []const u8 = "",
    at_unix: i64 = 0,
    /// whether that sign-in was asked for again, to approve
    again: bool = false,

    /// As git writes an author: `Name <email>`
    pub fn author(u: User, a: Allocator) ![]const u8 {
        return a.print("{s} <{s}>", .{ u.name, u.email });
    }
};

/// How long sessions and sign-ins under way last, in seconds
pub const Limits = struct {
    /// a session not used for this long ends (`--session-hours`)
    idle: i64 = 12 * 3600,
    /// and none lasts longer than this from its sign-in (`--session-days`)
    longest: i64 = 7 * 24 * 3600,
    /// a sign-in begun and not finished in this time is forgotten
    pending: i64 = 10 * 60,
    /// the most sign-ins under way at once; past it, the oldest is forgotten
    pending_most: usize = 1000,
};

const Session = struct { user: User, started: i64, last: i64 };

pub const Pending = struct { page: []const u8, again: bool, begun: i64 = 0 };

/// owns the keys and values of the maps below, and each session's user
gpa: Allocator,
limits: Limits = .{},
/// by the session's token
sessions: std.StringHashMapUnmanaged(Session) = .empty,
/// the `state` of each sign-in under way
pending: std.StringHashMapUnmanaged(Pending) = .empty,
/// the change each has open, by login
open: std.StringHashMapUnmanaged([]const u8) = .empty,

pub fn init(gpa: Allocator) People {
    return .{ .gpa = gpa };
}

pub fn deinit(p: *People) void {
    var s = p.sessions.iterator();
    while (s.next()) |e| p.freeSession(e.key_ptr.*, e.value_ptr.*);
    p.sessions.deinit(p.gpa);
    var w = p.pending.iterator();
    while (w.next()) |e| p.freePending(e.key_ptr.*, e.value_ptr.*);
    p.pending.deinit(p.gpa);
    var o = p.open.iterator();
    while (o.next()) |e| {
        p.gpa.free(e.key_ptr.*);
        p.gpa.free(e.value_ptr.*);
    }
    p.open.deinit(p.gpa);
}

/// A new session for `user`, signed in at `now`; its token
pub fn signIn(p: *People, io: Io, user: User, now: i64) Allocator.Error![]const u8 {
    p.prune(now);
    const token = try newToken(io, p.gpa);
    errdefer p.gpa.free(token);
    const u = try dupeUser(p.gpa, user);
    errdefer freeUser(p.gpa, u);
    try p.sessions.put(p.gpa, token, .{ .user = u, .started = now, .last = now });
    return token;
}

/// The user of the session `token` at `now`, which counts as its use; null
/// when there is no such session, or it has ended (and is forgotten)
pub fn session(p: *People, token: []const u8, now: i64) ?User {
    const s = p.sessions.getPtr(token) orelse return null;
    if (p.ended(s.*, now)) {
        const kv = p.sessions.fetchRemove(token).?;
        p.freeSession(kv.key, kv.value);
        return null;
    }
    s.last = now;
    return s.user;
}

fn ended(p: *const People, s: Session, now: i64) bool {
    return now - s.last > p.limits.idle or now - s.started > p.limits.longest;
}

/// A sign-in begun from `page` at `now`, asked for again to approve or
/// not; the `state` that comes back with it
pub fn begin(p: *People, io: Io, page: []const u8, again: bool, now: i64) Allocator.Error![]const u8 {
    p.prune(now);
    // past the most: the oldest is forgotten
    while (p.pending.count() >= p.limits.pending_most) {
        var oldest: ?[]const u8 = null;
        var at: i64 = std.math.maxInt(i64);
        var it = p.pending.iterator();
        while (it.next()) |e| if (e.value_ptr.begun < at) {
            at = e.value_ptr.begun;
            oldest = e.key_ptr.*;
        };
        const kv = p.pending.fetchRemove(oldest.?).?;
        p.freePending(kv.key, kv.value);
    }
    const state = try newToken(io, p.gpa);
    errdefer p.gpa.free(state);
    const copy = try p.gpa.dupe(u8, page);
    errdefer p.gpa.free(copy);
    try p.pending.put(p.gpa, state, .{ .page = copy, .again = again, .begun = now });
    return state;
}

/// The sign-in a `state` began, which ends it, its page in `arena`; null
/// for a `state` not given, or given more than ten minutes ago
pub fn finish(p: *People, arena: Allocator, state: []const u8, now: i64) Allocator.Error!?Pending {
    const kv = p.pending.fetchRemove(state) orelse return null;
    defer p.freePending(kv.key, kv.value);
    if (now - kv.value.begun > p.limits.pending) return null;
    return .{ .page = try arena.dupe(u8, kv.value.page), .again = kv.value.again, .begun = kv.value.begun };
}

/// Forgets the sessions that have ended and the sign-ins under way for too long
pub fn prune(p: *People, now: i64) void {
    while (true) {
        var it = p.sessions.iterator();
        const gone = while (it.next()) |e| {
            if (p.ended(e.value_ptr.*, now)) break e.key_ptr.*;
        } else break;
        const kv = p.sessions.fetchRemove(gone).?;
        p.freeSession(kv.key, kv.value);
    }
    while (true) {
        var it = p.pending.iterator();
        const gone = while (it.next()) |e| {
            if (now - e.value_ptr.begun > p.limits.pending) break e.key_ptr.*;
        } else break;
        const kv = p.pending.fetchRemove(gone).?;
        p.freePending(kv.key, kv.value);
    }
}

/// The sign-in again of `token`'s session is used: the next approval asks again
pub fn usedAgain(p: *People, token: []const u8) void {
    if (p.sessions.getPtr(token)) |s| s.user.again = false;
}

/// The change `login` has open
pub fn changeOf(p: *const People, login: []const u8) ?[]const u8 {
    return p.open.get(login);
}

/// `login` opens the change `name`, or none
pub fn setChange(p: *People, login: []const u8, name: ?[]const u8) Allocator.Error!void {
    const n = name orelse {
        if (p.open.fetchRemove(login)) |kv| {
            p.gpa.free(kv.key);
            p.gpa.free(kv.value);
        }
        return;
    };
    const copy = try p.gpa.dupe(u8, n);
    errdefer p.gpa.free(copy);
    if (p.open.getPtr(login)) |v| {
        p.gpa.free(v.*);
        v.* = copy;
        return;
    }
    const key = try p.gpa.dupe(u8, login);
    errdefer p.gpa.free(key);
    try p.open.put(p.gpa, key, copy);
}

/// The change `name` is gone (merged, proposed, abandoned): nobody has it open
pub fn closeChange(p: *People, name: []const u8) void {
    while (true) {
        var it = p.open.iterator();
        const login = while (it.next()) |e| {
            if (std.mem.eql(u8, e.value_ptr.*, name)) break e.key_ptr.*;
        } else return;
        const kv = p.open.fetchRemove(login).?;
        p.gpa.free(kv.key);
        p.gpa.free(kv.value);
    }
}

fn dupeUser(gpa: Allocator, u: User) Allocator.Error!User {
    var out = u;
    out.login = try gpa.dupe(u8, u.login);
    errdefer gpa.free(out.login);
    out.name = try gpa.dupe(u8, u.name);
    errdefer gpa.free(out.name);
    out.email = try gpa.dupe(u8, u.email);
    errdefer gpa.free(out.email);
    out.provider = try gpa.dupe(u8, u.provider);
    errdefer gpa.free(out.provider);
    out.subject = try gpa.dupe(u8, u.subject);
    errdefer gpa.free(out.subject);
    out.at = try gpa.dupe(u8, u.at);
    return out;
}

fn freeUser(gpa: Allocator, u: User) void {
    inline for (.{ "login", "name", "email", "provider", "subject", "at" }) |f| gpa.free(@field(u, f));
}

fn freeSession(p: *People, token: []const u8, s: Session) void {
    p.gpa.free(token);
    freeUser(p.gpa, s.user);
}

fn freePending(p: *People, state: []const u8, w: Pending) void {
    p.gpa.free(state);
    p.gpa.free(w.page);
}

/// 32 random bytes, in hexadecimal
fn newToken(io: Io, a: Allocator) Allocator.Error![]const u8 {
    var bytes: [32]u8 = undefined;
    io.randomSecure(&bytes) catch io.random(&bytes);
    return a.dupe(u8, &std.fmt.bytesToHex(bytes, .lower));
}

test {
    _ = @import("_test/people.zig");
}
