// cspell:ignore Foauth Freqs cret
//! Signing in through the forge, with the forge's answers recorded.

// req: serve.sign-in
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

const github = @import("../../forge/github.zig");
const oauth = @import("../oauth.zig");

var seen: [8][]const u8 = undefined;
var count: usize = 0;

fn recorded(_: Io, a: std.mem.Allocator, r: oauth.Request) anyerror!github.Reply {
    seen[count] = try a.print("{t} {s} {s} {s}", .{ r.method, r.url, r.auth orelse "-", r.form orelse "-" });
    count += 1;
    if (std.mem.endsWith(u8, r.url, "access_token") or std.mem.endsWith(u8, r.url, "/oauth/token")) {
        if (std.mem.find(u8, r.form.?, "code=bad") != null) return .{ .body = "{\"error\":\"bad_verification_code\"}" };
        return .{ .body = "{\"access_token\":\"t0ken\",\"token_type\":\"bearer\"}" };
    }
    if (std.mem.endsWith(u8, r.url, "/api/v4/user")) return .{ .body = "{\"username\":\"ada\",\"name\":\"Ada Lovelace\",\"public_email\":\"\",\"email\":\"ada@example.invalid\"}" };
    return .{ .body = "{\"login\":\"ada\",\"name\":null,\"email\":null}" };
}

test "the authorize page, and who comes back, on GitHub and GitLab" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = oauth.call;
    defer oauth.call = before;
    oauth.call = recorded;
    count = 0;
    const app: oauth.App = .{ .id = "abc", .secret = "s3cret" };
    const back = "https://reqs.example.com/_skein/oauth";

    const gh: @import("../../forge/Forge.zig") = .{ .kind = .github, .repository = "example/spec" };
    try testing.expectEqualStrings(
        "https://github.com/login/oauth/authorize?response_type=code&client_id=abc&redirect_uri=https%3A%2F%2Freqs.example.com%2F_skein%2Foauth&state=st4te&scope=read%3Auser%20user%3Aemail",
        try oauth.authorizeUrl(a, &gh, app, back, "st4te"),
    );
    const u = (try oauth.exchange(testing.io, a, &gh, app, back, "c0de")).user;
    try testing.expectEqualStrings("ada", u.login);
    // no name, no public email: the login, and the forge's address that is no one's
    try testing.expectEqualStrings("ada", u.name);
    try testing.expectEqualStrings("ada@users.noreply.github.com", u.email);
    try testing.expectEqualStrings("POST https://github.com/login/oauth/access_token - grant_type=authorization_code&client_id=abc&client_secret=s3cret&code=c0de&redirect_uri=https%3A%2F%2Freqs.example.com%2F_skein%2Foauth", seen[0]);
    try testing.expectEqualStrings("GET https://api.github.com/user Bearer t0ken -", seen[1]);
    try testing.expectEqualStrings("the forge gave no token (the code may have expired: sign in again)", (try oauth.exchange(testing.io, a, &gh, app, back, "bad")).failed);

    const gl: @import("../../forge/Forge.zig") = .{ .kind = .gitlab, .repository = "group/spec", .url = "https://gitlab.example.com" };
    try testing.expect(std.mem.startsWith(u8, try oauth.authorizeUrl(a, &gl, app, back, "s"), "https://gitlab.example.com/oauth/authorize?"));
    const g = (try oauth.exchange(testing.io, a, &gl, app, back, "c0de")).user;
    try testing.expectEqualStrings("ada", g.login);
    try testing.expectEqualStrings("Ada Lovelace", g.name);
    try testing.expectEqualStrings("ada@example.invalid", g.email);
}
