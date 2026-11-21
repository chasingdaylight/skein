//! skein: plain-text requirements, specifications and traceability.

pub const cli = @import("cli.zig");
pub const stdio = @import("stdio.zig");

pub const main = @import("__main__.zig").main;

test {
    _ = cli;
    _ = stdio;
}
