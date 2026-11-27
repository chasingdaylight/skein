//! Who uses `skein serve`, and where each works (#281): the sessions of
//! those signed in through the forge, the sign-ins under way, and the
//! change each person has open. On this computer alone, one person, with
//! the login "". Kept for as long as it serves, in its own arena.

const std = @import("std");
const Io = std.Io;

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
    pub fn author(u: User, a: std.mem.Allocator) ![]const u8 {
        return a.print("{s} <{s}>", .{ u.name, u.email });
    }
};

arena: std.heap.ArenaAllocator,
/// by the session's token
sessions: std.StringHashMapUnmanaged(User) = .empty,
/// the `state` of each sign-in under way
pending: std.StringHashMapUnmanaged(Pending) = .empty,
/// the change each has open, by login
open: std.StringHashMapUnmanaged([]const u8) = .empty,

pub const Pending = struct { page: []const u8, again: bool };

pub fn init(gpa: std.mem.Allocator) People {
    return .{ .arena = .init(gpa) };
}

pub fn deinit(p: *People) void {
    p.arena.deinit();
}

/// A new session for `user`; its token
pub fn signIn(p: *People, io: Io, user: User) ![]const u8 {
    const a = p.arena.allocator();
    const token = try newToken(io, a);
    var u = user;
    inline for (.{ "login", "name", "email", "provider", "subject", "at" }) |f| @field(u, f) = try a.dupe(u8, @field(user, f));
    try p.sessions.put(a, token, u);
    return token;
}

pub fn session(p: *const People, token: []const u8) ?User {
    return p.sessions.get(token);
}

/// A sign-in begun from `page`, asked for again to approve or not; the
/// `state` that comes back with it
pub fn begin(p: *People, io: Io, page: []const u8, again: bool) ![]const u8 {
    const a = p.arena.allocator();
    const state = try newToken(io, a);
    try p.pending.put(a, state, .{ .page = try a.dupe(u8, page), .again = again });
    return state;
}

/// The sign-in a `state` began, which ends it; null for a `state` not given
pub fn finish(p: *People, state: []const u8) ?Pending {
    const kv = p.pending.fetchRemove(state) orelse return null;
    return kv.value;
}

/// The sign-in again of `token`'s session is used: the next approval asks again
pub fn usedAgain(p: *People, token: []const u8) void {
    if (p.sessions.getPtr(token)) |u| u.again = false;
}

/// The change `login` has open
pub fn changeOf(p: *const People, login: []const u8) ?[]const u8 {
    return p.open.get(login);
}

/// `login` opens the change `name`, or none
pub fn setChange(p: *People, login: []const u8, name: ?[]const u8) !void {
    const a = p.arena.allocator();
    if (name) |n| {
        try p.open.put(a, try a.dupe(u8, login), try a.dupe(u8, n));
    } else _ = p.open.remove(login);
}

/// The change `name` is gone (merged, proposed, abandoned): nobody has it open
pub fn closeChange(p: *People, name: []const u8) void {
    var it = p.open.iterator();
    while (it.next()) |e| {
        if (std.mem.eql(u8, e.value_ptr.*, name)) {
            _ = p.open.remove(e.key_ptr.*);
            it = p.open.iterator();
        }
    }
}

/// 32 random bytes, in hexadecimal
fn newToken(io: Io, a: std.mem.Allocator) ![]const u8 {
    var bytes: [32]u8 = undefined;
    io.randomSecure(&bytes) catch io.random(&bytes);
    return a.dupe(u8, &std.fmt.bytesToHex(bytes, .lower));
}

test "sessions, sign-ins under way, and open changes" {
    var p: People = .init(std.testing.allocator);
    defer p.deinit();
    const io = std.testing.io;
    const token = try p.signIn(io, .{ .login = "ada", .name = "Ada", .email = "ada@example.invalid" });
    try std.testing.expectEqual(64, token.len);
    try std.testing.expectEqualStrings("Ada", p.session(token).?.name);
    try std.testing.expect(p.session("nope") == null);
    const state = try p.begin(io, "/spec/a.html", true);
    const f = p.finish(state).?;
    try std.testing.expectEqualStrings("/spec/a.html", f.page);
    try std.testing.expect(f.again);
    try std.testing.expect(p.finish(state) == null);
    try p.setChange("ada", "fix-a");
    try p.setChange("bob", "fix-a");
    try p.setChange("cy", "other");
    p.closeChange("fix-a");
    try std.testing.expect(p.changeOf("ada") == null and p.changeOf("bob") == null);
    try std.testing.expectEqualStrings("other", p.changeOf("cy").?);
}
