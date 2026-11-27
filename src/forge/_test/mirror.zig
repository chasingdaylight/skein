//! The full mirror of a forge, written and read; used offline; and
//! published to another forge: with a forge that the test stands in for.

// req: forge.mirror, forge.sync, forge.publish, principle.forge-neutral
// cspell:ignore Fnew
const std = @import("std");
const testing = std.testing;

const Forge = @import("../Forge.zig");
const check_command = @import("../../commands/check.zig");
const fetch = @import("../mirror_fetch.zig");
const git_program = @import("../../git.zig");
const github = @import("../github.zig");
const mirror_command = @import("../../commands/mirror.zig");
const publish_command = @import("../../commands/publish.zig");
const publisher = @import("../mirror_publish.zig");
const pulls = @import("../pulls.zig");
const sync_command = @import("../../commands/sync.zig");

const Mirror = @import("../Mirror.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

/// example/spec as the test has it: #1 an open issue with a label, an
/// assignee, a milestone and a comment; #2 a merged pull request; #3 a closed issue
fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, path: []const u8) anyerror!github.Reply {
    const p = "repos/example/spec/";
    if (!std.mem.startsWith(u8, path, p)) return .missing;
    const rest = path[p.len..];
    const empty: github.Reply = .{ .body = "[]" };
    if (std.mem.startsWith(u8, rest, "issues?state=all")) return if (std.mem.endsWith(u8, rest, "page=1")) .{ .body =
    \\[{"number": 1, "title": "Parse", "state": "open", "user": {"login": "ann"}, "created_at": "2026-11-20T10:00:00Z", "updated_at": "2026-11-21T10:00:00Z",
    \\  "labels": [{"name": "bug"}], "assignees": [{"login": "bob"}], "milestone": {"title": "v1"}, "body": "Line one\nLine two"},
    \\ {"number": 2, "title": "Fix parse", "state": "closed", "pull_request": {"url": "x"}, "user": {"login": "bob"}, "created_at": "2026-11-20T11:00:00Z", "updated_at": "2026-11-21T20:15:00Z", "labels": [], "assignees": [], "milestone": null, "body": null},
    \\ {"number": 3, "title": "Old", "state": "closed", "user": {"login": "ann"}, "created_at": "2026-11-01T10:00:00Z", "updated_at": "2026-11-02T10:00:00Z", "labels": [], "assignees": [], "milestone": null, "body": "Done"}]
    } else empty;
    if (std.mem.startsWith(u8, rest, "milestones?state=all")) return if (std.mem.endsWith(u8, rest, "page=1")) .{ .body =
    \\[{"number": 4, "title": "v1", "description": "First", "state": "open", "due_on": "2027-03-12T07:00:00Z"}]
    } else empty;
    if (std.mem.startsWith(u8, rest, "labels?")) return if (std.mem.endsWith(u8, rest, "page=1")) .{ .body =
    \\[{"name": "bug", "color": "d73a4a", "description": "Broken"}]
    } else empty;
    if (std.mem.startsWith(u8, rest, "issues/comments?")) return if (std.mem.endsWith(u8, rest, "page=1")) .{ .body =
    \\[{"issue_url": "https://api.github.com/repos/example/spec/issues/1", "user": {"login": "carol"}, "created_at": "2026-11-21T09:00:00Z", "body": "Seen"}]
    } else empty;
    if (std.mem.eql(u8, rest, "pulls/2")) return .{ .body =
    \\{"merged_at": "2026-11-21T20:15:00Z", "merge_commit_sha": "m1", "base": {"sha": "b1"}}
    };
    if (std.mem.startsWith(u8, rest, "pulls/2/reviews")) return .{ .body =
    \\[{"user": {"login": "carol"}, "state": "APPROVED"}]
    };
    return .missing;
}

fn project(a: std.mem.Allocator, tmp: anytype) ![]const u8 {
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nrepository = \"example/spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/links/tracked-by.toml", "open = true\n");
    try write(tmp.dir, "spec/lex.md",
        \\%rule[lex.a tracked-by=#1] Fine.
        \\
        \\%rule[lex.b tracked-by=#3] Closed, and required open.
        \\
    );
    return tmp.dir.realPathFileAlloc(testing.io, ".", a);
}

test "the mirror holds all of the forge's data, and stands in for it offline" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try project(a, tmp);
    const saved = fetch.call;
    const saved_pulls = pulls.call;
    defer fetch.call = saved;
    defer pulls.call = saved_pulls;
    fetch.call = fake;
    pulls.call = fake;

    const said = (try mirror_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(said, "mirrored 2 issues, 1 pull or merge request, 1 milestone and 1 label of example/spec into .skein/mirror/ (ignored by git)");
    try testing.expectEqualStrings("*\n", try tmp.dir.readFileAlloc(testing.io, ".skein/mirror/.gitignore", a, .limited(100)));
    const issue = try tmp.dir.readFileAlloc(testing.io, ".skein/mirror/issues/1.toml", a, .limited(1 << 16));
    try expectContains(issue, "labels = [\"bug\"]\nassignees = [\"bob\"]\nmilestone = \"v1\"\n");
    try expectContains(issue, "[[comments]]\nauthor = \"carol\"");
    const pull = try tmp.dir.readFileAlloc(testing.io, ".skein/mirror/pulls/2.toml", a, .limited(1 << 16));
    try expectContains(pull, "merged = \"2026-11-21\"\napprovers = [\"carol\"]\n");

    const data = (try Mirror.load(testing.io, a, tmp.dir)).?;
    try testing.expectEqual(3, data.issues.len);
    try testing.expectEqualStrings("Line one\nLine two", data.issues[0].body);
    try testing.expectEqual(1, data.issues[0].comments.len);
    try testing.expectEqualStrings("Seen", data.issues[0].comments[0].body);
    try testing.expect(data.issues[1].pull);
    try testing.expectEqualStrings("2027-03-12", data.milestones[0].due.?);
    try testing.expectEqualStrings("d73a4a", data.labels[0].color);

    // offline, with nothing cached and no network: what the mirror says is what is known
    const offline = (try check_command.run(testing.io, a, .{ .root = root, .offline = true })).text;
    try expectContains(offline, "lex.b: tracked-by: the link points to '#3', which is closed");
    try expectContains(offline, "skein: 1 problem");

    // sync with nothing to write refreshes the mirror
    const synced = (try sync_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(synced, "nothing to write");
    try expectContains(synced, "mirrored 2 issues");

    // not offline, and a mirror needs a forge
    try testing.expectEqual(.misuse, (try mirror_command.run(testing.io, a, .{ .common = .{ .root = root, .offline = true } })).status);
}

var sent: std.ArrayList([]const u8) = .empty;
var created: u64 = 0;

fn fakeSend(_: std.Io, arena: std.mem.Allocator, _: *const Forge, method: []const u8, path: []const u8, json: []const u8, _: []const u8) anyerror!github.Reply {
    try sent.append(testing.allocator, try std.fmt.allocPrint(testing.allocator, "{s} {s} {s}", .{ method, path, json }));
    if (std.mem.endsWith(u8, path, "/milestones")) return .{ .body = "{\"id\": 7, \"iid\": 1, \"number\": 1}" };
    if (std.mem.endsWith(u8, path, "/labels")) return .{ .body = "{\"id\": 11}" };
    if (std.mem.endsWith(u8, path, "/issues")) {
        created += 1;
        return .{ .body = try arena.print("{{\"iid\": {d}, \"number\": {d}}}", .{ created, created }) };
    }
    return .{ .body = "{}" };
}

test "publishing the mirror to another forge: what is created, and the map of references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    defer {
        for (sent.items) |s| testing.allocator.free(s);
        sent.deinit(testing.allocator);
        sent = .empty;
    }
    const root = try project(a, tmp);
    const saved = fetch.call;
    const saved_pulls = pulls.call;
    const saved_send = publisher.send;
    defer fetch.call = saved;
    defer pulls.call = saved_pulls;
    defer publisher.send = saved_send;
    fetch.call = fake;
    pulls.call = fake;
    publisher.send = fakeSend;
    created = 0;
    _ = try mirror_command.run(testing.io, a, .{ .common = .{ .root = root } });

    // a dry run creates nothing
    const dry = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .to = "gitlab:group/new", .dry_run = true })).text;
    try expectContains(dry, "would create 1 label, 1 milestone, 2 issues and 1 comment on gitlab:group/new; 1 pull or merge request left out");
    try testing.expectEqual(0, sent.items.len);

    const out = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .to = "gitlab:group/new" })).text;
    try expectContains(out, "created 1 label, 1 milestone, 2 issues and 1 comment on gitlab:group/new; 1 pull or merge request left out");
    try expectContains(sent.items[0], "POST projects/group%2Fnew/labels {\"name\":\"bug\",\"color\":\"#d73a4a\"");
    try expectContains(sent.items[1], "POST projects/group%2Fnew/milestones {\"title\":\"v1\",\"description\":\"First\",\"due_date\":\"2027-03-12\"}");
    try expectContains(sent.items[2], "POST projects/group%2Fnew/issues {\"title\":\"Parse\"");
    try expectContains(sent.items[2], "\"labels\":\"bug\",\"milestone_id\":7");
    try expectContains(sent.items[2], "Mirrored from example/spec#1, opened by ann on 2026-11-20T10:00:00Z.");
    try expectContains(sent.items[3], "POST projects/group%2Fnew/issues/1/notes");
    try expectContains(sent.items[5], "PUT projects/group%2Fnew/issues/2 {\"state_event\":\"close\"}");

    const map = try tmp.dir.readFileAlloc(testing.io, ".skein/forge-map.toml", a, .limited(1 << 16));
    try expectContains(map, "\"github:example/spec#1\" = \"gitlab:group/new#1\"\n\"github:example/spec#3\" = \"gitlab:group/new#2\"\n");

    // to GitHub: its paths and fields; each write waits (not here)
    const saved_pause = publisher.pause;
    defer publisher.pause = saved_pause;
    publisher.pause = .zero;
    const first = sent.items.len;
    const hub = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .to = "github:example/moved" })).text;
    try expectContains(hub, "created 1 label, 1 milestone, 2 issues and 1 comment on github:example/moved");
    try expectContains(sent.items[first], "POST repos/example/moved/labels {\"name\":\"bug\",\"color\":\"d73a4a\"");
    try expectContains(sent.items[first + 1], "\"due_on\":\"2027-03-12T12:00:00Z\"}");
    try expectContains(sent.items[first + 2], "\"labels\":[\"bug\"],\"milestone\":1}");
    try expectContains(sent.items[first + 3], "POST repos/example/moved/issues/3/comments");
    try expectContains(sent.items[first + 5], "PATCH repos/example/moved/issues/4 {\"state\":\"closed\"}");

    // to Forgejo: GitHub's paths, its labels and milestone by the ids it gave them
    const third = sent.items.len;
    const jo = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .to = "forgejo:example/moved", .url = "https://codeberg.org" })).text;
    try expectContains(jo, "created 1 label, 1 milestone, 2 issues and 1 comment on forgejo:example/moved");
    try expectContains(sent.items[third], "POST repos/example/moved/labels {\"name\":\"bug\",\"color\":\"#d73a4a\"");
    try expectContains(sent.items[third + 1], "\"due_on\":\"2027-03-12T12:00:00Z\"}");
    try expectContains(sent.items[third + 2], "\"labels\":[11],\"milestone\":7}");
    try expectContains(sent.items[third + 3], "POST repos/example/moved/issues/5/comments");
    try expectContains(sent.items[third + 5], "PATCH repos/example/moved/issues/6 {\"state\":\"closed\"}");

    // a forge that cannot be named, and no mirror
    try testing.expectEqual(.misuse, (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .to = "nowhere" })).status);
}
