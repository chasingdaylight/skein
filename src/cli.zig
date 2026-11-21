//! The command line: which command the arguments ask for.

const std = @import("std");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  help       Show this text
    \\  version    Show skein's version
    \\
;

pub const Command = union(enum) {
    help,
    version,
    /// the first argument, which names no command
    unknown: []const u8,
};

/// The command `args` (without the program's name) ask for; help when
/// there are none.
pub fn parse(args: []const []const u8) Command {
    if (args.len == 0) return .help;
    const name = args[0];
    if (eql(name, "help") or eql(name, "--help") or eql(name, "-h")) return .help;
    if (eql(name, "version") or eql(name, "--version")) return .version;
    return .{ .unknown = name };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "no arguments ask for help" {
    try std.testing.expectEqual(Command.help, parse(&.{}));
}

test "help and version, as commands and as options" {
    try std.testing.expectEqual(Command.help, parse(&.{"help"}));
    try std.testing.expectEqual(Command.help, parse(&.{"--help"}));
    try std.testing.expectEqual(Command.help, parse(&.{"-h"}));
    try std.testing.expectEqual(Command.version, parse(&.{"version"}));
    try std.testing.expectEqual(Command.version, parse(&.{"--version"}));
}

test "an unknown command is reported by name" {
    try std.testing.expectEqualStrings("frobnicate", parse(&.{ "frobnicate", "x" }).unknown);
}
