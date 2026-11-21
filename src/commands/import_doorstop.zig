//! `skein import doorstop DIR...`: turns Doorstop documents into skein
//! items, where they are. Each directory's items are rewritten as skein
//! item files, its `.doorstop.yml` becomes an item type, and the
//! directory becomes a source of the project (which is made, if there is
//! none yet). What becomes of what is in import/doorstop/convert.zig.
//!
//! The directory is changed in place, so that git shows every item's
//! history through the import. Commit before importing; the change is
//! then one diff to look over.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Project = @import("../Project.zig");
const Reviews = @import("../graph/Reviews.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const convert = @import("../import/doorstop/convert.zig");
const fingerprint = @import("../graph/fingerprint.zig");

const link_type = "parent";
const link_file = Project.dir_name ++ "/links/" ++ link_type ++ ".toml";

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Import) !Workspace.Outcome {
    // where the project is, or is to be: an import does not look for one
    // above, since the paths it is given are from this directory
    const root_path = Io.Dir.cwd().realPathFileAlloc(io, options.common.root, arena) catch return fail(arena, "cannot find the directory '{s}'", .{options.common.root});
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);

    var importer: Importer = .{ .io = io, .arena = arena, .root = root };
    for (options.paths) |path| {
        if (try importer.document(std.mem.trimEnd(u8, path, "/"))) |problem| return .{ .text = problem, .status = .misuse };
    }
    if (root.access(io, link_file, .{})) |_| {} else |_| {
        try root.createDirPath(io, Project.dir_name ++ "/links");
        try root.writeFile(io, .{ .sub_path = link_file, .data = "description = \"An item rests on its parent items (Doorstop's links)\"\nreview = true\n" });
    }

    // the links Doorstop had a review of are reviewed as their targets are now
    var ws = switch (try Workspace.open(io, arena, .{ .root = root_path })) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    var reviews = try Reviews.load(io, arena, root, &ws.report);
    var files: std.ArrayList([]const u8) = .empty;
    var recorded: usize = 0;
    for (ws.graph.items) |*item| {
        for (item.links) |link| {
            if (!importer.stamped.contains(try arena.print("{s}\n{s}", .{ item.id, link.target }))) continue;
            const target = ws.graph.find(link.target) orelse continue;
            if (ws.project.schema.itemType(target.type_name) == null) continue;
            try reviews.put(arena, item.id, link.type_name, link.target, &try fingerprint.of(arena, &ws.graph, &ws.project.schema, target));
            const file = try Reviews.fileOf(arena, item);
            if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
            recorded += 1;
        }
    }
    try reviews.write(io, arena, root, &ws.project.schema, &ws.graph, files.items);

    return .{ .text = try arena.print(
        "skein: imported {d} item{s} of {d} Doorstop document{s}; {d} link{s} recorded as reviewed\n" ++
            "       Look over the changes ('git diff'), then run 'skein check'.\n",
        .{
            importer.items,    plural(importer.items),
            options.paths.len, plural(options.paths.len),
            recorded,          plural(recorded),
        },
    ) };
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

fn fail(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

const Importer = struct {
    io: Io,
    arena: std.mem.Allocator,
    root: Io.Dir,
    items: usize = 0,
    /// "from\ntarget" of the links Doorstop had a review of
    stamped: std.array_hash_map.String(void) = .empty,

    /// Imports the Doorstop document in the directory `path`; what is
    /// wrong, when it cannot be
    fn document(self: *Importer, path: []const u8) !?[]const u8 {
        const a = self.arena;
        const io = self.io;
        var dir = self.root.openDir(io, path, .{ .iterate = true }) catch return try a.print("skein: cannot open the directory '{s}'\n", .{path});
        defer dir.close(io);
        const settings = dir.readFileAlloc(io, ".doorstop.yml", a, .limited(1 << 20)) catch return try a.print("skein: '{s}' is no Doorstop document: it has no .doorstop.yml\n", .{path});
        var line: u32 = 0;
        var doc = convert.readDocument(a, settings, &line) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return try a.print("skein: {s}/.doorstop.yml:{d}: this is not what Doorstop writes\n", .{ path, line }),
        };
        const type_name = try doc.typeName(a);
        const type_file = try a.print("{s}/types/{s}.toml", .{ Project.dir_name, type_name });
        if (self.root.access(io, type_file, .{})) |_| return try a.print("skein: there is an item type '{s}' already ({s})\n", .{ type_name, type_file }) else |_| {}

        // the items: the files named after the document's prefix
        var names: std.ArrayList([]const u8) = .empty;
        var it = dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind != .file or !std.mem.startsWith(u8, entry.name, doc.prefix)) continue;
            if (!std.mem.endsWith(u8, entry.name, ".md") and !std.mem.endsWith(u8, entry.name, ".yml")) continue;
            try names.append(a, try a.dupe(u8, entry.name));
        }
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.lt);

        var read: std.ArrayList(convert.Item) = .empty;
        for (names.items) |name| {
            const is_yaml = std.mem.endsWith(u8, name, ".yml");
            const id = name[0 .. name.len - @as(usize, if (is_yaml) 4 else 3)];
            const source = dir.readFileAlloc(io, name, a, .limited(1 << 26)) catch return try a.print("skein: cannot read {s}/{s}\n", .{ path, name });
            try read.append(a, convert.readItem(a, id, source, is_yaml, &line) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return try a.print("skein: {s}/{s}:{d}: this is not what Doorstop writes\n", .{ path, name, line }),
            });
        }

        for (read.items) |item| {
            const number = std.mem.trimStart(u8, item.id[@min(doc.prefix.len, item.id.len)..], doc.separator);
            for (number) |c| {
                if (!std.ascii.isDigit(c)) doc.names = true;
            }
        }

        // Doorstop's categories are skein's when every active item has one
        var categories: std.ArrayList([]const u8) = .empty;
        var use_category = read.items.len > 0;
        for (read.items) |item| {
            if (!item.active) continue;
            if (item.category.len == 0) use_category = false;
            if (item.category.len > 0 and !Schema.names.contains(categories.items, item.category)) try categories.append(a, item.category);
        }
        if (!use_category) categories.clearRetainingCapacity();
        std.mem.sort([]const u8, categories.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.lt);

        var attributes: std.ArrayList([]const u8) = .empty;
        for (read.items) |item| {
            for (try convert.attributesOf(a, item, use_category)) |attribute| {
                if (!Schema.names.contains(attributes.items, attribute[0])) try attributes.append(a, attribute[0]);
            }
            for (item.links) |link| {
                if (link.stamped) try self.stamped.put(a, try a.print("{s}\n{s}", .{ item.id, link.target }), {});
            }
        }

        // everything is read: now write
        for (read.items, names.items) |item, name| {
            const out_name = try a.print("{s}.md", .{item.id});
            try dir.writeFile(io, .{ .sub_path = out_name, .data = try convert.render(a, item, use_category) });
            if (!std.mem.eql(u8, name, out_name)) dir.deleteFile(io, name) catch {};
        }
        dir.deleteFile(io, ".doorstop.yml") catch {};
        try self.root.createDirPath(io, Project.dir_name ++ "/types");
        try self.root.writeFile(io, .{ .sub_path = type_file, .data = try convert.renderType(a, doc, attributes.items, categories.items) });
        try self.addSource(path, type_name);
        self.items += read.items.len;
        return null;
    }

    /// Adds the directory to the project's sources, at the end of its
    /// configuration, which is made when there is none
    fn addSource(self: *Importer, path: []const u8, type_name: []const u8) !void {
        const a = self.arena;
        const before = self.root.readFileAlloc(self.io, Project.config_file, a, .limited(1 << 24)) catch "";
        const gap: []const u8 = if (before.len == 0 or std.mem.endsWith(u8, before, "\n\n")) "" else if (std.mem.endsWith(u8, before, "\n")) "\n" else "\n\n";
        const text = try a.print("{s}{s}[[sources]]\npath = \"{s}\"\nkind = \"items\"\ntype = \"{s}\"\n", .{ before, gap, path, type_name });
        try self.root.writeFile(self.io, .{ .sub_path = Project.config_file, .data = text });
    }
};

test {
    _ = @import("_test/import_doorstop.zig");
}
