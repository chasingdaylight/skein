//! `skein import jama PROJECT --jama-type KEY --type TYPE --to DIR`: an item
//! file in DIR of each item of the type KEY of the Jama Connect project
//! PROJECT (its id), read through Jama's REST API (import/jama.zig), as `import reqif`
//! makes them of a ReqIF file. The instance is `url` in `.skein/jama.toml`,
//! else `JAMA_URL`; the credentials come from the environment (forge/jama.zig).

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const config = @import("../forge/jama_config.zig");
const import_csv = @import("import_csv.zig");
const jama = @import("../forge/jama.zig");
const rows = @import("../import/jama.zig").rows;

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Import) !Workspace.Outcome {
    if (try import_csv.needs(arena, options, "jama")) |problem| return problem;
    const jama_type = options.jama_type orelse return misuse(arena, "import jama: name the Jama item type to take with --jama-type KEY (REQ, say): a Skein type takes one", .{});
    const project = std.fmt.parseInt(i64, options.paths[0], 10) catch return misuse(arena, "import jama: '{s}' is not a project's id: a number, as in Jama's URL of the project", .{options.paths[0]});
    var url: ?[]const u8 = null;
    if (Io.Dir.cwd().openDir(io, options.common.root, .{})) |dir| {
        var root = dir;
        defer root.close(io);
        switch (try config.load(io, arena, root)) {
            .ok => |c| url = c.url,
            .missing => {},
            .failed => |why| return misuse(arena, "{s}", .{why}),
        }
    } else |_| {}
    const client = switch (try jama.connect(io, arena, url)) {
        .found => |c| c,
        .missing => unreachable,
        .failed => |why| return misuse(arena, "import jama: {s}", .{why}),
    };
    const read = try rows(arena, &client, project, jama_type);
    return import_csv.importFrom(io, arena, options, "jama", .{ .given = .{ .name = try arena.print("Jama project {d}", .{project}), .rows = read } });
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
