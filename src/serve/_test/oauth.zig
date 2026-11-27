// cspell:ignore Foauth Freqs cret lnbm
//! Signing in through a provider, with its answers recorded: GitHub,
//! GitLab, and an OpenID Connect provider found by discovery.

// req: serve.sign-in, serve.approve-sign-in
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

const Forge = @import("../../forge/Forge.zig");
const github = @import("../../forge/github.zig");
const oauth = @import("../oauth.zig");

var seen: [16][]const u8 = undefined;
var count: usize = 0;

/// An ID token whose claims are `claims`; its signature is not read
fn idToken(a: std.mem.Allocator, claims: []const u8) ![]const u8 {
    const e = std.base64.url_safe_no_pad.Encoder;
    const out = try a.alloc(u8, e.calcSize(claims.len));
    return a.print("eyJhbGciOiJSUzI1NiJ9.{s}.c2lnbmF0dXJl", .{e.encode(out, claims)});
}

fn recorded(_: Io, a: std.mem.Allocator, r: oauth.Request) anyerror!github.Reply {
    seen[count] = try a.print("{t} {s} {s} {s}", .{ r.method, r.url, r.auth orelse "-", r.form orelse "-" });
    count += 1;
    if (std.mem.endsWith(u8, r.url, "/.well-known/openid-configuration")) return .{ .body = "{\"issuer\":\"https://sso.example.gov\",\"authorization_endpoint\":\"https://sso.example.gov/authorize\",\"token_endpoint\":\"https://sso.example.gov/token\",\"userinfo_endpoint\":\"https://sso.example.gov/userinfo\"}" };
    if (std.mem.eql(u8, r.url, "https://sso.example.gov/token")) return .{ .body = try a.print("{{\"access_token\":\"t0ken\",\"id_token\":\"{s}\"}}", .{try idToken(a, "{\"iss\":\"https://sso.example.gov\",\"sub\":\"00u1\",\"auth_time\":1803895200,\"name\":\"Ada Lovelace\",\"email\":\"ada@example.gov\",\"preferred_username\":\"ada\"}")}) };
    if (std.mem.endsWith(u8, r.url, "access_token") or std.mem.endsWith(u8, r.url, "/oauth/token")) {
        if (std.mem.find(u8, r.form.?, "code=bad") != null) return .{ .body = "{\"error\":\"bad_verification_code\"}" };
        return .{ .body = "{\"access_token\":\"t0ken\",\"token_type\":\"bearer\"}" };
    }
    if (std.mem.endsWith(u8, r.url, "/api/v4/user")) return .{ .body = "{\"id\":7,\"username\":\"ada\",\"name\":\"Ada Lovelace\",\"public_email\":\"\",\"email\":\"ada@example.invalid\"}" };
    return .{ .body = "{\"id\":42,\"login\":\"ada\",\"name\":null,\"email\":null}" };
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

    const gh = try oauth.ofForge(a, &Forge{ .kind = .github, .repository = "example/spec" });
    try testing.expect(!gh.reauth);
    try testing.expectEqualStrings(
        "https://github.com/login/oauth/authorize?response_type=code&client_id=abc&redirect_uri=https%3A%2F%2Freqs.example.com%2F_skein%2Foauth&state=st4te&scope=read%3Auser%20user%3Aemail",
        try oauth.authorizeUrl(a, gh, app, back, "st4te", false),
    );
    const u = (try oauth.exchange(testing.io, a, gh, app, back, "c0de", 1803895200)).user;
    try testing.expectEqualStrings("ada", u.login);
    // no name, no public email: the login, and the forge's address that is no one's
    try testing.expectEqualStrings("ada", u.name);
    try testing.expectEqualStrings("ada@users.noreply.github.com", u.email);
    try testing.expectEqualStrings("forge:github", u.provider);
    try testing.expectEqualStrings("42", u.subject);
    try testing.expectEqualStrings("2027-03-01T10:00:00Z", u.at);
    try testing.expectEqualStrings("POST https://github.com/login/oauth/access_token - grant_type=authorization_code&client_id=abc&client_secret=s3cret&code=c0de&redirect_uri=https%3A%2F%2Freqs.example.com%2F_skein%2Foauth", seen[0]);
    try testing.expectEqualStrings("GET https://api.github.com/user Bearer t0ken -", seen[1]);
    try testing.expectEqualStrings("the provider gave no token (the code may have expired: sign in again)", (try oauth.exchange(testing.io, a, gh, app, back, "bad", 0)).failed);

    const gl = try oauth.ofForge(a, &Forge{ .kind = .gitlab, .repository = "group/spec", .url = "https://gitlab.example.com" });
    try testing.expect(std.mem.startsWith(u8, try oauth.authorizeUrl(a, gl, app, back, "s", false), "https://gitlab.example.com/oauth/authorize?"));
    const g = (try oauth.exchange(testing.io, a, gl, app, back, "c0de", 0)).user;
    try testing.expectEqualStrings("ada", g.login);
    try testing.expectEqualStrings("Ada Lovelace", g.name);
    try testing.expectEqualStrings("ada@example.invalid", g.email);
}

test "an OpenID Connect provider: discovered, asked to sign in again, its ID token read" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = oauth.call;
    defer oauth.call = before;
    oauth.call = recorded;
    count = 0;
    const app: oauth.App = .{ .id = "abc", .secret = "s3cret" };
    const back = "https://reqs.example.com/_skein/oauth";

    const p = (try oauth.discover(testing.io, a, "https://sso.example.gov/")).ok;
    try testing.expect(p.reauth);
    try testing.expectEqualStrings("oidc:https://sso.example.gov", p.name);
    const again = try oauth.authorizeUrl(a, p, app, back, "st", true);
    try testing.expect(std.mem.startsWith(u8, again, "https://sso.example.gov/authorize?"));
    try testing.expect(std.mem.endsWith(u8, again, "&scope=openid%20profile%20email&prompt=login&max_age=0"));

    const u = (try oauth.exchange(testing.io, a, p, app, back, "c0de", 0)).user;
    try testing.expectEqualStrings("ada", u.login);
    try testing.expectEqualStrings("Ada Lovelace", u.name);
    try testing.expectEqualStrings("ada@example.gov", u.email);
    try testing.expectEqualStrings("00u1", u.subject);
    // when the provider says they signed in, not when the code came back
    try testing.expectEqual(1803895200, u.at_unix);
}
