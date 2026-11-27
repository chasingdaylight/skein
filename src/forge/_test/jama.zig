//! Jama Connect through its REST API, against answers recorded in the shapes
//! Jama's REST reference gives: a sign-in with an API client, lists in pages,
//! a project imported, and items published, updated and related.

// req: import.jama, forge.jama
// cspell:ignore Vjcm
const std = @import("std");
const testing = std.testing;

const env = @import("../../env.zig");
const import_jama = @import("../../commands/import_jama.zig");
const jama = @import("../jama.zig");
const jama_command = @import("../../commands/jama.zig");

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

/// The requests Jama was sent, one a line: method, URL, auth, payload
var sent: std.ArrayList(u8) = .empty;

fn fake(io: std.Io, arena: std.mem.Allocator, r: jama.Request) anyerror!jama.Reply {
    _ = io;
    try sent.print(testing.allocator, "{t} {s} {s} {s}\n", .{ r.method, r.url, r.auth, r.payload orelse "" });
    const u = r.url;
    const ends = std.mem.endsWith;
    const has = struct {
        fn f(s: []const u8, x: []const u8) bool {
            return std.mem.find(u8, s, x) != null;
        }
    }.f;
    if (ends(u8, u, "/rest/oauth/token")) return .{ .body = "{\"access_token\":\"t0k3n\",\"expires_in\":3600}" };
    if (has(u, "/rest/v1/itemtypes?")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":0,\"resultCount\":3,\"totalResults\":3}},\"data\":[{\"id\":89,\"typeKey\":\"REQ\",\"display\":\"Requirement\"},{\"id\":90,\"typeKey\":\"TC\",\"display\":\"Test Case\"},{\"id\":31,\"typeKey\":\"FLD\",\"display\":\"Folder\"}]}" };
    if (has(u, "/rest/v1/relationshiptypes?")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":0,\"resultCount\":1,\"totalResults\":1}},\"data\":[{\"id\":5,\"name\":\"Verified By\"}]}" };
    // two pages, as Jama gives a long list
    if (has(u, "/rest/v1/items?project=42&startAt=0&")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":0,\"resultCount\":2,\"totalResults\":3}},\"data\":[" ++
        "{\"id\":1001,\"documentKey\":\"RVR-REQ-1\",\"itemType\":89,\"project\":42,\"fields\":{\"name\":\"Stop\",\"description\":\"<p>The rover shall&nbsp;stop within <strong>2 s</strong>.</p>\"}}," ++
        "{\"id\":1002,\"documentKey\":\"RVR-FLD-1\",\"itemType\":31,\"project\":42,\"fields\":{\"name\":\"Requirements\"}}]}" };
    if (has(u, "/rest/v1/items?project=42&startAt=2&")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":2,\"resultCount\":1,\"totalResults\":3}},\"data\":[" ++
        "{\"id\":1003,\"documentKey\":\"RVR-TC-1\",\"itemType\":90,\"project\":42,\"fields\":{\"name\":\"Radio off\",\"description\":\"<p>Switch off the radio.</p>\"}}]}" };
    if (has(u, "/rest/v1/relationships?project=42&")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":0,\"resultCount\":2,\"totalResults\":2}},\"data\":[" ++
        "{\"id\":7,\"fromItem\":1001,\"toItem\":1003,\"relationshipType\":5,\"suspect\":false}," ++
        "{\"id\":8,\"fromItem\":2002,\"toItem\":2001,\"relationshipType\":5,\"suspect\":false}]}" };
    // the publish: r.a's item says otherwise, r.same's as it is, r.gone's still there
    if (ends(u8, u, "/rest/v1/items/2001") and r.method == .GET) return .{ .body = "{\"meta\":{\"status\":\"OK\"},\"data\":{\"id\":2001,\"fields\":{\"name\":\"r.a: An old title.\",\"description\":\"<p>An old text.</p>\"}}}" };
    if (ends(u8, u, "/rest/v1/items/2002") and r.method == .GET) return .{ .body = "{\"meta\":{\"status\":\"OK\"},\"data\":{\"id\":2002,\"fields\":{\"name\":\"r.same: As it is.\",\"description\":\"<p>As it&nbsp;is.</p>\"}}}" };
    if (ends(u8, u, "/rest/v1/items/2003") and r.method == .GET) return .{ .body = "{\"meta\":{\"status\":\"OK\"},\"data\":{\"id\":2003,\"fields\":{\"name\":\"r.gone: Gone.\",\"description\":\"\"}}}" };
    if (ends(u8, u, "/rest/v1/items/2001") and r.method == .PATCH) return .{ .body = "{\"meta\":{\"status\":\"OK\"}}" };
    if (ends(u8, u, "/rest/v1/items") and r.method == .POST) return .{ .body = "{\"meta\":{\"status\":\"Created\",\"location\":\"https://x.jamacloud.com/rest/v1/items/2004\",\"id\":2004}}" };
    if (ends(u8, u, "/rest/v1/relationships") and r.method == .POST) return .{ .body = "{\"meta\":{\"status\":\"Created\",\"id\":9}}" };
    if (has(u, "/rest/v1/relationships?project=7&")) return .{ .body = "{\"meta\":{\"status\":\"OK\",\"pageInfo\":{\"startIndex\":0,\"resultCount\":1,\"totalResults\":1}},\"data\":[" ++
        "{\"id\":8,\"fromItem\":2002,\"toItem\":2001,\"relationshipType\":5,\"suspect\":false}]}" };
    _ = arena;
    return .missing;
}

fn environment(a: std.mem.Allocator, pairs: []const [2][]const u8) !*std.process.Environ.Map {
    const m = try a.create(std.process.Environ.Map);
    m.* = .init(a);
    for (pairs) |p| try m.put(p[0], p[1]);
    return m;
}

test "an API client signs in, and lists come page by page" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer sent.clearAndFree(testing.allocator);
    jama.call = fake;
    env.map = try environment(a, &.{ .{ "JAMA_CLIENT_ID", "id" }, .{ "JAMA_CLIENT_SECRET", "secret" } });
    defer env.map = null;

    const client = (try jama.connect(testing.io, a, "https://x.jamacloud.com/")).found;
    try testing.expectEqualStrings("Bearer t0k3n", client.auth);
    // the client's id and secret by basic authentication, the grant in the body
    try expectContains(sent.items, "POST https://x.jamacloud.com/rest/oauth/token Basic aWQ6c2VjcmV0 grant_type=client_credentials\n");
    const items = (try client.getAll("items?project=42")).found;
    try testing.expectEqual(3, items.len);
    try expectContains(sent.items, "GET https://x.jamacloud.com/rest/v1/items?project=42&startAt=2&maxResults=50 Bearer t0k3n");

    // without credentials, or an instance, it says what to set
    env.map = try environment(a, &.{});
    try expectContains((try jama.connect(testing.io, a, "https://x")).failed, "JAMA_CLIENT_ID and JAMA_CLIENT_SECRET");
    try expectContains((try jama.connect(testing.io, a, null)).failed, "JAMA_URL");
}

test "a Jama project imported: its items, their text as Markdown, its relationships" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer sent.clearAndFree(testing.allocator);
    jama.call = fake;
    env.map = try environment(a, &.{ .{ "JAMA_URL", "https://x.jamacloud.com" }, .{ "JAMA_USERNAME", "me" }, .{ "JAMA_PASSWORD", "pw" } });
    defer env.map = null;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    // a Jama type is to be named, as a Skein type takes one
    try expectContains((try import_jama.run(testing.io, a, .{ .common = .{ .root = root }, .format = .jama, .paths = &.{"42"}, .item_type = "req", .to = "jama" })).text, "--jama-type KEY");

    const out = try import_jama.run(testing.io, a, .{ .common = .{ .root = root }, .format = .jama, .paths = &.{"42"}, .item_type = "req", .to = "jama", .jama_type = "REQ" });
    testing.expectEqual(.ok, out.status) catch |e| {
        std.debug.print("{s}", .{out.text});
        return e;
    };
    try expectContains(out.text, "imported 1 item of type req into jama");
    // basic authentication, as the environment gives it
    try expectContains(sent.items, "Basic bWU6cHc=");
    const req = try tmp.dir.readFileAlloc(testing.io, "jama/RVR-REQ-1.md", a, .limited(1 << 16));
    try expectContains(req, "id = \"RVR-REQ-1\"\n");
    try expectContains(req, "title = \"Stop\"\n");
    try expectContains(req, "jama = \"1001\"\n");
    try expectContains(req, "verified-by = \"RVR-TC-1\"\n");
    try expectContains(req, "+++\n\nThe rover shall stop within **2 s**.\n");
    // of the type taken only
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "jama/RVR-FLD-1.md", .{}));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "jama/RVR-TC-1.md", .{}));

    // the test cases, to a type of their own: the link above now has its target
    try testing.expectEqual(.ok, (try import_jama.run(testing.io, a, .{ .common = .{ .root = root }, .format = .jama, .paths = &.{"42"}, .item_type = "tc", .to = "tests", .jama_type = "TC" })).status);
    _ = try tmp.dir.readFileAlloc(testing.io, "tests/RVR-TC-1.md", a, .limited(1 << 16));

    const bad = try import_jama.run(testing.io, a, .{ .common = .{ .root = root }, .format = .jama, .paths = &.{"rover"}, .item_type = "req", .to = "x", .jama_type = "REQ" });
    try expectContains(bad.text, "'rover' is not a project's id");
}

test "items published to Jama: created, brought back, related, and what Jama alone has reported" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer sent.clearAndFree(testing.allocator);
    jama.call = fake;
    env.map = try environment(a, &.{ .{ "JAMA_USERNAME", "me" }, .{ "JAMA_PASSWORD", "pw" } });
    defer env.map = null;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(dir, ".skein/types/req.toml", "statuses = [\"draft\", \"removed\"]\ntombstone = \"removed\"\n");
    try write(dir, ".skein/types/note.toml", "");
    try write(dir, ".skein/links/refines.toml", "from = [\"req\"]\nto = [\"req\"]\n");
    try write(dir, "spec/all.md",
        \\%req[r.a] A new title.
        \\
        \\%req[r.new refines=r.a] Not yet in Jama.
        \\
        \\%req[r.same] As it is.
        \\
        \\%req[r.gone removed] Gone.
        \\
        \\%note[n.1] Not published.
        \\
    );
    try write(dir, ".skein/jama.toml", "url = \"https://x.jamacloud.com\"\nproject = 7\nparent = 300\n[types]\nreq = 89\n[links]\nrefines = 5\n");
    try write(dir, ".skein/jama-map.toml", "\"r.a\" = 2001\n\"r.same\" = 2002\n\"r.gone\" = 2003\n");

    const dry = try jama_command.run(testing.io, a, .{ .common = .{ .root = root }, .dry_run = true });
    try expectContains(dry.text, "would be: 1 created, 1 updated, 1 removed here, 1 as they are, 0 relationships added; nothing written");
    try testing.expect(std.mem.find(u8, sent.items, "PATCH") == null and std.mem.find(u8, sent.items, "POST") == null);

    const out = try jama_command.run(testing.io, a, .{ .common = .{ .root = root } });
    try testing.expectEqual(.ok, out.status);
    try expectContains(out.text, "r.a: updated (Jama item 2001, which said otherwise)\n");
    try expectContains(out.text, "r.new: created (Jama item 2004)\n");
    try expectContains(out.text, "r.gone: removed here; Jama item 2003 is left for its owners to delete\n");
    try expectContains(out.text, "r.new refines r.a: relationship added\n");
    try expectContains(out.text, "r.same refines r.a: in Jama only; link it here, or take it out of Jama\n");
    try expectContains(out.text, "skein: 1 created, 1 updated, 1 removed here, 1 as they are, 1 relationship added; the map is in .skein/jama-map.toml\n");
    // the requests, as Jama's reference gives them
    try expectContains(sent.items, "PATCH https://x.jamacloud.com/rest/v1/items/2001 Basic bWU6cHc= [{\"op\":\"replace\",\"path\":\"/fields/name\",\"value\":\"r.a: A new title.\"},{\"op\":\"replace\",\"path\":\"/fields/description\",\"value\":\"<p>A new title.</p>\"}]\n");
    try expectContains(sent.items, "POST https://x.jamacloud.com/rest/v1/items Basic bWU6cHc= {\"project\":7,\"itemType\":89,\"location\":{\"parent\":{\"item\":300}},\"fields\":{\"name\":\"r.new: Not yet in Jama.\",\"description\":\"<p>Not yet in Jama.</p>\"}}\n");
    try expectContains(sent.items, "POST https://x.jamacloud.com/rest/v1/relationships Basic bWU6cHc= {\"fromItem\":2004,\"toItem\":2001,\"relationshipType\":5}\n");
    try testing.expect(std.mem.find(u8, sent.items, "n.1") == null);
    const map = try dir.readFileAlloc(testing.io, ".skein/jama-map.toml", a, .limited(1 << 16));
    try expectContains(map, "\"r.new\" = 2004\n");

    // no configuration: it says where it goes
    try dir.deleteFile(testing.io, ".skein/jama.toml");
    try expectContains((try jama_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "in .skein/jama.toml");
}
