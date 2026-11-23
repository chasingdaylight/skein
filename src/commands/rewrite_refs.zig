//! `skein rewrite-refs`: after a move between forges (`skein publish`), writes
//! the new number into the references that were written with the old forge's:
//! `%[#24]` becomes `%[#7]`, `tracked-by=#24` in a marker becomes `=#7`, and
//! `"#24"` in front matter likewise. Only those places are touched, never
//! prose, a code block or a color; a source that is read-only is left alone.

const std = @import("std");
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const files = @import("../files.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.RewriteRefs) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    const forge = ws.project.forge orelse return misuse(arena, "the project names no forge", .{});
    if (forge.formerly.len == 0) return misuse(arena, "the project declares no former forge: add formerly = [\"kind:owner/repo\"] under [forge]", .{});
    if (forge.moved.len == 0) return misuse(arena, "the map of moved issues is empty or missing (.skein/forge-map.toml, written by 'skein publish')", .{});

    var total: usize = 0;
    var touched: usize = 0;
    var out: std.ArrayList(u8) = .empty;
    for (ws.project.sources) |source| {
        if (source.read_only) continue;
        const paths = files.list(io, arena, ws.root, source.path, &.{".md"}) catch continue;
        for (paths) |path| {
            const text = ws.root.readFileAlloc(io, path, arena, .limited(1 << 26)) catch continue;
            var count: usize = 0;
            const now = try rewriteText(arena, &forge, text, &count);
            if (count == 0) continue;
            if (!options.dry_run) try ws.root.writeFile(io, .{ .sub_path = path, .data = now });
            try out.print(arena, "{s}: {d} reference{s}\n", .{ path, count, if (count == 1) "" else "s" });
            total += count;
            touched += 1;
        }
    }
    try out.print(arena, "skein: {s} {d} reference{s} in {d} file{s}\n", .{ if (options.dry_run) "would rewrite" else "rewrote", total, if (total == 1) "" else "s", touched, if (touched == 1) "" else "s" });
    // once the numbers are the new forge's, a new number that is also an old one in the map would be read as the old
    if (!options.dry_run) try out.appendSlice(arena, "skein: every reference has the new numbers now: remove `formerly` from [forge] in .skein/config.toml, or a new number that is also an old one in the map is read as the old one\n");
    return .{ .text = out.items };
}

/// `text` with the old numbers of the former forges rewritten, counted in `count`
pub fn rewriteText(arena: std.mem.Allocator, forge: *const Forge, text: []const u8, count: *usize) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var in_code = false;
    var in_front = false;
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        line_no += 1;
        if (line_no > 1) try out.append(arena, '\n');
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (line_no == 1 and std.mem.eql(u8, trimmed, "+++")) in_front = true else if (in_front and std.mem.eql(u8, trimmed, "+++")) in_front = false;
        if (std.mem.startsWith(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "~~~")) in_code = !in_code;
        if (in_code) {
            try out.appendSlice(arena, line);
            continue;
        }
        var now = line;
        if (in_front) now = try renumber(arena, forge, now, "\"", count);
        // a marker at the start of a paragraph or list entry: its attributes and links
        if (markerEnd(now)) |end| {
            const head = try renumber(arena, forge, now[0..end], "=,", count);
            now = try std.mem.concat(arena, u8, &.{ head, now[end..] });
        }
        now = try renumber(arena, forge, now, "[", count);
        try out.appendSlice(arena, now);
    }
    return out.items;
}

/// Where the brackets of a marker at the start of `line` end; null when it has none
fn markerEnd(line: []const u8) ?usize {
    var at: usize = 0;
    while (at < line.len and (line[at] == ' ' or line[at] == '\t' or line[at] == '-' or line[at] == '*')) at += 1;
    if (at >= line.len or line[at] != '%') return null;
    const open = std.mem.findScalarPos(u8, line, at, '[') orelse return null;
    // a type name, then the bracket: `%rule[`; a reference has none
    if (open == at + 1) return null;
    for (line[at + 1 .. open]) |c| if (!std.ascii.isLower(c) and c != '-' and c != '_' and !std.ascii.isDigit(c)) return null;
    return std.mem.findScalarPos(u8, line, open, ']');
}

/// `span` with `#N` rewritten where a character of `before` comes just before the `#`
/// and the number is the former forge's; `%[#N` needs `[` and `%` both, so only `[` after `%`
fn renumber(arena: std.mem.Allocator, forge: *const Forge, span: []const u8, before: []const u8, count: *usize) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < span.len) {
        const c = span[i];
        if (c == '#' and i > 0 and std.mem.findScalar(u8, before, span[i - 1]) != null and (span[i - 1] != '[' or (i > 1 and span[i - 2] == '%'))) {
            var j = i + 1;
            while (j < span.len and std.ascii.isDigit(span[j])) j += 1;
            const boundary = j >= span.len or !std.ascii.isAlphanumeric(span[j]);
            if (j > i + 1 and boundary) {
                const written = try arena.print("#{s}", .{span[i + 1 .. j]});
                if (forge.ref(written)) |r| if (r.former != null) {
                    try out.print(arena, "#{d}", .{r.number});
                    count.* += 1;
                    i = j;
                    continue;
                };
            }
        }
        try out.append(arena, c);
        i += 1;
    }
    return out.items;
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

// req: forge.moved
test "the numbers of a former forge are rewritten only where they are references" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const forge: Forge = .{
        .kind = .gitlab,
        .repository = "group/project",
        .formerly = &.{"github:example/spec"},
        .moved = &.{
            .{ .from = "github:example/spec#24", .to = "gitlab:group/project#7" },
            .{ .from = "github:example/spec#25", .to = "gitlab:group/project#8" },
            // the same number on both: nothing to rewrite
            .{ .from = "github:example/spec#26", .to = "gitlab:group/project#26" },
        },
    };
    const text =
        \\+++
        \\id = "lex.a"
        \\derived-from = ["#24"]
        \\+++
        \\
        \\%rule[lex.b tracked-by=#24,#9 introduced-by=#25] See %[#25 the issue] and issue #24 and the color #25 and %[#9] and %[#26].
        \\
        \\```text
        \\%rule[x tracked-by=#24] %[#24]
        \\```
        \\
    ;
    var n: usize = 0;
    const got = try rewriteText(a, &forge, text, &n);
    // #9 is not in the map: it is the new forge's own; prose and code are left as written
    try std.testing.expectEqual(4, n);
    try std.testing.expect(std.mem.find(u8, got, "derived-from = [\"#7\"]") != null);
    try std.testing.expect(std.mem.find(u8, got, "tracked-by=#7,#9 introduced-by=#8]") != null);
    try std.testing.expect(std.mem.find(u8, got, "See %[#8 the issue] and issue #24 and the color #25 and %[#9] and %[#26].") != null);
    try std.testing.expect(std.mem.find(u8, got, "%rule[x tracked-by=#24] %[#24]") != null);
}
