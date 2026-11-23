//! The forge a project's issues and pull requests are on, as `[forge]` in
//! `.skein/config.toml` gives it, and references to them: `#97` in the
//! project's own repository, `owner/repo#12` in another.

const std = @import("std");

const Schema = @import("../schema/Schema.zig");

const Forge = @This();

kind: Kind = .github,
/// `owner/repo`
repository: []const u8,
/// the address of another server (GitHub Enterprise); null for the public one
url: ?[]const u8 = null,
/// whether the full mirror (`skein mirror`) is committed; by default it is per checkout
mirror_committed: bool = false,
/// the forges the project was on before, `kind:owner/repo`: a reference written
/// for one of them resolves through the map of where its issues went
formerly: []const []const u8 = &.{},
/// where the issues of a former forge went (`.skein/forge-map.toml`); set when the project is read
moved: []const Moved = &.{},

pub const Kind = enum { github, gitlab, forgejo };

/// An issue that moved: `github:example/spec#24` to `gitlab:group/project#7`
pub const Moved = struct { from: []const u8, to: []const u8 };

/// The `[forge]` table of the configuration `r`; null when it has none
pub fn read(r: Schema.Reader) Schema.Reader.Error!?Forge {
    const f = try r.child("forge") orelse return null;
    try f.known(&.{ "kind", "repository", "url", "mirror", "formerly" });
    const kind_name = try f.string("kind") orelse "github";
    const kind = std.meta.stringToEnum(Kind, kind_name) orelse {
        try f.complain("kind", "expected \"github\", \"gitlab\" or \"forgejo\"", .{});
        return null;
    };
    const repository = try f.string("repository") orelse {
        try f.complain("repository", "the forge needs the repository, as owner/repo", .{});
        return null;
    };
    if (std.mem.findScalar(u8, repository, '/') == null) {
        try f.complain("repository", "a repository is written owner/repo", .{});
        return null;
    }
    const mirror = try f.string("mirror") orelse "local";
    if (!std.mem.eql(u8, mirror, "local") and !std.mem.eql(u8, mirror, "committed")) {
        try f.complain("mirror", "expected \"local\" or \"committed\"", .{});
        return null;
    }
    const formerly = try f.strings("formerly");
    for (formerly) |name| {
        const colon = std.mem.findScalar(u8, name, ':') orelse 0;
        if (std.meta.stringToEnum(Kind, name[0..colon]) == null or std.mem.findScalar(u8, name[colon..], '/') == null) {
            try f.complain("formerly", "'{s}' is no forge: write it kind:owner/repo, as \"github:example/spec\"", .{name});
        }
    }
    return .{
        .kind = kind,
        .repository = repository,
        .url = if (try f.string("url")) |u| std.mem.trimEnd(u8, u, "/") else null,
        .mirror_committed = std.mem.eql(u8, mirror, "committed"),
        .formerly = formerly,
    };
}

/// An issue or a pull request
pub const Ref = struct {
    /// `owner/repo`
    repository: []const u8,
    number: u64,
    /// the former forge, `kind:owner/repo`, whose number the reference was written with,
    /// and that number, when it was resolved through the map
    former: ?[]const u8 = null,
    former_number: u64 = 0,
    /// a reference to a former forge that the map does not have
    unmapped: bool = false,
};

/// Whether `target` names an issue or a pull request: `#97`, `o/r#12`
pub fn isRef(target: []const u8) bool {
    const hash = std.mem.findScalar(u8, target, '#') orelse return false;
    const digits = target[hash + 1 ..];
    if (digits.len == 0) return false;
    for (digits) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// The issue or pull request `target` names, in `self.repository` when it
/// names no repository. After a move between forges, `#24` is the former
/// forge's number when the project declares one (`formerly`) whose map has it,
/// and `kind:owner/repo#24` always names an issue of that former forge.
pub fn ref(self: *const Forge, target: []const u8) ?Ref {
    if (!isRef(target)) return null;
    const hash = std.mem.findScalar(u8, target, '#').?;
    const number = std.fmt.parseInt(u64, target[hash + 1 ..], 10) catch return null;
    if (hash == 0) {
        for (self.formerly) |former| {
            if (self.movedTo(former, number)) |r| return r;
        }
        return .{ .repository = self.repository, .number = number };
    }
    const named = target[0..hash];
    if (std.mem.findScalar(u8, named, ':') != null) {
        if (self.movedTo(named, number)) |r| return r;
        if (self.isOwn(named)) return .{ .repository = self.repository, .number = number };
        return .{ .repository = named, .number = number, .unmapped = true };
    }
    return .{ .repository = named, .number = number };
}

/// Whether `kind_repository` (`gitlab:group/project`) is this forge
fn isOwn(self: *const Forge, kind_repository: []const u8) bool {
    const colon = std.mem.findScalar(u8, kind_repository, ':') orelse return false;
    return std.mem.eql(u8, kind_repository[0..colon], @tagName(self.kind)) and std.mem.eql(u8, kind_repository[colon + 1 ..], self.repository);
}

/// Where issue `number` of the former forge went, when it went to this forge
fn movedTo(self: *const Forge, former: []const u8, number: u64) ?Ref {
    for (self.moved) |m| {
        const from_hash = std.mem.findScalarLast(u8, m.from, '#') orelse continue;
        if (!std.mem.eql(u8, m.from[0..from_hash], former)) continue;
        const old = std.fmt.parseInt(u64, m.from[from_hash + 1 ..], 10) catch continue;
        if (old != number) continue;
        const to_hash = std.mem.findScalarLast(u8, m.to, '#') orelse continue;
        if (!self.isOwn(m.to[0..to_hash])) continue;
        const now = std.fmt.parseInt(u64, m.to[to_hash + 1 ..], 10) catch continue;
        // the same number on both forges: the reference means the same either way
        if (now == number) return .{ .repository = self.repository, .number = now };
        return .{ .repository = self.repository, .number = now, .former = former, .former_number = number };
    }
    return null;
}

/// The host name of the forge: `github.com`, or that of `url`
pub fn host(self: *const Forge) []const u8 {
    const u = self.url orelse return switch (self.kind) {
        .github => "github.com",
        .gitlab => "gitlab.com",
        .forgejo => "codeberg.org",
    };
    const start = if (std.mem.find(u8, u, "://")) |s| s + 3 else 0;
    const end = std.mem.findScalarPos(u8, u, start, '/') orelse u.len;
    return u[start..end];
}

/// The address of the page of `r` in a browser
pub fn page(self: *const Forge, arena: std.mem.Allocator, r: Ref) std.mem.Allocator.Error![]const u8 {
    const base = self.url orelse try arena.print("https://{s}", .{self.host()});
    return arena.print("{s}/{s}/{s}issues/{d}", .{ base, r.repository, if (self.kind == .gitlab) "-/" else "", r.number });
}

// req: forge.refs
test "references to issues and pull requests" {
    const f: Forge = .{ .repository = "chasingdaylight/skein" };
    try std.testing.expect(isRef("#97"));
    try std.testing.expect(isRef("other/repo#12"));
    try std.testing.expect(!isRef("lex.comment"));
    try std.testing.expect(!isRef("#"));
    try std.testing.expect(!isRef("#a1"));
    const own = f.ref("#97").?;
    try std.testing.expectEqualStrings("chasingdaylight/skein", own.repository);
    try std.testing.expectEqual(97, own.number);
    try std.testing.expectEqualStrings("other/repo", f.ref("other/repo#12").?.repository);
    try std.testing.expectEqualStrings("github.com", f.host());
    const enterprise: Forge = .{ .repository = "team/project", .url = "https://github.example.com" };
    try std.testing.expectEqualStrings("github.example.com", enterprise.host());
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("https://github.example.com/team/project/issues/3", try enterprise.page(arena.allocator(), enterprise.ref("#3").?));
    const lab: Forge = .{ .kind = .gitlab, .repository = "group/sub/project" };
    try std.testing.expectEqualStrings("gitlab.com", lab.host());
    try std.testing.expectEqualStrings("https://gitlab.com/group/sub/project/-/issues/3", try lab.page(arena.allocator(), lab.ref("#3").?));
}
