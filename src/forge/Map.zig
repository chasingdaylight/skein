//! Where the issues of a former forge are now: `.skein/forge-map.toml`,
//! written by `skein publish` and committed, one line for each issue that
//! moved:
//!
//!     "github:example/spec#24" = "gitlab:group/project#7"

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const file = ".skein/forge-map.toml";

const header = "# Where the issues of a former forge are now: written by skein publish, committed.\n";

/// The moves the map holds, in order of their old references; none when the
/// file is not there or cannot be read
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir) std.mem.Allocator.Error![]const Forge.Moved {
    var out: std.ArrayList(Forge.Moved) = .empty;
    const text = root.readFileAlloc(io, file, arena, .limited(1 << 24)) catch return out.items;
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return out.items,
    };
    for (table.keys()) |from| {
        const to = table.get(from) orelse continue;
        if (to == .string) try out.append(arena, .{ .from = from, .to = to.string });
    }
    return out.items;
}

/// Adds `new` to the map, which keeps every earlier move, in order
pub fn save(io: Io, arena: std.mem.Allocator, root: Io.Dir, new: []const Forge.Moved) !void {
    var all: std.array_hash_map.String([]const u8) = .empty;
    for (try load(io, arena, root)) |m| try all.put(arena, m.from, m.to);
    for (new) |m| try all.put(arena, m.from, m.to);
    const Order = struct {
        keys: []const []const u8,
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            return std.mem.lessThan(u8, self.keys[a], self.keys[b]);
        }
    };
    all.sort(Order{ .keys = all.keys() });
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(arena, header);
    for (all.keys(), all.values()) |k, v| try text.print(arena, "{s} = {s}\n", .{ try write.string(arena, k), try write.string(arena, v) });
    try root.writeFile(io, .{ .sub_path = file, .data = text.items });
}
