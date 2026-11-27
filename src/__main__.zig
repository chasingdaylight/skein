const std = @import("std");

const approve = @import("commands/approve.zig");
const check = @import("commands/check.zig");
const diff = @import("commands/diff.zig");
const exporter = @import("commands/export.zig");
const import_csv = @import("commands/import_csv.zig");
const import_gitlab = @import("commands/import_gitlab.zig");
const import_reqif = @import("import/reqif.zig");
const lsp = @import("commands/lsp.zig");
const mcp = @import("commands/mcp.zig");
const agents = @import("commands/agents.zig");
const import_doorstop = @import("commands/import_doorstop.zig");
const coverage = @import("commands/coverage.zig");
const load = @import("commands/load.zig");
const schedule = @import("commands/schedule.zig");
const level = @import("commands/level.zig");
const gitlab_publish = @import("commands/gitlab_publish.zig");
const time_spent = @import("commands/time.zig");
const overlay = @import("commands/overlay.zig");
const apply = @import("commands/apply.zig");
const mirror = @import("commands/mirror.zig");
const publish = @import("commands/publish.zig");
const rewrite_refs = @import("commands/rewrite_refs.zig");
const sync = @import("commands/sync.zig");
const cli = @import("cli.zig");
const move = @import("commands/move.zig");
const new = @import("commands/new.zig");
const link = @import("commands/link.zig");
const baseline = @import("commands/baseline.zig");
const examples = @import("commands/examples.zig");
const template = @import("commands/template.zig");
const init_command = @import("commands/init.zig");
const pin = @import("commands/pin.zig");
const render = @import("commands/render.zig");
const result = @import("commands/result.zig");
const review = @import("commands/review.zig");
const trace = @import("commands/trace.zig");
const env = @import("env.zig");
const stdio = @import("stdio.zig");
const Workspace = @import("commands/Workspace.zig");

const version = @import("build_options").version;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    env.map = init.environ_map;

    const outcome: Workspace.Outcome = switch (try cli.parse(arena, argv[1..])) {
        .help => .{ .text = cli.usage },
        .version => .{ .text = version ++ "\n" },
        .check => |options| try check.runFormatted(io, arena, options),
        .review => |options| try review.run(io, arena, options, .from),
        .clear => |options| try review.run(io, arena, options, .to),
        .approve => |options| try approve.run(io, arena, options),
        .result => |options| try result.run(io, arena, options),
        .diff => |options| try diff.run(io, arena, options),
        .exporting => |options| try exporter.run(io, arena, options),
        .render => |options| try render.run(io, arena, options),
        .move => |options| try move.run(io, arena, options),
        .new => |options| try new.run(io, arena, options),
        .link => |options| try link.run(io, arena, options),
        .baseline => |options| try baseline.run(io, arena, options),
        .pin => |options| try pin.run(io, arena, options),
        .examples => |options| try examples.run(io, arena, options),
        .template => |options| try template.run(io, arena, options),
        .init => |options| try init_command.run(io, arena, options),
        .lsp => std.process.exit(try lsp.serve(io, init.gpa, version)),
        .mcp => |root| std.process.exit(try mcp.serve(io, init.gpa, version, root)),
        .agents => |options| try agents.run(io, arena, options),
        .import => |options| switch (options.format) {
            .doorstop => try import_doorstop.run(io, arena, options),
            .csv => try import_csv.run(io, arena, options),
            .reqif => try import_csv.importRows(io, arena, options, "reqif", import_reqif.rows),
            .@"gitlab-requirements" => try import_gitlab.run(io, arena, options),
        },
        .trace => |options| try trace.run(io, arena, options),
        .coverage => |options| try coverage.run(io, arena, options),
        .load => |options| try load.run(io, arena, options),
        .schedule => |options| try schedule.run(io, arena, options),
        .level => |options| try level.run(io, arena, options),
        .gitlab_requirements => |options| try gitlab_publish.run(io, arena, options),
        .time => |options| try time_spent.run(io, arena, options),
        .overlay => |options| try overlay.run(io, arena, options),
        .apply => |options| try apply.run(io, arena, options),
        .mirror => |options| try mirror.run(io, arena, options),
        .sync => |options| try sync.run(io, arena, options),
        .publish => |options| try publish.run(io, arena, options),
        .rewrite_refs => |options| try rewrite_refs.run(io, arena, options),
        .unknown => |name| .{
            .text = try arena.print("skein: unknown command '{s}'\n\n{s}", .{ name, cli.usage }),
            .status = .misuse,
        },
        .misuse => |problem| .{
            .text = try arena.print("skein: {s}\n\n{s}", .{ problem, cli.usage }),
            .status = .misuse,
        },
    };
    if (outcome.status == .ok) return stdio.stdout().writeStreamingAll(io, outcome.text);
    if (outcome.to_stdout) {
        try stdio.stdout().writeStreamingAll(io, outcome.text);
        std.process.exit(@backingInt(outcome.status));
    }
    try stdio.stderr().writeStreamingAll(io, outcome.text);
    std.process.exit(@backingInt(outcome.status));
}
