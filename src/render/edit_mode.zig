//! The static site's edit mode (`skein render --format html --edit --wasm
//! FILE`, #282): skein built for WebAssembly (`zig build wasm`, a release's
//! `skein-vVERSION-wasm32-wasi.wasm`) and the project's files go into the
//! site under `_skein/`, with the scripts that run it in the page (wasi.js,
//! static.js) and edit with it as `skein serve`'s pages do (edit.js). Every
//! page loads them. No server: the site stays static files. Where the project
//! names its forge, `forge.json` says where its changes are saved, through
//! the forge's API (forge.js, #283).

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Workspace = @import("../commands/Workspace.zig");
const Forge = @import("../forge/Forge.zig");
const changes = @import("../serve/changes.zig");
const files = @import("../files.zig");
const git = @import("../git.zig");

pub const dir = "_skein";

/// The largest file the page is given; larger ones are left out
const largest = 4 << 20;

pub const Outcome = union(enum) { ok: usize, failed: []const u8 };

/// Writes the edit mode into the site at `out`, whose pages are `pages`
/// (paths in the site); the number of the project's files it carries
pub fn write(io: Io, arena: std.mem.Allocator, ws: *const Workspace, out: Io.Dir, wasm_path: []const u8, pages: []const []const u8) !Outcome {
    const wasm = Io.Dir.cwd().readFileAlloc(io, wasm_path, arena, .limited(64 << 20)) catch |e| return .{ .failed = try arena.print("--wasm: cannot read '{s}' ({t}); build it with zig build wasm, or take skein-vVERSION-wasm32-wasi.wasm from a release", .{ wasm_path, e }) };
    if (wasm.len < 8 or !std.mem.eql(u8, wasm[0..4], "\x00asm")) return .{ .failed = try arena.print("--wasm: '{s}' is not a WebAssembly module", .{wasm_path}) };
    try out.createDirPath(io, dir);
    try out.writeFile(io, .{ .sub_path = dir ++ "/skein.wasm", .data = wasm });
    try out.writeFile(io, .{ .sub_path = dir ++ "/wasi.js", .data = @embedFile("../serve/wasi.js") });
    try out.writeFile(io, .{ .sub_path = dir ++ "/static.js", .data = @embedFile("../serve/static.js") });
    try out.writeFile(io, .{ .sub_path = dir ++ "/edit.js", .data = @embedFile("../serve/edit.js") });
    try out.writeFile(io, .{ .sub_path = dir ++ "/forge.js", .data = @embedFile("../serve/forge.js") });
    if (ws.project.forge) |forge| try out.writeFile(io, .{ .sub_path = dir ++ "/forge.json", .data = try forgeConfig(io, arena, ws, forge) });
    const carried = try projectFiles(io, arena, ws);
    try out.writeFile(io, .{ .sub_path = dir ++ "/files.json", .data = carried.json });
    for (pages) |page| {
        const html = out.readFileAlloc(io, page, arena, .limited(1 << 28)) catch continue;
        try out.writeFile(io, .{ .sub_path = page, .data = try withScripts(arena, page, html) });
    }
    return .{ .ok = carried.count };
}

/// `html` with the edit mode's scripts, from the page at `page`
pub fn withScripts(arena: std.mem.Allocator, page: []const u8, html: []const u8) ![]const u8 {
    var up: std.ArrayList(u8) = .empty;
    for (page) |c| if (c == '/') try up.appendSlice(arena, "../");
    var scripts: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "wasi", "forge", "static", "edit" }) |name| try scripts.print(arena, "<script src=\"{s}{s}/{s}.js\"></script>\n", .{ up.items, dir, name });
    const at = std.mem.findLast(u8, html, "</body>") orelse html.len;
    return std.mem.concat(arena, u8, &.{ html[0..at], scripts.items, html[at..] });
}

/// Where the project's changes are saved on its forge: its kind, the
/// repository, its web and API addresses, the branch changes go to (null:
/// the repository's default), the project's directory in the repository,
/// and the way the project saves (`[serve] save`)
fn forgeConfig(io: Io, arena: std.mem.Allocator, ws: *const Workspace, forge: Forge) ![]const u8 {
    const web = std.mem.trimEnd(u8, forge.url orelse switch (forge.kind) {
        .github => "https://github.com",
        .gitlab => "https://gitlab.com",
        .forgejo => "https://codeberg.org",
    }, "/");
    const api = switch (forge.kind) {
        .github => if (forge.url != null) try arena.print("{s}/api/v3", .{web}) else "https://api.github.com",
        .gitlab => try arena.print("{s}/api/v4", .{web}),
        .forgejo => try arena.print("{s}/api/v1", .{web}),
    };
    const start = try changes.current(io, arena, ws.root);
    const branch = ws.project.workflow.branch orelse if (start != null and changes.changeOf(start) == null) start else null;
    const prefix_out = if (try changes.ignored(io, arena, ws.root)) "" else try git.output(io, arena, ws.root, &.{ "rev-parse", "--show-prefix" }) orelse "";
    const prefix = std.mem.trim(u8, prefix_out, " \r\n");
    return arena.print("{f}", .{std.json.fmt(.{
        .kind = @tagName(forge.kind),
        .repository = forge.repository,
        .url = web,
        .api = api,
        .branch = branch,
        .prefix = prefix,
        .save = @tagName(ws.project.workflow.mode(true)),
    }, .{})});
}

/// The files `check` and the editing requests read, as a JSON object of
/// path and text: the configuration and schema, the sources, the places
/// that cite, the results; text only
fn projectFiles(io: Io, arena: std.mem.Allocator, ws: *const Workspace) !struct { json: []const u8, count: usize } {
    var places: std.ArrayList([]const u8) = .empty;
    try places.append(arena, Project.dir_name);
    for (ws.project.sources) |s| try places.append(arena, s.path);
    for (ws.project.citations) |c| try places.append(arena, c.path);
    for (ws.project.results) |r| try places.append(arena, r);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    try w.writeAll("{");
    var count: usize = 0;
    for (places.items) |place| {
        // a place that is one file (a results file) or a directory
        const list: []const []const u8 = files.list(io, arena, ws.root, place, &.{""}) catch &.{place};
        for (list) |file| {
            if ((try seen.getOrPut(arena, file)).found_existing) continue;
            const text = ws.root.readFileAlloc(io, file, arena, .limited(largest)) catch continue;
            if (!std.unicode.utf8ValidateSlice(text)) continue;
            if (count > 0) try w.writeAll(",");
            try w.print("{f}:{f}", .{ std.json.fmt(file, .{}), std.json.fmt(text, .{}) });
            count += 1;
        }
    }
    try w.writeAll("}");
    return .{ .json = out.written(), .count = count };
}

test withScripts {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const page = try withScripts(arena.allocator(), "spec/lex/a.html", "<html><body><p>x</p></body></html>");
    try std.testing.expectEqualStrings("<html><body><p>x</p><script src=\"../../_skein/wasi.js\"></script>\n<script src=\"../../_skein/forge.js\"></script>\n<script src=\"../../_skein/static.js\"></script>\n<script src=\"../../_skein/edit.js\"></script>\n</body></html>", page);
}

test {
    _ = @import("_test/edit_mode.zig");
}
