//! `skein init [--template NAME]...`: starts a project here: `.skein/` with
//! its configuration, and, from each template, what the template's
//! `config.toml` adds to it, its document skeletons (`documents/`) under
//! `docs/`, and its standards (`project/standards/`, which skein provides and
//! git leaves out: template/standards.zig); and what coding agents
//! should know of Skein, in the project's agent instructions (agents.zig).

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Template = @import("../template/Template.zig");
const standards = @import("../template/standards.zig");
const Workspace = @import("Workspace.zig");
const agents = @import("agents.zig");
const cli = @import("../cli.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Init) !Workspace.Outcome {
    var root = Io.Dir.cwd().openDir(io, options.root, .{}) catch |e| return misuse(arena, "cannot open '{s}' ({s})", .{ options.root, @errorName(e) });
    defer root.close(io);
    if (root.access(io, Project.dir_name, .{})) |_| {
        return misuse(arena, "there is a project here already: '{s}' has a {s}/", .{ options.root, Project.dir_name });
    } else |_| {}
    for (options.templates) |name| if (!Template.exists(name)) return misuse(arena, "skein has no template '{s}' ('skein template list' names them)", .{name});

    const config = try configuration(arena, options.templates);
    root.createDirPath(io, Project.dir_name) catch |e| return misuse(arena, "cannot make {s}/ ({s})", .{ Project.dir_name, @errorName(e) });
    try root.writeFile(io, .{ .sub_path = Project.config_file, .data = config.text });

    var written: usize = 0;
    for (options.templates, config.values) |name, values| {
        for (try Template.filesOf(arena, name, "documents/")) |f| {
            const path = try arena.print("docs/{s}", .{f.path["documents/".len..]});
            if (try writeNew(io, root, path, try Template.substitute(arena, f.data, values))) written += 1;
        }
        // the standards it carries, which skein provides, kept out of git
        _ = try standards.writeFor(io, arena, root, name);
    }
    try root.createDirPath(io, "docs");
    // what coding agents should know of it, in the project's instructions for them
    var agents_file: []const u8 = "";
    switch (try Workspace.open(io, arena, .{ .root = options.root })) {
        .ok => |ws_ok| {
            var ws = ws_ok;
            defer ws.close();
            agents_file = try agents.write(io, arena, &ws, false, null);
        },
        .failed => {},
    }
    const from = if (options.templates.len == 0) "" else try arena.print(", from the template{s} {s}", .{
        if (options.templates.len == 1) "" else "s",
        try std.mem.join(arena, " and ", options.templates),
    });
    const told = if (agents_file.len == 0) "" else try arena.print("; {s} tells coding agents about Skein", .{agents_file});
    return .{ .text = try arena.print("skein: a project in {s}{s}, with {d} document{s} to start from; 'skein check' checks it{s}\n", .{
        options.root,
        from,
        written,
        if (written == 1) "" else "s",
        told,
    }) };
}

const Configuration = struct {
    text: []const u8,
    /// the option values of each template, by default, for its documents
    values: []const []const Template.Value,
};

/// `.skein/config.toml`: the templates, the source of documents, each
/// template's options at their defaults (one without a default written as
/// a comment, to be given), and what each template's `config.toml` adds
fn configuration(arena: std.mem.Allocator, templates: []const []const u8) !Configuration {
    const sources = "# where the items are: Markdown documents whose paragraphs can be items\n[[sources]]\npath = \"docs\"\n";
    var text: std.ArrayList(u8) = .empty;
    var all: std.ArrayList([]const Template.Value) = .empty;
    var any_options = false;
    for (templates) |name| {
        if ((try Template.info(arena, name)).options.len > 0) any_options = true;
    }
    // without options, the templates are named in one line before the sources
    if (templates.len > 0 and !any_options) {
        try text.appendSlice(arena, "template = [");
        for (templates, 0..) |name, i| try text.print(arena, "{s}\"{s}\"", .{ if (i > 0) ", " else "", name });
        try text.appendSlice(arena, "]\n\n");
    }
    try text.appendSlice(arena, sources);
    for (templates) |name| {
        var values: std.ArrayList(Template.Value) = .empty;
        if (any_options) try text.print(arena, "\n[template.\"{s}\"]\n", .{name});
        for ((try Template.info(arena, name)).options) |o| if (o.default) |d| {
            try values.append(arena, .{ .name = o.name, .value = d });
            try values.appendSlice(arena, o.setBy(d));
            try text.print(arena, "# {s}\n\"{s}\" = \"{s}\"\n", .{ o.description, o.name, d });
        } else try text.print(arena, "# {s} (needed)\n# \"{s}\" = \"\"\n", .{ o.description, o.name });
        try all.append(arena, values.items);
    }
    // what the templates add to a project's configuration, such as citations
    for (templates, all.items) |name, values| {
        for (try Template.filesOf(arena, name, "config.toml")) |f| try text.appendSlice(arena, try Template.substitute(arena, f.data, values));
    }
    return .{ .text = text.items, .values = all.items };
}

/// Writes `data` at `path` unless a file is there already; whether it did
fn writeNew(io: Io, root: Io.Dir, path: []const u8, data: []const u8) !bool {
    if (root.access(io, path, .{})) |_| return false else |_| {}
    if (Io.Dir.path.dirnamePosix(path)) |d| try root.createDirPath(io, d);
    try root.writeFile(io, .{ .sub_path = path, .data = data });
    return true;
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
