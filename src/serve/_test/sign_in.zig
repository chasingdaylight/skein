// cspell:ignore Fspec
//! Who is asking `skein serve`: through a proxy, or through the forge,
//! with the forge's answers recorded.

// req: serve.sign-in
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

const People = @import("../People.zig");
const github = @import("../../forge/github.zig");
const oauth = @import("../oauth.zig");
const sign_in = @import("../sign_in.zig");

fn ip(text: []const u8) Io.net.IpAddress {
    return Io.net.IpAddress.parse(text, 0) catch unreachable;
}

test "a proxy's header is believed from the proxy alone" {
    var people: People = .init(testing.allocator);
    defer people.deinit();
    const setup: sign_in.Setup = .{ .mode = .proxy, .proxies = &.{ip("10.0.0.2")} };
    const u = sign_in.who(setup, &people, .{ .peer = ip("10.0.0.2"), .user = "ada", .email = "ada@example.invalid", .path = "/" }).?;
    try testing.expectEqualStrings("ada", u.login);
    try testing.expectEqualStrings("ada@example.invalid", u.email);
    // the same header from anyone else is nobody
    try testing.expect(sign_in.who(setup, &people, .{ .peer = ip("10.0.0.9"), .user = "ada", .path = "/" }) == null);
    try testing.expect(sign_in.who(setup, &people, .{ .peer = ip("10.0.0.2"), .path = "/" }) == null);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // anyone reads; a change needs someone signed in
    try testing.expect(try sign_in.gate(testing.io, arena.allocator(), setup, &people, .{ .path = "/spec/a.html" }, null) == null);
    try testing.expect(try sign_in.gate(testing.io, arena.allocator(), setup, &people, .{ .path = "/_skein/form" }, null) == null);
    const api = (try sign_in.gate(testing.io, arena.allocator(), setup, &people, .{ .path = "/_skein/save", .change = true }, null)).?;
    try testing.expectEqual(.unauthorized, api.status);
    try testing.expect(std.mem.find(u8, api.body, "sign in to change or approve anything") != null);
    try testing.expect(try sign_in.gate(testing.io, arena.allocator(), setup, &people, .{ .path = "/_skein/save", .change = true }, u) == null);
    try testing.expect(try sign_in.gate(testing.io, arena.allocator(), setup, &people, .{ .path = "/" }, u) == null);
}

fn recorded(_: Io, _: std.mem.Allocator, r: oauth.Request) anyerror!github.Reply {
    if (std.mem.endsWith(u8, r.url, "access_token")) return .{ .body = "{\"access_token\":\"t0ken\"}" };
    return .{ .body = "{\"login\":\"ada\",\"name\":\"Ada Lovelace\",\"email\":\"ada@example.invalid\"}" };
}

test "through the forge: the authorize page, the way back, the session" {
    var people: People = .init(testing.allocator);
    defer people.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = oauth.call;
    defer oauth.call = before;
    oauth.call = recorded;
    const setup: sign_in.Setup = .{ .mode = .forge, .url = "https://reqs.example.com", .forge = .{ .kind = .github, .repository = "example/spec" }, .app = .{ .id = "abc", .secret = "s" } };

    // nobody signed in: a change is refused, and says to sign in
    try testing.expect(std.mem.find(u8, (try sign_in.gate(testing.io, a, setup, &people, .{ .path = "/_skein/save", .change = true }, null)).?.body, "\"signIn\":true") != null);

    const go = (try sign_in.gate(testing.io, a, setup, &people, .{ .path = sign_in.sign_in_path, .query = "back=%2Fspec%2Fa.html" }, null)).?;
    try testing.expectEqual(.found, go.status);
    const location = go.location.?;
    try testing.expect(std.mem.startsWith(u8, location, "https://github.com/login/oauth/authorize?"));
    const state = location[std.mem.find(u8, location, "state=").? + 6 ..][0..64];

    // a state not begun here is refused
    try testing.expectEqual(.unauthorized, (try sign_in.gate(testing.io, a, setup, &people, .{ .path = sign_in.back_path, .query = "code=c&state=nope" }, null)).?.status);
    const back = (try sign_in.gate(testing.io, a, setup, &people, .{ .path = sign_in.back_path, .query = try a.print("code=c0de&state={s}", .{state}) }, null)).?;
    try testing.expectEqualStrings("/spec/a.html", back.location.?);
    const cookie = back.set_cookie.?;
    try testing.expect(std.mem.endsWith(u8, cookie, "; Path=/; HttpOnly; SameSite=Lax; Secure"));
    const token = cookie["skein-session=".len..][0..64];

    const u = sign_in.who(setup, &people, .{ .cookie = try a.print("other=1; skein-session={s}", .{token}), .path = "/" }).?;
    try testing.expectEqualStrings("Ada Lovelace", u.name);
    try testing.expect(sign_in.who(setup, &people, .{ .cookie = "skein-session=forged", .path = "/" }) == null);
}

test "listening beyond this computer needs a sign-in and the address people use" {
    const cli = @import("../../cli.zig");
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expect(std.mem.find(u8, (try cli.parse(a, &.{ "serve", "--listen", "0.0.0.0" })).misuse, "give --sign-in proxy or forge") != null);
    try testing.expect(std.mem.find(u8, (try cli.parse(a, &.{ "serve", "--listen", "0.0.0.0", "--sign-in", "proxy" })).misuse, "give --url") != null);
    try testing.expect(std.mem.find(u8, (try cli.parse(a, &.{ "serve", "--sign-in", "forge" })).misuse, "give --url") != null);
    const ok = (try cli.parse(a, &.{ "serve", "--listen", "0.0.0.0", "--sign-in", "proxy", "--url", "https://reqs.example.com", "--proxy", "10.0.0.2" })).serve;
    try testing.expectEqual(.proxy, ok.sign_in);
    try testing.expectEqualStrings("10.0.0.2", ok.proxies[0]);
}
