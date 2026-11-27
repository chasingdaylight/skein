//! GitLab's requirements kept to the items through its GraphQL API, against
//! answers recorded in the shapes GitLab's reference gives: one created, one
//! brought back to its item, one archived, and the map kept.

// req: forge.gitlab-requirements-api
const std = @import("std");
const testing = std.testing;

const Forge = @import("../Forge.zig");
const github = @import("../github.zig");
const publish_command = @import("../../commands/gitlab_publish.zig");
const publish = @import("../gitlab_publish.zig");

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

/// The requests GitLab was sent, joined
var sent: std.ArrayList(u8) = .empty;

fn fake(io: std.Io, arena: std.mem.Allocator, forge: *const Forge, body: []const u8, body_path: []const u8) anyerror!github.Reply {
    _ = io;
    _ = forge;
    _ = body_path;
    try sent.appendSlice(testing.allocator, body);
    try sent.append(testing.allocator, '\n');
    if (std.mem.find(u8, body, "workItemTypes") != null) return .{ .body = "{\"data\":{\"namespace\":{\"workItemTypes\":{\"nodes\":[{\"id\":\"gid://gitlab/WorkItems::Type/1\",\"name\":\"Issue\"},{\"id\":\"gid://gitlab/WorkItems::Type/9\",\"name\":\"Requirement\"}]}}}}" };
    if (std.mem.find(u8, body, "workItemCreate") != null) return .{ .body = "{\"data\":{\"workItemCreate\":{\"workItem\":{\"iid\":\"4\"},\"errors\":[]}}}" };
    if (std.mem.find(u8, body, "workItemUpdate") != null) return .{ .body = "{\"data\":{\"workItemUpdate\":{\"workItem\":{\"iid\":\"1\"},\"errors\":[]}}}" };
    if (std.mem.find(u8, body, "\"i\":\"1\"") != null) return .{ .body = "{\"data\":{\"namespace\":{\"workItem\":{\"id\":\"gid://gitlab/WorkItem/101\",\"title\":\"r.a: An old title.\",\"state\":\"OPEN\",\"widgets\":[{},{\"description\":\"An old text.\"}]}}}}" };
    if (std.mem.find(u8, body, "\"i\":\"2\"") != null) return .{ .body = "{\"data\":{\"namespace\":{\"workItem\":{\"id\":\"gid://gitlab/WorkItem/102\",\"title\":\"r.same: As it is.\",\"state\":\"OPEN\",\"widgets\":[{\"description\":\"As it is.\\n\"}]}}}}" };
    if (std.mem.find(u8, body, "\"i\":\"3\"") != null) return .{ .body = "{\"data\":{\"namespace\":{\"workItem\":{\"id\":\"gid://gitlab/WorkItem/103\",\"title\":\"r.gone: Gone.\",\"state\":\"OPEN\",\"widgets\":[]}}}}" };
    _ = arena;
    return .{ .body = "{\"errors\":[{\"message\":\"unexpected request\"}]}" };
}

test "requirements created, updated and archived through the API, and the map kept" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nkind = \"gitlab\"\nrepository = \"group/project\"\n");
    try write(dir, ".skein/types/req.toml", "statuses = [\"draft\", \"removed\"]\ntombstone = \"removed\"\n");
    try write(dir, "spec/all.md",
        \\%req[r.a] A new title.
        \\
        \\%req[r.new] Not yet in GitLab.
        \\
        \\%req[r.same] As it is.
        \\
        \\%req[r.gone removed] Gone.
        \\
    );
    try write(dir, ".skein/gitlab-requirements.toml", "\"r.a\" = 1\n\"r.same\" = 2\n\"r.gone\" = 3\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);

    publish.call = fake;
    defer publish.call = @import("../gitlab.zig").graphql;
    defer sent.deinit(testing.allocator);

    // a dry run asks, and changes nothing
    const dry = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root }, .dry_run = true })).text;
    try expectContains(dry, "r.a: updated (requirement 1)\nr.new: created\nr.gone: archived (requirement 3)\n");
    try expectContains(dry, "would be: 1 created, 1 updated, 0 reopened, 1 archived, 1 as they are; nothing written");
    try testing.expect(std.mem.find(u8, sent.items, "mutation") == null);
    sent.clearRetainingCapacity();

    const done = (try publish_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(done, "r.new: created (requirement 4)\n");
    try expectContains(done, "1 created, 1 updated, 0 reopened, 1 archived, 1 as they are; the map is in .skein/gitlab-requirements.toml");
    try expectContains(sent.items, "\"in\":{\"id\":\"gid://gitlab/WorkItem/101\",\"title\":\"r.a: A new title.\",\"descriptionWidget\":{\"description\":\"A new title.\"}}");
    try expectContains(sent.items, "\"in\":{\"id\":\"gid://gitlab/WorkItem/103\",\"stateEvent\":\"CLOSE\"}");
    try expectContains(sent.items, "\"ty\":\"gid://gitlab/WorkItems::Type/9\"");
    try expectContains(try dir.readFileAlloc(testing.io, ".skein/gitlab-requirements.toml", a, .limited(1 << 16)), "\"r.new\" = 4\n");

    // the forge must be GitLab
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try testing.expectEqual(.misuse, (try publish_command.run(testing.io, a, .{ .common = .{ .root = root } })).status);
}
