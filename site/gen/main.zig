//! skein-site-gen [--content DIR] [--pages FILE] [--site DIR] [--repo DIR]
//!
//! Turns the pages tools/site.sh put together (CONTENT: docs/ with the
//! requirements rendered, and the earlier releases' under vX.Y.Z/) into what
//! Zine builds: SuperMD files in `SITE/content/`, placed by the tree of
//! pages (FILE, pages.txt), each group's front page, and
//! `SITE/assets/site-index.json` and `editions.json` for the explorer, the
//! search and the editions. Everything it writes is generated; the layouts,
//! styles and scripts in SITE are written by hand. From cesiumlang.org's
//! tools/zine/main.zig (cesiumlang/cesiumlang.org@c657aa2).

const std = @import("std");
const content = @import("content.zig");
const pages_txt = @import("pages.zig");
const portable = @import("portable.zig");
const site_json = @import("site_json.zig");
const smd = @import("smd.zig");

const usage = "usage: skein-site-gen [--content DIR] [--pages FILE] [--site DIR] [--repo DIR]\n";

/// The date of a page that git does not know.
const fallback_date = "2026-11-21T00:00:00";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var content_dir: []const u8 = "../.site/md";
    var pages_path: []const u8 = "pages.txt";
    var site_dir: []const u8 = ".";
    var repo: []const u8 = "..";
    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        const value = if (i + 1 < args.len) args[i + 1] else "";
        if (std.mem.eql(u8, args[i], "--content") and value.len > 0) {
            content_dir = value;
        } else if (std.mem.eql(u8, args[i], "--pages") and value.len > 0) {
            pages_path = value;
        } else if (std.mem.eql(u8, args[i], "--site") and value.len > 0) {
            site_dir = value;
        } else if (std.mem.eql(u8, args[i], "--repo") and value.len > 0) {
            repo = value;
        } else {
            try std.Io.File.stderr().writeStreamingAll(io, usage);
            std.process.exit(2);
        }
    }
    const cwd = std.Io.Dir.cwd();

    const groups = try pages_txt.parse(arena, try cwd.readFileAlloc(io, pages_path, arena, .limited(1 << 20)));
    const pages = try pages_txt.place(arena, groups, try content.load(arena, io, content_dir));
    var report: portable.Report = .{ .arena = arena };

    const generated = try arena.print("{s}/content", .{site_dir});
    cwd.deleteTree(io, generated) catch {};

    // the release the pages are of, as tools/site.sh wrote it
    const version_path = try arena.print("{s}/skein-version.txt", .{content_dir});
    const version: ?[]const u8 = if (cwd.readFileAlloc(io, version_path, arena, .limited(1 << 12))) |text|
        try arena.print("Skein {s}", .{std.mem.trim(u8, text, " \r\n")})
    else |_|
        null;

    var entries: std.ArrayList(site_json.Entry) = .empty;
    for (pages) |page| {
        const date = try gitDate(arena, io, repo, page);
        const page_version = if (page.edition()) |release| try arena.print("Skein {s}", .{release}) else version;
        const rendered = try smd.render(arena, pages, page, date, page_version, &report);
        try write(io, generated, try arena.print("{s}.smd", .{page.site}), rendered.text, arena);
        try entries.append(arena, .{
            .page = page,
            .headings = rendered.headings,
            .links = try portable.linkTargets(arena, pages, page),
        });
    }
    const assets = try arena.print("{s}/assets", .{site_dir});
    try copyLinked(io, arena, content_dir, assets, report.files.items);
    try write(io, assets, "site-index.json", try site_json.render(arena, entries.items), arena);
    // the releases for the edition selector, as tools/site.sh wrote them
    const editions_path = try arena.print("{s}/skein-editions.json", .{content_dir});
    const editions: []const u8 = cwd.readFileAlloc(io, editions_path, arena, .limited(1 << 16)) catch
        "{\"releases\":[]}\n";
    try write(io, assets, "editions.json", editions, arena);

    std.debug.print("{d} pages, {d} unresolved links\n", .{ pages.len, report.unresolved });
}

/// The tops of the files linked from pages (and each edition's), which
/// assets/ holds only as copies (.gitignore): removed before each run.
const linked_tops = [_][]const u8{ "examples", "img" };

// each file linked from a page into assets/, at its path, for Zine to check
// the link and write the file; the files of an earlier run are removed
fn copyLinked(io: std.Io, arena: std.mem.Allocator, content_dir: []const u8, assets: []const u8, files: []const []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var dir = try cwd.openDir(io, assets, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    var stale: std.ArrayList([]const u8) = .empty;
    while (try it.next(io)) |entry| {
        if (entry.kind == .directory and isLinkedTop(entry.name)) try stale.append(arena, try arena.dupe(u8, entry.name));
    }
    for (stale.items) |name| try dir.deleteTree(io, name);
    for (files) |path| {
        if (!isLinkedTop(path[0 .. std.mem.findScalar(u8, path, '/') orelse path.len])) {
            std.debug.print("warning: {s}: a file linked from a page belongs under examples/ or img/\n", .{path});
            continue;
        }
        const from = try arena.print("{s}/{s}", .{ content_dir, path });
        const data = cwd.readFileAlloc(io, from, arena, .limited(1 << 26)) catch {
            std.debug.print("warning: {s}: linked from a page, and not there\n", .{path});
            continue;
        };
        try write(io, assets, path, data, arena);
    }
}

fn isLinkedTop(name: []const u8) bool {
    if (content.editionOf(name) != null) return true;
    for (linked_tops) |top| {
        if (std.mem.eql(u8, name, top)) return true;
    }
    return false;
}

fn write(io: std.Io, dir: []const u8, path: []const u8, data: []const u8, arena: std.mem.Allocator) !void {
    const full = try arena.print("{s}/{s}", .{ dir, path });
    if (std.mem.findScalarLast(u8, full, '/')) |slash| try std.Io.Dir.cwd().createDirPath(io, full[0..slash]);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = full, .data = data });
}

// the date of the last commit that changed the page's file under docs/ (at
// its release's tag, for an edition), as Zine writes dates
fn gitDate(arena: std.mem.Allocator, io: std.Io, repo: []const u8, page: content.Page) ![]const u8 {
    const path = try arena.print("docs/{s}.md", .{page.withinEdition()});
    const rev = if (page.edition()) |release| try arena.print("v{s}", .{release}) else "HEAD";
    const result = std.process.run(arena, io, .{
        .argv = &.{ "git", "log", "-1", "--format=%cI", rev, "--", path },
        .cwd = .{ .path = repo },
        .stdout_limit = .limited(256),
    }) catch return fallback_date;
    const text = std.mem.trim(u8, result.stdout, " \r\n");
    if (!result.term.success() or text.len < 19) return fallback_date;
    return try arena.dupe(u8, text[0..19]);
}
