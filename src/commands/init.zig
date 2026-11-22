//! `skein init [--template NAME]`: starts a project here: `.skein/` with
//! its configuration, and, from a template, the template's document
//! skeletons (`documents/` of the template) under `docs/`.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Template = @import("../template/Template.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Init) !Workspace.Outcome {
    var root = Io.Dir.cwd().openDir(io, options.root, .{}) catch |e| return misuse(arena, "cannot open '{s}' ({s})", .{ options.root, @errorName(e) });
    defer root.close(io);
    if (root.access(io, Project.dir_name, .{})) |_| {
        return misuse(arena, "there is a project here already: '{s}' has a {s}/", .{ options.root, Project.dir_name });
    } else |_| {}
    if (options.template) |name| if (!Template.exists(name)) return misuse(arena, "skein has no template '{s}' ('skein template list' names them)", .{name});

    const sources = "# where the items are: Markdown documents whose paragraphs can be items\n[[sources]]\npath = \"docs\"\n";
    var config: std.ArrayList(u8) = .empty;
    // options take their defaults; one without a default is left for the project to give
    var values: std.ArrayList(Template.Value) = .empty;
    if (options.template) |name| {
        const declared = (try Template.info(arena, name)).options;
        if (declared.len == 0) {
            try config.print(arena, "template = \"{s}\"\n\n{s}", .{ name, sources });
        } else try config.print(arena, "{s}\n[template.\"{s}\"]\n", .{ sources, name });
        for (declared) |o| if (o.default) |d| {
            try values.append(arena, .{ .name = o.name, .value = d });
            try config.print(arena, "# {s}\n\"{s}\" = \"{s}\"\n", .{ o.description, o.name, d });
        } else try config.print(arena, "# {s} (needed)\n# \"{s}\" = \"\"\n", .{ o.description, o.name });
    } else try config.appendSlice(arena, sources);
    root.createDirPath(io, Project.dir_name) catch |e| return misuse(arena, "cannot make {s}/ ({s})", .{ Project.dir_name, @errorName(e) });
    try root.writeFile(io, .{ .sub_path = Project.config_file, .data = config.items });

    var written: usize = 0;
    if (options.template) |name| {
        for (try Template.filesOf(arena, name, "documents/")) |f| {
            const path = try arena.print("docs/{s}", .{f.path["documents/".len..]});
            if (root.access(io, path, .{})) |_| continue else |_| {}
            if (Io.Dir.path.dirnamePosix(path)) |d| try root.createDirPath(io, d);
            try root.writeFile(io, .{ .sub_path = path, .data = try Template.substitute(arena, f.data, values.items) });
            written += 1;
        }
    }
    try root.createDirPath(io, "docs");
    return .{ .text = try arena.print("skein: a project in {s}{s}{s}, with {d} document{s} to start from; 'skein check' checks it\n", .{
        options.root,
        if (options.template != null) ", from the template " else "",
        options.template orelse "",
        written,
        if (written == 1) "" else "s",
    }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
