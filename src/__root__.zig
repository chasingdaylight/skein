//! skein: plain-text requirements, specifications and traceability.

pub const cli = @import("cli.zig");
pub const Graph = @import("graph/Graph.zig");
pub const Json = @import("output/Json.zig");
pub const markdown = @import("markdown.zig");
pub const Project = @import("Project.zig");
pub const Report = @import("Report.zig");
pub const Schema = @import("schema/Schema.zig");
pub const stdio = @import("stdio.zig");
pub const toml = @import("toml.zig");

pub const main = @import("__main__.zig").main;

test {
    _ = cli;
    _ = Graph;
    _ = Json;
    _ = markdown;
    _ = Project;
    _ = Report;
    _ = Schema;
    _ = stdio;
    _ = toml;
    _ = @import("graph/walk.zig");
    _ = @import("graph/coverage.zig");
    _ = @import("commands/diff.zig");
    _ = @import("commands/export.zig");
    _ = @import("import/doorstop/convert.zig");
    _ = @import("commands/import_doorstop.zig");
    _ = @import("commands/_test/trace.zig");
}
