const std = @import("std");

const check = @import("commands/check.zig");
const cli = @import("cli.zig");
const stdio = @import("stdio.zig");

const version = @import("build_options").version;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

    switch (cli.parse(argv[1..])) {
        .help => try stdio.stdout().writeStreamingAll(io, cli.usage),
        .version => try stdio.stdout().writeStreamingAll(io, version ++ "\n"),
        .check => |options| {
            const outcome = try check.run(io, arena, options);
            if (outcome.ok) return stdio.stdout().writeStreamingAll(io, outcome.text);
            try stdio.stderr().writeStreamingAll(io, outcome.text);
            std.process.exit(1);
        },
        .unknown => |name| {
            const msg = try arena.print("skein: unknown command '{s}'\n\n{s}", .{ name, cli.usage });
            try stdio.stderr().writeStreamingAll(io, msg);
            std.process.exit(2);
        },
        .misuse => |problem| {
            const msg = try arena.print("skein: {s}\n\n{s}", .{ problem, cli.usage });
            try stdio.stderr().writeStreamingAll(io, msg);
            std.process.exit(2);
        },
    }
}
