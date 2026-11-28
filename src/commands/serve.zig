//! `skein serve`: the site of the project, rendered from the checkout as
//! the files change, with pages that load again when they do, and edit
//! them (serve/). On this computer alone by default; for a team, on
//! another address with people signed in (`--listen`, `--url`, `--sign-in`).

const std = @import("std");
const Io = std.Io;

const People = @import("../serve/People.zig");
const Project = @import("../Project.zig");
const Server = @import("../serve/Server.zig");
const Site = @import("../serve/Site.zig");
const Sites = @import("../serve/Sites.zig");
const Workspace = @import("Workspace.zig");
const changes = @import("../serve/changes.zig");
const cli = @import("../cli.zig");
const env = @import("../env.zig");
const oauth = @import("../serve/oauth.zig");
const sign_in = @import("../serve/sign_in.zig");
const stdio = @import("../stdio.zig");

/// How many requests are answered at once: a browser opens several
/// connections, some of which send nothing for a while
const workers = 8;

/// Serves until the process is stopped; the exit code when it cannot start
pub fn serve(io: Io, gpa: std.mem.Allocator, options: cli.Serve) !u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const root_path = (Project.findRoot(io, a, options.common.root) catch null) orelse {
        try say(io, try a.print("skein: no project here: no '{s}' directory in '{s}' or above it\n", .{ Project.dir_name, options.common.root }));
        return 2;
    };
    var root = try Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true });
    defer root.close(io);
    var site: Site = .init(gpa, io, options, root);
    defer site.deinit();
    site.start_branch = try changes.current(io, a, root);
    try site.refresh();

    const setup = switch (try setUp(io, a, options)) {
        .ok => |s| s,
        .failed => |why| {
            try say(io, try a.print("skein: {s}\n", .{why}));
            return 2;
        },
    };
    var server: Server = .{
        .io = io,
        .gpa = gpa,
        .main = &site,
        .people = .init(gpa),
        .sites = .init(gpa, io),
        .setup = setup,
        .public_host = if (options.url) |u| hostOf(u) else null,
    };
    defer server.people.deinit();
    server.people.limits.idle = @as(i64, options.session_hours) * 3600;
    server.people.limits.longest = @as(i64, options.session_days) * 24 * 3600;
    defer server.sites.deinit();

    const address = try Io.net.IpAddress.parse(options.listen, options.port);
    var listener = address.listen(io, .{ .reuse_address = true }) catch |e| {
        try say(io, try a.print("skein: cannot serve on {s}:{d} ({t}); give another --port\n", .{ options.listen, options.port, e }));
        return 2;
    };
    defer listener.deinit(io);
    const at = options.url orelse try a.print("http://{s}:{d}/", .{ options.listen, options.port });
    try say(io, try a.print("skein: serving {s} at {s} until stopped (Ctrl+C){s}{s}\n", .{
        if (site.name.len > 0) site.name else root_path,
        at,
        switch (options.sign_in) {
            .none => "",
            .proxy => "; people sign in through the proxy",
            .forge => "; people sign in through the forge",
            .oidc => "; people sign in through the OpenID Connect provider",
        },
        if (site.failed != null) "; it cannot be rendered yet: see the page" else "",
    }));

    var group: Io.Group = .init;
    defer group.cancel(io);
    var started: usize = 0;
    while (started < workers) : (started += 1) group.concurrent(io, Server.work, .{ &server, &listener }) catch break;
    // with no concurrency to be had, one at a time here
    if (started == 0) try server.work(&listener);
    try group.await(io);
    return 0;
}

/// How people sign in, from the options, the project's forge and the
/// environment; or why it cannot be set up
fn setUp(io: Io, a: std.mem.Allocator, options: cli.Serve) !union(enum) { ok: sign_in.Setup, failed: []const u8 } {
    var setup: sign_in.Setup = .{ .mode = options.sign_in, .url = options.url orelse "", .user_header = options.user_header, .email_header = options.email_header };
    switch (options.sign_in) {
        .none => {},
        .proxy => {
            var proxies: std.ArrayList(Io.net.IpAddress) = .empty;
            const given: []const []const u8 = if (options.proxies.len > 0) options.proxies else &.{ "127.0.0.1", "::1" };
            for (given) |p| try proxies.append(a, Io.net.IpAddress.parse(p, 0) catch return .{ .failed = try a.print("serve --proxy: '{s}' is not an IP address", .{p}) });
            setup.proxies = proxies.items;
        },
        .forge, .oidc => {
            const id = env.get("SKEIN_OAUTH_CLIENT_ID") orelse "";
            const secret = env.get("SKEIN_OAUTH_CLIENT_SECRET") orelse "";
            if (id.len == 0 or secret.len == 0) return .{ .failed = "serve --sign-in: set SKEIN_OAUTH_CLIENT_ID and SKEIN_OAUTH_CLIENT_SECRET, the id and secret of an OAuth or OpenID Connect app made with the provider, whose callback is URL/_skein/oauth" };
            setup.app = .{ .id = id, .secret = secret };
            if (options.sign_in == .oidc) {
                setup.provider = switch (try oauth.discover(io, a, options.issuer.?)) {
                    .ok => |p| p,
                    .failed => |why| return .{ .failed = try a.print("serve --issuer: {s}", .{why}) },
                };
            } else {
                var ws = switch (try Workspace.open(io, a, options.common)) {
                    .ok => |w| w,
                    .failed => |o| return .{ .failed = std.mem.trimEnd(u8, o.text, "\n") },
                };
                defer ws.close();
                const forge = ws.project.forge orelse return .{ .failed = "serve --sign-in forge: the project names no forge ([forge] in .skein/config.toml)" };
                setup.provider = try oauth.ofForge(a, &forge);
            }
        },
    }
    // an approval that must be signed with a sign-in again needs a provider that can ask for it
    var ws = switch (try Workspace.open(io, a, options.common)) {
        .ok => |w| w,
        .failed => return .{ .ok = setup },
    };
    defer ws.close();
    if (ws.project.workflow.approve_sign_in == .again and options.sign_in != .none and !(setup.provider != null and setup.provider.?.reauth)) {
        return .{ .failed = "the project asks for a sign-in again to approve ([serve] approve_sign_in = \"again\"), which needs --sign-in oidc: a provider that can be asked for it (GitLab and most single sign-on are OpenID Connect providers)" };
    }
    return .{ .ok = setup };
}

/// `reqs.example.com` of `https://reqs.example.com/`, with its port when it has one
fn hostOf(url: []const u8) []const u8 {
    const after = if (std.mem.find(u8, url, "://")) |at| url[at + 3 ..] else url;
    return after[0 .. std.mem.findScalar(u8, after, '/') orelse after.len];
}

fn say(io: Io, text: []const u8) !void {
    try stdio.stderr().writeStreamingAll(io, text);
}

test hostOf {
    try std.testing.expectEqualStrings("reqs.example.com", hostOf("https://reqs.example.com/"));
    try std.testing.expectEqualStrings("10.0.0.5:8080", hostOf("http://10.0.0.5:8080"));
}

test {
    _ = People;
    _ = Sites;
}
