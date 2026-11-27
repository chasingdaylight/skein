//! Signing in to `skein serve` through a provider (#281, #288): the
//! project's forge (`--sign-in forge`) or any OpenID Connect provider
//! (`--sign-in oidc --issuer URL`, found by its discovery document), with
//! OAuth's authorization code flow. A person is sent to the provider's
//! authorize page with a `state`, comes back to `URL/_skein/oauth` with a
//! code, which is exchanged, with the app's secret, for a token that says
//! who they are. The app's id and secret come from the environment,
//! `SKEIN_OAUTH_CLIENT_ID` and `SKEIN_OAUTH_CLIENT_SECRET`, never the
//! repository. An OIDC provider can be asked to make the person sign in
//! again (`prompt=login`, `max_age=0`), and its ID token says when they did
//! (`auth_time`); it comes straight from the provider over TLS, so its
//! claims are read without checking its signature (OpenID Connect Core
//! 3.1.3.7).
//!
//! | Forge | Authorize, token | Who |
//! | --- | --- | --- |
//! | GitHub | `/login/oauth/authorize`, `/login/oauth/access_token` | `api.github.com/user` (`URL/api/v3/user` for a server of one's own) |
//! | GitLab | `/oauth/authorize`, `/oauth/token` | `/api/v4/user` |
//! | Forgejo | `/login/oauth/authorize`, `/login/oauth/access_token` | `/api/v1/user` |

const std = @import("std");
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const People = @import("People.zig");
const github = @import("../forge/github.zig");
const query = @import("query.zig");
const tool = @import("../forge/tool.zig");

pub const Request = struct {
    method: std.http.Method,
    url: []const u8,
    /// the value of the Authorization header, if any
    auth: ?[]const u8 = null,
    /// a form (`application/x-www-form-urlencoded`)
    form: ?[]const u8 = null,
};

/// How the provider is asked: the provider itself, or recorded answers in tests
pub var call: *const fn (Io, std.mem.Allocator, Request) anyerror!github.Reply = live;

fn live(io: Io, a: std.mem.Allocator, r: Request) anyerror!github.Reply {
    var headers: std.ArrayList(std.http.Header) = .empty;
    try headers.append(a, .{ .name = "Accept", .value = "application/json" });
    try headers.append(a, .{ .name = "User-Agent", .value = "skein" });
    if (r.auth) |v| try headers.append(a, .{ .name = "Authorization", .value = v });
    const uri = std.Uri.parse(r.url) catch return .{ .unreachable_ = try a.print("'{s}' is not a URL", .{r.url}) };
    const host = if (uri.host) |h| switch (h) {
        .raw, .percent_encoded => |s| s,
    } else r.url;
    return tool.httpsSendAs(io, a, r.method, r.url, headers.items, r.form, "application/x-www-form-urlencoded", host, "the sign-in provider");
}

pub const App = struct { id: []const u8, secret: []const u8 };

/// Where people sign in, and what it can do
pub const Provider = struct {
    /// as an approval's record names it: `forge:github`, `oidc:ISSUER`
    name: []const u8,
    authorize: []const u8,
    token: []const u8,
    /// who the token is of; empty when the ID token says
    user: []const u8,
    scope: []const u8,
    /// for an address the provider does not give: `LOGIN@users.noreply.HOST`
    host: []const u8,
    /// whether it can be asked to make the person sign in again
    reauth: bool = false,
};

/// The project's forge, as a provider
pub fn ofForge(a: std.mem.Allocator, forge: *const Forge) !Provider {
    const base = std.mem.trimEnd(u8, forge.url orelse switch (forge.kind) {
        .github => "https://github.com",
        .gitlab => "https://gitlab.com",
        .forgejo => "https://codeberg.org",
    }, "/");
    const host = hostOf(base);
    const name = try a.print("forge:{t}", .{forge.kind});
    return switch (forge.kind) {
        .github => .{
            .name = name,
            .authorize = try a.print("{s}/login/oauth/authorize", .{base}),
            .token = try a.print("{s}/login/oauth/access_token", .{base}),
            .user = if (forge.url != null) try a.print("{s}/api/v3/user", .{base}) else "https://api.github.com/user",
            .scope = "read:user user:email",
            .host = host,
        },
        .gitlab => .{ .name = name, .authorize = try a.print("{s}/oauth/authorize", .{base}), .token = try a.print("{s}/oauth/token", .{base}), .user = try a.print("{s}/api/v4/user", .{base}), .scope = "read_user", .host = host },
        .forgejo => .{ .name = name, .authorize = try a.print("{s}/login/oauth/authorize", .{base}), .token = try a.print("{s}/login/oauth/access_token", .{base}), .user = try a.print("{s}/api/v1/user", .{base}), .scope = "", .host = host },
    };
}

/// The OpenID Connect provider at `issuer`, from its discovery document
pub fn discover(io: Io, a: std.mem.Allocator, issuer: []const u8) !union(enum) { ok: Provider, failed: []const u8 } {
    const base = std.mem.trimEnd(u8, issuer, "/");
    const body = switch (try call(io, a, .{ .method = .GET, .url = try a.print("{s}/.well-known/openid-configuration", .{base}) })) {
        .body => |b| b,
        .missing => return .{ .failed = try a.print("{s} has no OpenID Connect discovery document", .{base}) },
        .unreachable_ => |why| return .{ .failed = why },
    };
    const authorize = field(a, body, "authorization_endpoint") orelse return .{ .failed = "the discovery document names no authorization_endpoint" };
    const token = field(a, body, "token_endpoint") orelse return .{ .failed = "the discovery document names no token_endpoint" };
    return .{ .ok = .{
        .name = try a.print("oidc:{s}", .{base}),
        .authorize = authorize,
        .token = token,
        .user = field(a, body, "userinfo_endpoint") orelse "",
        .scope = "openid profile email",
        .host = hostOf(base),
        .reauth = true,
    } };
}

/// Where a person is sent to sign in; `back` is `URL/_skein/oauth`. With
/// `again`, the provider is asked to make them sign in again, whatever
/// session it holds.
pub fn authorizeUrl(a: std.mem.Allocator, p: Provider, app: App, back: []const u8, state: []const u8, again: bool) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "{s}?response_type=code&client_id={s}&redirect_uri={s}&state={s}", .{ p.authorize, try query.escaped(a, app.id), try query.escaped(a, back), state });
    if (p.scope.len > 0) try out.print(a, "&scope={s}", .{try query.escaped(a, p.scope)});
    if (again) try out.appendSlice(a, "&prompt=login&max_age=0");
    return out.items;
}

pub const Outcome = union(enum) { user: People.User, failed: []const u8 };

/// Who the person is that came back with `code`; `now` (seconds since the
/// epoch) is when they signed in, unless the ID token says
pub fn exchange(io: Io, a: std.mem.Allocator, p: Provider, app: App, back: []const u8, code: []const u8, now: i64) !Outcome {
    const form = try a.print("grant_type=authorization_code&client_id={s}&client_secret={s}&code={s}&redirect_uri={s}", .{ try query.escaped(a, app.id), try query.escaped(a, app.secret), try query.escaped(a, code), try query.escaped(a, back) });
    const token_body = switch (try call(io, a, .{ .method = .POST, .url = p.token, .form = form })) {
        .body => |b| b,
        .missing => return .{ .failed = "the provider has no token endpoint there" },
        .unreachable_ => |why| return .{ .failed = why },
    };
    const token = field(a, token_body, "access_token") orelse return .{ .failed = "the provider gave no token (the code may have expired: sign in again)" };
    // an ID token's claims, when there is one; else who the token is of
    const claims = if (field(a, token_body, "id_token")) |jwt| try payloadOf(a, jwt) else null;
    var who: []const u8 = claims orelse "";
    if (claims == null or (field(a, who, "email") == null and p.user.len > 0)) {
        if (p.user.len == 0) return .{ .failed = "the provider does not say who signed in" };
        who = switch (try call(io, a, .{ .method = .GET, .url = p.user, .auth = try a.print("Bearer {s}", .{token}) })) {
            .body => |b| b,
            .missing => return .{ .failed = "the provider does not say who signed in" },
            .unreachable_ => |why| return .{ .failed = why },
        };
    }
    const from = claims orelse who;
    const login = field(a, who, "login") orelse field(a, who, "username") orelse field(a, from, "preferred_username") orelse field(a, from, "sub") orelse return .{ .failed = "the provider does not say who signed in" };
    const name = field(a, who, "name") orelse field(a, from, "name") orelse field(a, who, "full_name") orelse login;
    const email = field(a, who, "email") orelse field(a, from, "email") orelse field(a, who, "public_email") orelse try a.print("{s}@users.noreply.{s}", .{ login, p.host });
    const subject = field(a, from, "sub") orelse number(a, who, "id") orelse login;
    const at_unix = if (claims) |c| integer(a, c, "auth_time") orelse now else now;
    return .{ .user = .{ .login = login, .name = name, .email = email, .provider = p.name, .subject = subject, .at = try rfc3339(a, at_unix), .at_unix = at_unix } };
}

/// The claims of a JSON Web Token: its middle part, decoded
fn payloadOf(a: std.mem.Allocator, jwt: []const u8) !?[]const u8 {
    var parts = std.mem.splitScalar(u8, jwt, '.');
    _ = parts.next();
    const middle = parts.next() orelse return null;
    const d = std.base64.url_safe_no_pad.Decoder;
    const n = d.calcSizeForSlice(std.mem.trimEnd(u8, middle, "=")) catch return null;
    const out = try a.alloc(u8, n);
    d.decode(out, std.mem.trimEnd(u8, middle, "=")) catch return null;
    return out;
}

/// `unix` (seconds since the epoch) as RFC 3339, in UTC
pub fn rfc3339(a: std.mem.Allocator, unix: i64) ![]const u8 {
    const es: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(unix, 0)) };
    const day = es.getEpochDay().calculateYearDay();
    const md = day.calculateMonthDay();
    const ds = es.getDaySeconds();
    return a.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{ day.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute() });
}

fn hostOf(url: []const u8) []const u8 {
    const after = if (std.mem.find(u8, url, "://")) |at| url[at + 3 ..] else url;
    return after[0 .. std.mem.findAny(u8, after, "/:") orelse after.len];
}

fn member(a: std.mem.Allocator, body: []const u8, key: []const u8) ?std.json.Value {
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, body, .{}) catch return null;
    if (v != .object) return null;
    return v.object.get(key);
}

/// A string member of the JSON object `body`, when it is one and not empty
fn field(a: std.mem.Allocator, body: []const u8, key: []const u8) ?[]const u8 {
    const x = member(a, body, key) orelse return null;
    return if (x == .string and x.string.len > 0) x.string else null;
}

fn integer(a: std.mem.Allocator, body: []const u8, key: []const u8) ?i64 {
    const x = member(a, body, key) orelse return null;
    return if (x == .integer) x.integer else null;
}

/// A number member, as text: a forge's user id
fn number(a: std.mem.Allocator, body: []const u8, key: []const u8) ?[]const u8 {
    const n = integer(a, body, key) orelse return null;
    return a.print("{d}", .{n}) catch null;
}

test rfc3339 {
    var buf: [64]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    try std.testing.expectEqualStrings("2027-03-01T10:00:00Z", try rfc3339(fba.allocator(), 1803895200));
}

test {
    _ = @import("_test/oauth.zig");
}
