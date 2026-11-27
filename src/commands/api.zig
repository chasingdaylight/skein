//! `skein api GET|POST PATH [QUERY]`: one of `skein serve`'s editing
//! requests (serve/edit_api.zig), its body read from standard input and its
//! answer, JSON, written to standard output. It is how the static site's
//! edit mode asks them: skein built for WebAssembly, run in the page over
//! the project's files (#282). Without git there, a save is written, not
//! committed.

const std = @import("std");
const Io = std.Io;

const Context = @import("../serve/Context.zig");
const People = @import("../serve/People.zig");
const Project = @import("../Project.zig");
const Site = @import("../serve/Site.zig");
const Sites = @import("../serve/Sites.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const edit_api = @import("../serve/edit_api.zig");
const stdio = @import("../stdio.zig");

pub fn run(io: Io, gpa: std.mem.Allocator, arena: std.mem.Allocator, options: cli.Api) !Workspace.Outcome {
    const root_path = (Project.findRoot(io, arena, options.common.root) catch null) orelse return .{
        .text = try arena.print("skein: no project here: no '{s}' directory in '{s}' or above it\n", .{ Project.dir_name, options.common.root }),
        .status = .misuse,
    };
    var root = try Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true });
    defer root.close(io);
    var body: []const u8 = "";
    if (options.method == .post) {
        var buf: [16 * 1024]u8 = undefined;
        var reader = stdio.stdin().readerStreaming(io, &buf);
        body = reader.interface.allocRemaining(arena, .limited(1 << 26)) catch "";
    }
    var o: cli.Serve = .{ .common = options.common };
    o.common.root = root_path;
    var site: Site = .init(gpa, io, o, root);
    defer site.deinit();
    var people: People = .init(gpa);
    defer people.deinit();
    var sites: Sites = .init(gpa, io);
    defer sites.deinit();
    var c = try Context.of(arena, &site, &people, &sites, null);
    const answer = try edit_api.handle(arena, &c, options.method, options.path, options.query, body);
    return .{ .text = try arena.print("{s}\n", .{answer.body}) };
}
