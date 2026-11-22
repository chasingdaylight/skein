//! The list of the templates' files in `templates/__root__.zig` is the
//! files of `templates/`, every one of them.

// req: templates.builtin
const std = @import("std");
const testing = std.testing;

const embedded = @import("templates");
const files = @import("../../files.zig");
const templates_dir = @import("build_options").templates_dir;

test "every file of templates/ is built in, and nothing else" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = try std.Io.Dir.cwd().openDir(testing.io, templates_dir, .{});
    defer dir.close(testing.io);
    const on_disk = try files.list(testing.io, a, dir, ".", &.{ ".toml", ".md" });
    for (on_disk) |path| {
        const listed = for (embedded.files) |f| {
            if (std.mem.eql(u8, path, try a.print("{s}/{s}", .{ f.template, f.path }))) break true;
        } else false;
        if (!listed) {
            std.debug.print("templates/{s} is not listed in templates/__root__.zig\n", .{path});
            return error.TestUnexpectedResult;
        }
    }
    try testing.expectEqual(on_disk.len, embedded.files.len);
}
