//! `skein template list`, `show NAME`, `eject NAME` and `documents`: the templates
//! built into skein, what one declares, and its files taken into a project.

const std = @import("std");

const Template = @import("../template/Template.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const template_documents = @import("../template/documents.zig");

pub fn run(io: std.Io, arena: std.mem.Allocator, options: cli.TemplateCommand) !Workspace.Outcome {
    var out: std.ArrayList(u8) = .empty;
    switch (options.what) {
        .eject => return eject(io, arena, options),
        .documents => return documents(io, arena, options),
        .list => for (try Template.names(arena)) |name| {
            try out.print(arena, "{s}  {s}\n", .{ name, (try Template.info(arena, name)).description });
        },
        .show => {
            const name = options.name orelse return misuse(arena, "template show takes the name of a template", .{});
            if (!Template.exists(name)) return misuse(arena, "skein has no template '{s}' ('skein template list' names them)", .{name});
            const info = try Template.info(arena, name);
            try out.print(arena, "{s}: {s}\n", .{ name, info.description });
            if (info.options.len > 0) try out.appendSlice(arena, "\nOptions:\n");
            for (info.options) |o| {
                try out.print(arena, "  {s}", .{o.name});
                if (o.values.len > 0) try out.print(arena, " ({s})", .{try std.mem.join(arena, ", ", o.values)});
                if (o.default) |d| try out.print(arena, ", default {s}", .{d});
                try out.print(arena, ": {s}\n", .{o.description});
            }
            for ([_][]const u8{ "types", "links", "profiles", "documents", "project" }) |kind| {
                const files = try Template.filesOf(arena, name, try arena.print("{s}/", .{kind}));
                if (files.len == 0) continue;
                try out.print(arena, "\n{c}{s}:\n", .{ std.ascii.toUpper(kind[0]), kind[1..] });
                for (files) |f| try out.print(arena, "  {s}\n", .{f.path[kind.len + 1 ..]});
            }
            if (info.includes.len > 0) try out.appendSlice(arena, "\nBrings along:\n");
            for (info.includes) |inc| {
                try out.print(arena, "  {s}", .{inc.template});
                if (inc.option) |o| try out.print(arena, ", when {s} is {s}", .{ o, try std.mem.join(arena, " or ", inc.values) }) else try out.appendSlice(arena, ", always");
                if (inc.because.len > 0) try out.print(arena, ": {s}", .{inc.because});
                try out.append(arena, '\n');
            }
            if ((try Template.filesOf(arena, name, "config.toml")).len > 0) try out.appendSlice(arena, "\nConfiguration: config.toml, which 'skein init' adds to the project's\n");
        },
    }
    return .{ .text = out.items };
}

/// Copies the types, links and profiles of a template the project uses
/// into its `.skein/`, as its options make them, to be changed freely:
/// the project's own files replace the template's. A file the project has
/// already is left as it is.
fn eject(io: std.Io, arena: std.mem.Allocator, options: cli.TemplateCommand) !Workspace.Outcome {
    const name = options.name orelse return misuse(arena, "template eject takes the name of a template", .{});
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    const use = for (ws.project.templates) |u| {
        if (std.mem.eql(u8, u.name, name)) break u;
    } else return misuse(arena, "the project does not use the template '{s}'", .{name});
    var written: usize = 0;
    var kept: usize = 0;
    for ([_][]const u8{ "types/", "links/", "profiles/" }) |kind| {
        for (try Template.filesOf(arena, name, kind)) |f| {
            const path = try arena.print(".skein/{s}", .{f.path});
            if (ws.root.access(io, path, .{})) |_| {
                kept += 1;
                continue;
            } else |_| {}
            if (std.Io.Dir.path.dirnamePosix(path)) |d| try ws.root.createDirPath(io, d);
            try ws.root.writeFile(io, .{ .sub_path = path, .data = try Template.substitute(arena, f.data, use.options) });
            written += 1;
        }
    }
    return .{ .text = try arena.print("skein: {d} file{s} of '{s}' written to .skein/, where they replace the template's{s}\n", .{
        written,
        if (written == 1) "" else "s",
        name,
        if (kept > 0) try arena.print("; {d} the project has already, left as {s}", .{ kept, if (kept == 1) "it is" else "they are" }) else "",
    }) };
}

/// Writes the document skeletons of every template in use, brought along
/// ones too, that are not in `docs/` yet
fn documents(io: std.Io, arena: std.mem.Allocator, options: cli.TemplateCommand) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (ws.project.templates.len == 0) return misuse(arena, "the project uses no template", .{});
    var out: std.ArrayList(u8) = .empty;
    var total: usize = 0;
    for (ws.project.templates) |u| {
        const n = try template_documents.write(io, arena, ws.root, u);
        total += n;
        if (n > 0) try out.print(arena, "skein: {d} document{s} of {s}{s}\n", .{ n, if (n == 1) "" else "s", u.name, if (u.brought_by) |b| try arena.print(", which {s} brings along", .{b}) else "" });
    }
    if (total == 0) try out.appendSlice(arena, "skein: every document of the templates in use is in docs/ already\n");
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
