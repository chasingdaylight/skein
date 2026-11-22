//! Links across repositories, on two git repositories made for the test:
//! `other`, whose items are referred to, and `site`, which refers to them.

// req: links.repositories, network.declared, network.record, network.states, pin.command, pin.refusals, check.other-repositories, check.warnings
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const pin_command = @import("../../commands/pin.zig");
const render_command = @import("../../commands/render.zig");
const review_command = @import("../../commands/review.zig");
const trace_command = @import("../../commands/trace.zig");
const git_program = @import("../../git.zig");
const Network = @import("../Network.zig");

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    site: []const u8,

    fn init(self: *Fixture) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        try self.tmp.dir.createDirPath(testing.io, "other");
        try self.tmp.dir.createDirPath(testing.io, "site");
        const a = self.arena.allocator();
        self.site = try self.tmp.dir.realPathFileAlloc(testing.io, "site", a);
        try self.git("other", &.{ "init", "--quiet" });
        try self.git("site", &.{ "init", "--quiet" });
        try self.write("other/.skein/config.toml",
            \\[[sources]]
            \\path = "spec"
            \\
        );
        try self.write("other/.skein/types/rule.toml", "statuses = [\"draft\", \"removed\"]\ntombstone = \"removed\"\n");
        try self.write("other/spec/lex.md",
            \\# Lexing
            \\
            \\%rule[lex.token] A token.
            \\
            \\%rule[lex.old removed]
            \\
        );
        try self.commit("other");
        try self.write("site/.skein/config.toml",
            \\[[sources]]
            \\path = "pages"
            \\
            \\[[repositories]]
            \\name = "other"
            \\path = "../other"
            \\
        );
        try self.write("site/.skein/types/page.toml", "");
        try self.write("site/.skein/links/explains.toml", "from = [\"page\"]\n");
        try self.write("site/pages/intro.md",
            \\# Intro
            \\
            \\%page[intro explains=other:lex.token] About %[other:lex.token tokens].
            \\
        );
        try self.commit("site");
    }

    fn deinit(self: *Fixture) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn git(self: *Fixture, repo: []const u8, args: []const []const u8) !void {
        var dir = try self.tmp.dir.openDir(testing.io, repo, .{});
        defer dir.close(testing.io);
        if (try git_program.output(testing.io, self.arena.allocator(), dir, args) == null) return error.GitFailed;
    }

    fn write(self: *Fixture, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |parent| try self.tmp.dir.createDirPath(testing.io, parent);
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }

    fn commit(self: *Fixture, repo: []const u8) !void {
        try self.git(repo, &.{ "add", "--all" });
        try self.git(repo, &.{ "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "change" });
    }

    fn check(self: *Fixture, state: Network.State) ![]const u8 {
        return self.checkWith(state, false);
    }

    fn checkWith(self: *Fixture, state: Network.State, offline: bool) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.site, .state = state, .offline = offline })).text;
    }

    fn pin(self: *Fixture, name: ?[]const u8, revision: ?[]const u8) !@import("../../commands/Workspace.zig").Outcome {
        return pin_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.site }, .name = name, .revision = revision });
    }

    /// Declares `other` by its address instead of its path
    fn byUrl(self: *Fixture, url: []const u8) !void {
        const a = self.arena.allocator();
        try self.write("site/.skein/config.toml", try a.print(
            \\[[sources]]
            \\path = "pages"
            \\
            \\[[repositories]]
            \\name = "other"
            \\url = "{s}"
            \\
        , .{url}));
    }

    /// The address of `other`: its path, with forward slashes
    fn otherUrl(self: *Fixture) ![]const u8 {
        const path = try self.tmp.dir.realPathFileAlloc(testing.io, "other", self.arena.allocator());
        std.mem.replaceScalar(u8, path, '\\', '/');
        return path;
    }
};

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "a repository not yet pinned is a warning, not a problem" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const out = try f.check(.recorded);
    try expectContains(out, ".skein/config.toml: warning: repositories: other: it is not pinned yet ('skein pin other'), so 2 references to it are not checked");
    try expectContains(out, "no problems, 1 warning");
}

test "pinned, references are checked against the commit recorded" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const pinned = try f.pin(null, null);
    try testing.expectEqual(.ok, pinned.status);
    try expectContains(pinned.text, "other: pinned at ");
    try expectContains(pinned.text, "(2 items)");
    try expectContains(try f.check(.recorded), "no problems (");

    try f.write("site/pages/more.md",
        \\%page[more explains=other:lex.old] See %[other:lex.new] and %[nowhere:x].
        \\
    );
    const out = try f.check(.recorded);
    try expectContains(out, "pages/more.md:1:1: error: more: explains: the link points to 'other:lex.old', which is removed");
    try expectContains(out, "error: more: the text refers to 'other:lex.new', and other has no such item at ");
    try expectContains(out, "error: more: the text refers to 'nowhere:x', and no repository 'nowhere' is declared");
}

test "the other repository moves on: recorded, current and working states" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.pin(null, null);
    try f.write("other/spec/lex.md",
        \\# Lexing
        \\
        \\%rule[lex.token] A token, changed.
        \\
        \\%rule[lex.old removed]
        \\
        \\%rule[lex.new] New.
        \\
    );
    try f.commit("other");
    try f.write("site/pages/more.md", "%page[more] See %[other:lex.new] and %[other:lex.draft].\n");
    try f.write("other/spec/draft.md", "%rule[lex.draft] Not committed.\n");

    try expectContains(try f.check(.recorded), "'other:lex.new', and other has no such item at ");
    const current = try f.check(.current);
    if (std.mem.find(u8, current, "lex.new'") != null) return error.TestUnexpectedResult;
    try expectContains(current, "'other:lex.draft', and other has no such item at ");
    try expectContains(try f.check(.working), "no problems (");

    // a checkout with changes is not pinned unless the commit is named
    const refused = try f.pin("other", null);
    try testing.expectEqual(.problems, refused.status);
    try expectContains(refused.text, "'../other' has changes that are not committed");
    try f.git("other", &.{ "clean", "--quiet", "--force" });

    const moved = try f.pin("other", null);
    try testing.expectEqual(.ok, moved.status);
    try expectContains(moved.text, ": 1 added, 0 removed, 1 changed");
    try expectContains(moved.text, "other:lex.token is changed; referred to by intro");
    try expectContains(try f.check(.recorded), "'other:lex.draft', and other has no such item");
}

test "pin refuses what it cannot pin" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try expectContains((try f.pin("elsewhere", null)).text, "the project declares no repository 'elsewhere'");
    const unknown = try f.pin("other", "no-such-commit");
    try testing.expectEqual(.problems, unknown.status);
    try expectContains(unknown.text, "there is no commit 'no-such-commit' in '../other'");
}

test "a record that does not match its commit is reported" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.pin(null, null);
    const a = f.arena.allocator();
    const text = try f.tmp.dir.readFileAlloc(testing.io, "site/.skein/network.toml", a, .limited(1 << 16));
    const at = std.mem.find(u8, text, "fingerprint = \"").? + "fingerprint = \"".len;
    const changed = try a.dupe(u8, text);
    changed[at] = if (changed[at] == '0') '1' else '0';
    try f.write("site/.skein/network.toml", changed);
    try expectContains(try f.check(.recorded), ".skein/network.toml: error: other: its items at ");
}

// req: network.reviews
test "a reviewed link into another repository is suspect when its target changes" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.write("site/.skein/links/explains.toml", "from = [\"page\"]\nreview = true\n");
    _ = try f.pin(null, null);
    try expectContains(try f.check(.recorded), "intro: explains: the link to 'other:lex.token' was never reviewed");
    const a = f.arena.allocator();
    const reviewed = try review_command.run(testing.io, a, .{ .common = .{ .root = f.site }, .ids = &.{"intro"} }, .from);
    try expectContains(reviewed.text, "1 link recorded as reviewed");
    try expectContains(try f.check(.recorded), "no problems (");

    try f.write("other/spec/lex.md",
        \\# Lexing
        \\
        \\%rule[lex.token] A token, changed.
        \\
        \\%rule[lex.old removed]
        \\
    );
    try f.commit("other");
    // the record decides: nothing is suspect until the new commit is pinned
    try expectContains(try f.check(.recorded), "no problems (");
    _ = try f.pin(null, null);
    try expectContains(try f.check(.recorded), "intro: explains: 'other:lex.token' has changed since the link was reviewed");
    const traced = try trace_command.run(testing.io, a, .{ .common = .{ .root = f.site }, .id = "intro" });
    try expectContains(traced.text, "other:lex.token (rule, in other at ");
}

// req: render.markdown.references, network.site
test "render: links to another repository's site, and unresolved references marked" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.pin(null, null);
    try f.write("site/pages/more.md", "%page[more] See %[other:lex.token] and %[other:lex.none].\n");
    const a = f.arena.allocator();
    const out_dir = try std.Io.Dir.path.join(a, &.{ f.site, "..", "out" });
    const plain = try render_command.run(testing.io, a, .{ .common = .{ .root = f.site }, .out = out_dir });
    try testing.expectEqual(.ok, plain.status);
    try expectContains(try f.tmp.dir.readFileAlloc(testing.io, "out/pages/more.md", a, .limited(1 << 16)),
        \\See other:lex.token and <span class="skein-unresolved" title="unresolved: other:lex.none">other:lex.none</span>.
    );
    try f.write("site/.skein/config.toml",
        \\[[sources]]
        \\path = "pages"
        \\
        \\[[repositories]]
        \\name = "other"
        \\path = "../other"
        \\site = "https://example.org/other/"
        \\
    );
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = f.site }, .out = out_dir });
    try expectContains(try f.tmp.dir.readFileAlloc(testing.io, "out/pages/more.md", a, .limited(1 << 16)), "See [other:lex.token](https://example.org/other/spec/lex.html#lex.token) and <span");
}

// req: network.fetched, network.offline
test "a repository by url is fetched into a cache, and read offline from it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.byUrl(try f.otherUrl());
    const pinned = try f.pin(null, null);
    try testing.expectEqual(.ok, pinned.status);
    try expectContains(pinned.text, "other: pinned at ");
    try expectContains(try f.check(.recorded), "no problems (");
    try expectContains(try f.checkWith(.recorded, true), "no problems (");

    // the tip moves on: --current fetches it, the record stays
    try f.write("other/spec/more.md", "%rule[lex.more] More.\n");
    try f.commit("other");
    try f.write("site/pages/more.md", "%page[more] See %[other:lex.more].\n");
    try expectContains(try f.check(.recorded), "'other:lex.more', and other has no such item at ");
    try expectContains(try f.check(.current), "no problems (");

    // with the cache gone, offline knows nothing, online fetches again
    try f.tmp.dir.deleteTree(testing.io, "site/.git/skein/repositories");
    try expectContains(try f.checkWith(.recorded, true), "warning: repositories: other: offline, and the commit ");
    try expectContains(try f.check(.recorded), "'other:lex.more', and other has no such item at ");
}

test "a repository by url that cannot be fetched is a warning" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.byUrl(try f.otherUrl());
    _ = try f.pin(null, null);
    const a = f.arena.allocator();
    try f.byUrl(try a.print("{s}-gone", .{try f.otherUrl()}));
    try f.tmp.dir.deleteTree(testing.io, "site/.git/skein/repositories");
    const out = try f.check(.recorded);
    try expectContains(out, "warning: repositories: other: the commit ");
    try expectContains(out, " could not be fetched from ");
    const refused = try f.pin(null, null);
    try testing.expectEqual(.problems, refused.status);
    try expectContains(refused.text, "its tip could not be fetched from ");
}
