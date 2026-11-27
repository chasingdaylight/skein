//! Signing in to `skein serve` through the project's forge (#281;
//! `--sign-in forge`): OAuth's authorization code flow. A person is sent to
//! the forge's authorize page with a `state`, comes back to
//! `URL/_skein/oauth` with a code, which is exchanged, with the OAuth app's
//! secret, for a token; the token tells who they are. The app's id and
//! secret come from the environment, `SKEIN_OAUTH_CLIENT_ID` and
//! `SKEIN_OAUTH_CLIENT_SECRET`, never the repository.
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
const tool = @import("../forge/tool.zig");
const query = @import("query.zig");

pub const Request = struct {
    method: std.http.Method,
    url: []const u8,
    /// the value of the Authorization header, if any
    auth: ?[]const u8 = null,
    /// a form (`application/x-www-form-urlencoded`)
    form: ?[]const u8 = null,
};

/// How the forge is asked: the forge itself, or recorded answers in tests
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
    return tool.httpsSendAs(io, a, r.method, r.url, headers.items, r.form, "application/x-www-form-urlencoded", host, "the forge");
}

pub const App = struct { id: []const u8, secret: []const u8 };

const Endpoints = struct { authorize: []const u8, token: []const u8, user: []const u8, scope: []const u8 };

fn endpoints(a: std.mem.Allocator, forge: *const Forge) !Endpoints {
    const base = std.mem.trimEnd(u8, forge.url orelse switch (forge.kind) {
        .github => "https://github.com",
        .gitlab => "https://gitlab.com",
        .forgejo => "https://codeberg.org",
    }, "/");
    return switch (forge.kind) {
        .github => .{
            .authorize = try a.print("{s}/login/oauth/authorize", .{base}),
            .token = try a.print("{s}/login/oauth/access_token", .{base}),
            .user = if (forge.url != null) try a.print("{s}/api/v3/user", .{base}) else "https://api.github.com/user",
            .scope = "read:user user:email",
        },
        .gitlab => .{ .authorize = try a.print("{s}/oauth/authorize", .{base}), .token = try a.print("{s}/oauth/token", .{base}), .user = try a.print("{s}/api/v4/user", .{base}), .scope = "read_user" },
        .forgejo => .{ .authorize = try a.print("{s}/login/oauth/authorize", .{base}), .token = try a.print("{s}/login/oauth/access_token", .{base}), .user = try a.print("{s}/api/v1/user", .{base}), .scope = "" },
    };
}

/// Where a person is sent to sign in; `back` is `URL/_skein/oauth`
pub fn authorizeUrl(a: std.mem.Allocator, forge: *const Forge, app: App, back: []const u8, state: []const u8) ![]const u8 {
    const e = try endpoints(a, forge);
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "{s}?response_type=code&client_id={s}&redirect_uri={s}&state={s}", .{ e.authorize, try query.escaped(a, app.id), try query.escaped(a, back), state });
    if (e.scope.len > 0) try out.print(a, "&scope={s}", .{try query.escaped(a, e.scope)});
    return out.items;
}

pub const Outcome = union(enum) { user: People.User, failed: []const u8 };

/// Who the person is that came back with `code`
pub fn exchange(io: Io, a: std.mem.Allocator, forge: *const Forge, app: App, back: []const u8, code: []const u8) !Outcome {
    const e = try endpoints(a, forge);
    const form = try a.print("grant_type=authorization_code&client_id={s}&client_secret={s}&code={s}&redirect_uri={s}", .{ try query.escaped(a, app.id), try query.escaped(a, app.secret), try query.escaped(a, code), try query.escaped(a, back) });
    const token_body = switch (try call(io, a, .{ .method = .POST, .url = e.token, .form = form })) {
        .body => |b| b,
        .missing => return .{ .failed = "the forge has no OAuth token endpoint there" },
        .unreachable_ => |why| return .{ .failed = why },
    };
    const token = field(a, token_body, "access_token") orelse return .{ .failed = "the forge gave no token (the code may have expired: sign in again)" };
    const user_body = switch (try call(io, a, .{ .method = .GET, .url = e.user, .auth = try a.print("Bearer {s}", .{token}) })) {
        .body => |b| b,
        .missing => return .{ .failed = "the forge does not say who signed in" },
        .unreachable_ => |why| return .{ .failed = why },
    };
    const login = field(a, user_body, "login") orelse field(a, user_body, "username") orelse return .{ .failed = "the forge does not say who signed in" };
    const name = field(a, user_body, "name") orelse field(a, user_body, "full_name") orelse login;
    const email = field(a, user_body, "email") orelse field(a, user_body, "public_email") orelse try a.print("{s}@users.noreply.{s}", .{ login, forgeHost(forge) });
    return .{ .user = .{ .login = login, .name = if (name.len > 0) name else login, .email = email } };
}

fn forgeHost(forge: *const Forge) []const u8 {
    const url = forge.url orelse return switch (forge.kind) {
        .github => "github.com",
        .gitlab => "gitlab.com",
        .forgejo => "codeberg.org",
    };
    const after = if (std.mem.find(u8, url, "://")) |at| url[at + 3 ..] else url;
    return after[0 .. std.mem.findAny(u8, after, "/:") orelse after.len];
}

/// A string member of the JSON object `body`, when it is one and not empty
fn field(a: std.mem.Allocator, body: []const u8, key: []const u8) ?[]const u8 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, body, .{}) catch return null;
    if (v != .object) return null;
    const x = v.object.get(key) orelse return null;
    return if (x == .string and x.string.len > 0) x.string else null;
}

test {
    _ = @import("_test/oauth.zig");
}
