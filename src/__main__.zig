const std = @import("std");

const approve = @import("commands/approve.zig");
const check = @import("commands/check.zig");
const diff = @import("commands/diff.zig");
const exporter = @import("commands/export.zig");
const import_csv = @import("commands/import_csv.zig");
const lsp = @import("commands/lsp.zig");
const import_doorstop = @import("commands/import_doorstop.zig");
const coverage = @import("commands/coverage.zig");
const cli = @import("cli.zig");
const move = @import("commands/move.zig");
const new = @import("commands/new.zig");
const link = @import("commands/link.zig");
const baseline = @import("commands/baseline.zig");
const examples = @import("commands/examples.zig");
const pin = @import("commands/pin.zig");
const render = @import("commands/render.zig");
const result = @import("commands/result.zig");
const review = @import("commands/review.zig");
const trace = @import("commands/trace.zig");
const stdio = @import("stdio.zig");
const Workspace = @import("commands/Workspace.zig");

const version = @import("build_options").version;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

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
        .lsp => std.process.exit(try lsp.serve(io, init.gpa, version)),
        .import => |options| switch (options.format) {
            .doorstop => try import_doorstop.run(io, arena, options),
            .csv => try import_csv.run(io, arena, options),
        },
        .trace => |options| try trace.run(io, arena, options),
        .coverage => |options| try coverage.run(io, arena, options),
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
