//! How `skein serve`'s saves reach git, in a repository made for the test:
//! a change started, saved into, merged; a commit on the branch; and what
//! `skein check` warns of when the way the project chose was not followed.

// req: serve.save, serve.save.warnings
const std = @import("std");
const testing = std.testing;

const Repo = @import("../../commands/_test/Repo.zig");
const Site = @import("../Site.zig");
const changes = @import("../changes.zig");
const check = @import("../../commands/check.zig");
const edit_api = @import("../edit_api.zig");

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

fn post(a: std.mem.Allocator, s: *Site, path: []const u8, body: []const u8) ![]const u8 {
    return (try edit_api.handle(a, s, .post, path, "", body)).body;
}

/// Saves `text` as `spec/lex.md` through the page's request
fn saveFile(a: std.mem.Allocator, s: *Site, repo: *Repo, text: []const u8) ![]const u8 {
    const now = try repo.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 20));
    return post(a, s, "source", try a.print("{{\"file\":\"spec/lex.md\",\"text\":{f},\"hash\":\"{s}\"}}", .{ std.json.fmt(text, .{}), &edit_api.hashOf(now) }));
}

const config = "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// spec:\"\nexpected = true\n";

test "a change: started, saved into, merged; and a commit straight on the branch warned of" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.git(&.{ "config", "user.name", "Tester" });
    try repo.git(&.{ "config", "user.email", "tester@example.invalid" });
    try repo.git(&.{ "config", "commit.gpgsign", "false" });
    try repo.write(".skein/config.toml", config ++ "[serve]\nsave = \"branch\"\n");
    try repo.commit("save through changes");
    const base = (try changes.current(testing.io, a, repo.tmp.dir)).?;

    var s: Site = .init(testing.allocator, testing.io, .{ .common = .{ .root = repo.root } }, repo.tmp.dir);
    defer s.deinit();
    s.start_branch = base;

    // on the branch itself, a save waits for a change
    const refused = try saveFile(a, &s, &repo, "%rule[lex.a] A, again.\n\n%rule[lex.b] B.\n");
    try has(refused, "\"needsChange\":true");
    try has(try post(a, &s, "change", "{\"action\":\"start\",\"name\":\"Not Valid\"}"), "lowercase letters, digits and dashes");
    try has(try post(a, &s, "change", "{\"action\":\"start\",\"name\":\"lex-a\"}"), "started the change lex-a");
    try has(try saveFile(a, &s, &repo, "%rule[lex.a] A, again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has(try repo.gitOutput(&.{ "log", "--format=%s", "-1", "edit/lex-a" }), "Edit spec/lex.md");
    // where the change goes is known to a server started on it
    try testing.expectEqualStrings(base, (try changes.targetOf(testing.io, a, repo.tmp.dir, "lex-a")).?);

    try has(try post(a, &s, "change", "{\"action\":\"merge\",\"name\":\"lex-a\"}"), try a.print("merged the change lex-a into {s}", .{base}));
    try has(try repo.gitOutput(&.{ "log", "--format=%s", "-1" }), "Merge change lex-a");
    try testing.expectEqualStrings(base, (try changes.current(testing.io, a, repo.tmp.dir)).?);
    const clean = try check.run(testing.io, a, .{ .root = repo.root });
    try testing.expect(std.mem.find(u8, clean.text, "warning") == null);

    // a commit straight on the branch
    try repo.write("spec/lex.md", "%rule[lex.a] A.\n\n%rule[lex.b] B.\n");
    try repo.commit("by hand");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "serve: 1 commit changed the sources straight on");

    // a change abandoned
    try has(try post(a, &s, "change", "{\"action\":\"start\",\"name\":\"gone\"}"), "started");
    try has(try post(a, &s, "change", "{\"action\":\"abandon\",\"name\":\"gone\"}"), "abandoned the change gone");
    try testing.expect(std.mem.find(u8, try repo.gitOutput(&.{"branch"}), "edit/gone") == null);
}

test "a save committed on the branch, and a commit by someone not among the editors warned of" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.git(&.{ "config", "user.name", "Tester" });
    try repo.git(&.{ "config", "user.email", "tester@example.invalid" });
    try repo.git(&.{ "config", "commit.gpgsign", "false" });
    try repo.write(".skein/config.toml", config ++ "[serve]\nsave = \"commit\"\neditors = [\"A. Editor\"]\n");
    try repo.commit("commit each save");

    var s: Site = .init(testing.allocator, testing.io, .{ .common = .{ .root = repo.root } }, repo.tmp.dir);
    defer s.deinit();
    s.start_branch = try changes.current(testing.io, a, repo.tmp.dir);

    try has(try saveFile(a, &s, &repo, "%rule[lex.a] A, said again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has(try repo.gitOutput(&.{ "log", "--format=%s", "-1" }), "Edit spec/lex.md");
    // nothing changed: nothing to commit, and no warning
    try has(try saveFile(a, &s, &repo, "%rule[lex.a] A, said again.\n\n%rule[lex.b] B.\n"), "\"warning\":null");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "serve: 1 commit by Tester changed the sources, who is not one of [serve] editors");
}

test "the way of saving is one skein knows" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/config.toml", config ++ "[serve]\nsave = \"push\"\n");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "expected \"pull-request\", \"branch\" or \"commit\"");
}
