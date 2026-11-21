const std = @import("std");

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
        .unknown => |name| {
            const msg = try arena.print("skein: unknown command '{s}'\n\n{s}", .{ name, cli.usage });
            try stdio.stderr().writeStreamingAll(io, msg);
            std.process.exit(2);
        },
    }
}
