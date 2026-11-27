//! How `skein serve`'s saves reach git, in a repository made for the test:
//! changes started, saved into (each in a worktree of its own, two people
//! at once), merged and abandoned; a commit on the branch; an approval;
//! and what `skein check` warns of when the way the project chose was not
//! followed.

// req: serve.save, serve.save.warnings, serve.team
const std = @import("std");
const testing = std.testing;

const People = @import("../People.zig");
const Repo = @import("../../commands/_test/Repo.zig");
const Served = @import("Served.zig");
const changes = @import("../changes.zig");
const check = @import("../../commands/check.zig");
const edit_api = @import("../edit_api.zig");
const worktrees = @import("../worktrees.zig");

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

const ada: People.User = .{ .login = "ada", .name = "Ada Lovelace", .email = "ada@example.invalid" };
const bob: People.User = .{ .login = "bob", .name = "Bob Bobson", .email = "bob@example.invalid" };

/// Saves `text` as `spec/lex.md` where `user` works, read from `dir` for its hash
fn saveFile(a: std.mem.Allocator, s: *Served, user: ?People.User, dir: std.Io.Dir, text: []const u8) ![]const u8 {
    const now = try dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 20));
    return s.ask(a, user, .post, "source", "", try a.print("{{\"file\":\"spec/lex.md\",\"text\":{f},\"hash\":\"{s}\"}}", .{ std.json.fmt(text, .{}), &edit_api.hashOf(now) }));
}

/// The project's directory in the worktree of the change `name`
fn changeDir(a: std.mem.Allocator, repo: *Repo, name: []const u8) !std.Io.Dir {
    const p = (try worktrees.place(testing.io, a, repo.tmp.dir, name)).?;
    return std.Io.Dir.cwd().openDir(testing.io, p.project, .{});
}

const config = "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// spec:\"\nexpected = true\n";

fn setUp(repo: *Repo, serve_config: []const u8) !void {
    try repo.init();
    try repo.git(&.{ "config", "user.name", "Tester" });
    try repo.git(&.{ "config", "user.email", "tester@example.invalid" });
    try repo.git(&.{ "config", "commit.gpgsign", "false" });
    try repo.write(".skein/types/rule.toml", "approval = [\"approved\"]\n");
    try repo.write(".skein/config.toml", try std.mem.concat(repo.arena.allocator(), u8, &.{ config, serve_config }));
    try repo.commit("the way of saving");
}

test "changes in worktrees of their own: two people at once, merged, abandoned" {
    var repo: Repo = undefined;
    try setUp(&repo, "[serve]\nsave = \"branch\"\n");
    defer repo.deinit();
    const a = repo.arena.allocator();
    const base = (try changes.current(testing.io, a, repo.tmp.dir)).?;
    var s: Served = undefined;
    try s.init(repo.root, repo.tmp.dir);
    defer s.deinit();

    // on the branch itself, a save waits for a change
    try has(try saveFile(a, &s, ada, repo.tmp.dir, "%rule[lex.a] A, again.\n\n%rule[lex.b] B.\n"), "\"needsChange\":true");
    try has(try s.ask(a, ada, .post, "change", "", "{\"action\":\"start\",\"name\":\"Not Valid\"}"), "lowercase letters, digits and dashes");
    try has(try s.ask(a, ada, .post, "change", "", "{\"action\":\"start\",\"name\":\"lex-a\"}"), "started the change lex-a");
    try has(try s.ask(a, bob, .post, "change", "", "{\"action\":\"start\",\"name\":\"lex-b\"}"), "started the change lex-b");
    const ada_dir = try changeDir(a, &repo, "lex-a");
    const bob_dir = try changeDir(a, &repo, "lex-b");
    try has(try saveFile(a, &s, ada, ada_dir, "%rule[lex.a] A, again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has(try saveFile(a, &s, bob, bob_dir, "%rule[lex.a] A.\n\n%rule[lex.b] B, again.\n"), "\"warning\":null");
    // each in their own change, as themselves; the checkout that serves is untouched
    try has(try repo.gitOutput(&.{ "log", "--format=%s by %an <%ae>", "-1", "edit/lex-a" }), "Edit spec/lex.md by Ada Lovelace <ada@example.invalid>");
    try has(try repo.gitOutput(&.{ "log", "--format=%s by %an", "-1", "edit/lex-b" }), "Edit spec/lex.md by Bob Bobson");
    try testing.expectEqualStrings(base, (try changes.current(testing.io, a, repo.tmp.dir)).?);
    try has(try repo.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 20)), "%rule[lex.a] A.\n");
    // where a change goes is known to a server started on it
    try testing.expectEqualStrings(base, (try changes.targetOf(testing.io, a, repo.tmp.dir, "lex-a")).?);
    try has(try s.ask(a, ada, .get, "page", "file=spec/lex.md", ""), "\"change\":\"lex-a\"");

    try has(try s.ask(a, ada, .post, "change", "", "{\"action\":\"merge\",\"name\":\"lex-a\"}"), try a.print("merged the change lex-a into {s}", .{base}));
    try has(try repo.gitOutput(&.{ "log", "--format=%s", "-1" }), "Merge change lex-a");
    try has(try repo.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 20)), "A, again.");
    try has(try s.ask(a, ada, .get, "page", "file=spec/lex.md", ""), "\"change\":null");
    const clean = try check.run(testing.io, a, .{ .root = repo.root });
    try testing.expect(std.mem.find(u8, clean.text, "warning") == null);

    try has(try s.ask(a, bob, .post, "change", "", "{\"action\":\"abandon\",\"name\":\"lex-b\"}"), "abandoned the change lex-b");
    try testing.expect(std.mem.find(u8, try repo.gitOutput(&.{"branch"}), "edit/lex-b") == null);
    try testing.expect(std.mem.find(u8, try repo.gitOutput(&.{ "worktree", "list" }), "lex-b") == null);

    // a commit straight on the branch
    try repo.write("spec/lex.md", "%rule[lex.a] A.\n\n%rule[lex.b] B.\n");
    try repo.commit("by hand");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "serve: 1 commit changed the sources straight on");
}

test "a save committed on the branch, an approval, and a commit by someone not among the editors" {
    var repo: Repo = undefined;
    try setUp(&repo, "[serve]\nsave = \"commit\"\neditors = [\"A. Editor\"]\n");
    defer repo.deinit();
    const a = repo.arena.allocator();
    var s: Served = undefined;
    try s.init(repo.root, repo.tmp.dir);
    defer s.deinit();

    try has(try saveFile(a, &s, null, repo.tmp.dir, "%rule[lex.a] A, said again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has(try repo.gitOutput(&.{ "log", "--format=%s", "-1" }), "Edit spec/lex.md");
    // nothing changed: nothing to commit, and no warning
    try has(try saveFile(a, &s, null, repo.tmp.dir, "%rule[lex.a] A, said again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "serve: 1 commit by Tester changed the sources, who is not one of [serve] editors");

    // an approval by the person signed in, committed as them
    try has(try s.ask(a, ada, .post, "approve", "", "{\"id\":\"lex.a\"}"), "\"said\":");
    try has(try repo.gitOutput(&.{ "log", "--format=%s by %an", "-1" }), "Approve lex.a by Ada Lovelace");
    try has(try repo.tmp.dir.readFileAlloc(testing.io, ".skein/approvals/spec/lex.md.toml", a, .limited(1 << 20)), "\"lex.a\".\"ada\"");
    try has(try s.ask(a, ada, .post, "approve", "", "{\"id\":\"lex.none\"}"), "there is no item 'lex.none'");
}

test "the way of saving is one skein knows" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/config.toml", config ++ "[serve]\nsave = \"push\"\n");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "expected \"pull-request\", \"branch\" or \"commit\"");
}
