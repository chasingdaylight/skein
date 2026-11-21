//! The command line: which command the arguments ask for.

const std = @import("std");

pub const usage =
    \\Usage: skein <command> [options]
    \\
    \\Commands:
    \\  check      Check the project: its configuration and schema
    \\  help       Show this text
    \\  version    Show skein's version
    \\
    \\Options:
    \\  --root DIR   The project, or a directory inside it (default: here)
    \\
;

pub const Command = union(enum) {
    help,
    version,
    check: Common,
    /// the first argument, which names no command
    unknown: []const u8,
    /// what is wrong with the arguments of a command
    misuse: []const u8,
};

/// The options every command that works on a project takes
pub const Common = struct {
    /// where to look for the project from
    root: []const u8 = ".",
};

/// The command `args` (without the program's name) ask for; help when
/// there are none.
pub fn parse(args: []const []const u8) Command {
    if (args.len == 0) return .help;
    const name = args[0];
    if (eql(name, "help") or eql(name, "--help") or eql(name, "-h")) return .help;
    if (eql(name, "version") or eql(name, "--version")) return .version;
    if (eql(name, "check")) {
        var common: Common = .{};
        if (parseCommon(args[1..], &common)) |problem| return .{ .misuse = problem };
        return .{ .check = common };
    }
    return .{ .unknown = name };
}

/// Fills `common` from `args`; what is wrong with them, if anything
fn parseCommon(args: []const []const u8, common: *Common) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (eql(args[i], "--root")) {
            i += 1;
            if (i == args.len) return "--root needs a directory";
            common.root = args[i];
        } else return "unknown option or argument";
    }
    return null;
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

test "check takes the project's place" {
    try std.testing.expectEqualStrings(".", parse(&.{"check"}).check.root);
    try std.testing.expectEqualStrings("docs", parse(&.{ "check", "--root", "docs" }).check.root);
    try std.testing.expectEqualStrings("--root needs a directory", parse(&.{ "check", "--root" }).misuse);
    try std.testing.expectEqualStrings("unknown option or argument", parse(&.{ "check", "everything" }).misuse);
}
