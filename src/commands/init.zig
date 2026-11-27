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
const files = @import("../files.zig");
const standards = @import("../template/standards.zig");
const template_documents = @import("../template/documents.zig");
const todo = @import("../agents/todo.zig");
const Workspace = @import("Workspace.zig");
const agents = @import("agents.zig");
const init_workflow = @import("init_workflow.zig");
const cli = @import("../cli.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Init) !Workspace.Outcome {
    var root = Io.Dir.cwd().openDir(io, options.root, .{}) catch |e| return misuse(arena, "cannot open '{s}' ({s})", .{ options.root, @errorName(e) });
    defer root.close(io);
    if (root.access(io, Project.dir_name, .{})) |_| {
        return misuse(arena, "there is a project here already: '{s}' has a {s}/", .{ options.root, Project.dir_name });
    } else |_| {}
    for (options.templates) |name| if (!Template.exists(name)) return misuse(arena, "skein has no template '{s}' ('skein template list' names them)", .{name});
    const given = try arena.alloc(Given, options.options.len);
    for (options.options, given) |o, *g| {
        const eq = std.mem.findScalar(u8, o, '=') orelse return misuse(arena, "--option takes NAME=VALUE, not '{s}'", .{o});
        g.* = .{ .name = o[0..eq], .value = o[eq + 1 ..] };
    }

    const full = root.realPathFileAlloc(io, ".", arena) catch "";
    const config = try configuration(arena, try projectName(arena, Io.Dir.path.basename(full)), options.templates, given);
    if (config.problem) |p| return misuse(arena, "{s}", .{p});
    root.createDirPath(io, Project.dir_name) catch |e| return misuse(arena, "cannot make {s}/ ({s})", .{ Project.dir_name, @errorName(e) });
    try root.writeFile(io, .{ .sub_path = Project.config_file, .data = config.text });

    var written: usize = 0;
    for (options.templates, config.values) |name, values| {
        for (try Template.filesOf(arena, name, "documents/")) |f| {
            const path = try arena.print("docs/{s}", .{f.path["documents/".len..]});
            if (try files.writeNew(io, root, path, try Template.substitute(arena, f.data, values))) written += 1;
        }
        // the standards it carries, which skein provides, kept out of git
        _ = try standards.writeFor(io, arena, root, name);
    }
    try root.createDirPath(io, "docs");
    // on GitHub: the workflow that checks the documents and collects them as PDFs
    const workflow = try init_workflow.write(io, arena, root, @import("build_options").version);
    // what coding agents should know of it, in the project's instructions for them
    var agents_file: []const u8 = "";
    // and what is still to do, which the agent that ran it is told too
    var still: []const []const u8 = &.{};
    switch (try Workspace.open(io, arena, .{ .root = options.root })) {
        .ok => |ws_ok| {
            var ws = ws_ok;
            defer ws.close();
            // the documents of the templates the options bring along
            for (ws.project.templates) |u| if (u.brought_by != null) {
                written += try template_documents.write(io, arena, ws.root, u);
            };
            agents_file = try agents.write(io, arena, &ws, false, null);
            still = try todo.list(io, arena, &ws);
        },
        .failed => |outcome| still = try arena.dupe([]const u8, &.{try arena.print("Give the options the templates need in `.skein/config.toml`, then run `skein agents`, which says what else is to do:\n  {s}", .{std.mem.trim(u8, outcome.text, " \n")})}),
    }
    const from = if (options.templates.len == 0) "" else try arena.print(", from the template{s} {s}", .{
        if (options.templates.len == 1) "" else "s",
        try std.mem.join(arena, " and ", options.templates),
    });
    const told = if (agents_file.len == 0) "" else try arena.print("; {s} tells coding agents about Skein", .{agents_file});
    const ci = if (workflow) |w| try arena.print("; {s} checks them and collects them as PDFs", .{w}) else "";
    var text: std.ArrayList(u8) = .empty;
    try text.print(arena, "skein: a project in {s}{s}, with {d} document{s} to start from; 'skein check' checks it{s}{s}\n", .{
        options.root,
        from,
        written,
        if (written == 1) "" else "s",
        told,
        ci,
    });
    if (still.len > 0) try text.appendSlice(arena, "Still to do:\n");
    for (still) |t| try text.print(arena, "- {s}\n", .{t});
    return .{ .text = text.items };
}

/// An option given with `--option NAME=VALUE`
const Given = struct { name: []const u8, value: []const u8, used: bool = false };

const Configuration = struct {
    text: []const u8 = "",
    /// the option values of each template, given or by default, for its documents
    values: []const []const Template.Value = &.{},
    /// what is wrong with the options given
    problem: ?[]const u8 = null,
};

/// `.skein/config.toml`: the templates, the source of documents, each
/// template's options as given, else at their defaults (one without a
/// default written as a comment, to be given), and what each template's
/// `config.toml` adds
fn configuration(arena: std.mem.Allocator, name_of_project: ?[]const u8, templates: []const []const u8, given: []Given) !Configuration {
    var sources: []const u8 = "# where the items are: Markdown documents whose paragraphs can be items\n[[sources]]\npath = \"docs\"\n";
    if (name_of_project) |n| sources = try arena.print("# the project's name, for reports\n[project]\nname = \"{s}\"\n\n{s}", .{ n, sources });
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
        for ((try Template.info(arena, name)).options) |o| {
            const g: ?*Given = for (given) |*g| {
                if (std.mem.eql(u8, g.name, o.name)) break g;
            } else null;
            if (g) |x| {
                x.used = true;
                if (o.values.len > 0) for (o.values) |v| {
                    if (std.mem.eql(u8, v, x.value)) break;
                } else return .{ .problem = try arena.print("'{s}' is not a value of the option '{s}' of '{s}': {s}", .{ x.value, o.name, name, try std.mem.join(arena, ", ", o.values) }) };
            }
            const value = if (g) |x| x.value else o.default orelse {
                try text.print(arena, "# {s} (needed)\n# \"{s}\" = \"\"\n", .{ o.description, o.name });
                continue;
            };
            try values.append(arena, .{ .name = o.name, .value = value });
            try values.appendSlice(arena, o.setBy(value));
            try text.print(arena, "# {s}\n\"{s}\" = \"{s}\"\n", .{ o.description, o.name, value });
        }
        try all.append(arena, values.items);
    }
    for (given) |g| if (!g.used) return .{ .problem = try arena.print("no template named has the option '{s}' ('skein template show NAME' lists a template's options)", .{g.name}) };
    // what the templates add to a project's configuration, such as citations
    for (templates, all.items) |name, values| {
        for (try Template.filesOf(arena, name, "config.toml")) |f| try text.appendSlice(arena, try Template.substitute(arena, f.data, values));
    }
    return .{ .text = text.items, .values = all.items };
}

/// The project's name from its directory's: lowercase, with `-` for what a
/// name cannot hold; null when nothing of it is left
fn projectName(arena: std.mem.Allocator, dir: []const u8) !?[]const u8 {
    const out = try arena.alloc(u8, dir.len);
    for (dir, out) |c, *o| o.* = switch (std.ascii.toLower(c)) {
        'a'...'z', '0'...'9', '-', '_', '.' => std.ascii.toLower(c),
        else => '-',
    };
    const trimmed = std.mem.trim(u8, out, "-.");
    return if (trimmed.len == 0) null else trimmed;
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
