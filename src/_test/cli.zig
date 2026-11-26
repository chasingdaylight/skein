//! The command line: commands, their options, and the mistakes reported.

// req: cli.commands, cli.options, principle.no-silent-mistakes
const std = @import("std");
const testing = std.testing;

const cli = @import("../cli.zig");
const Command = cli.Command;
const parse = cli.parse;

/// A parser for tests, whose arena is freed with `deinit`
const Fixture = struct {
    arena: std.heap.ArenaAllocator,

    fn init() Fixture {
        return .{ .arena = .init(testing.allocator) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    fn run(self: *Fixture, args: []const []const u8) !Command {
        return parse(self.arena.allocator(), args);
    }
};

test "no arguments ask for help" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(Command.help, try f.run(&.{}));
}

test "help and version, as commands and as options" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(Command.help, try f.run(&.{"help"}));
    try testing.expectEqual(Command.help, try f.run(&.{"--help"}));
    try testing.expectEqual(Command.help, try f.run(&.{"-h"}));
    try testing.expectEqual(Command.version, try f.run(&.{"version"}));
    try testing.expectEqual(Command.version, try f.run(&.{"--version"}));
}

test "an unknown command is reported by name" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings("frobnicate", (try f.run(&.{ "frobnicate", "x" })).unknown);
}

test "options: values, unknown ones, and ones that do not go with the command" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings(".", (try f.run(&.{"check"})).check.common.root);
    try testing.expectEqualStrings("docs", (try f.run(&.{ "check", "--root", "docs" })).check.common.root);
    try testing.expectEqualStrings("--root needs a value after it", (try f.run(&.{ "check", "--root" })).misuse);
    try testing.expectEqualStrings("check takes no items", (try f.run(&.{ "check", "everything" })).misuse);
    try testing.expectEqualStrings("unknown option --fast", (try f.run(&.{ "check", "--fast" })).misuse);
    try testing.expectEqualStrings("--json does not go with check", (try f.run(&.{ "check", "--json" })).misuse);
    try testing.expectEqualStrings("--profile does not go with trace", (try f.run(&.{ "trace", "a.b", "--profile", "s0" })).misuse);
}

test "trace takes one item" {
    var f: Fixture = .init();
    defer f.deinit();
    const t = (try f.run(&.{ "trace", "--json", "a.b" })).trace;
    try testing.expectEqualStrings("a.b", t.id);
    try testing.expect(t.json);
    try testing.expectEqualStrings("trace takes one item", (try f.run(&.{"trace"})).misuse);
    try testing.expectEqualStrings("trace takes one item", (try f.run(&.{ "trace", "a", "b" })).misuse);
}

test "coverage takes a profile" {
    var f: Fixture = .init();
    defer f.deinit();
    const c = (try f.run(&.{ "coverage", "--profile", "s0", "--json" })).coverage;
    try testing.expectEqualStrings("s0", c.profile.?);
    try testing.expect(c.json);
    try testing.expectEqual(null, (try f.run(&.{"coverage"})).coverage.profile);
    try testing.expectEqualStrings("--profile needs a value after it", (try f.run(&.{ "coverage", "--profile" })).misuse);
}

test "review and clear take items, or all" {
    var f: Fixture = .init();
    defer f.deinit();
    const review = (try f.run(&.{ "review", "a.b", "--root", "docs", "c.d" })).review;
    try testing.expectEqual(2, review.ids.len);
    try testing.expectEqualStrings("c.d", review.ids[1]);
    try testing.expectEqualStrings("docs", review.common.root);
    try testing.expect(!review.all);
    try testing.expect((try f.run(&.{ "clear", "--all" })).clear.all);
    try testing.expectEqualStrings("name the items, or give --all", (try f.run(&.{"review"})).misuse);
    try testing.expectEqualStrings("name the items, or give --all", (try f.run(&.{ "clear", "a.b", "--all" })).misuse);
}

test "approve takes items, and who and when" {
    var f: Fixture = .init();
    defer f.deinit();
    const approve = (try f.run(&.{ "approve", "SRS-001", "--by", "A. Reviewer", "--on", "2027-03-01", "SRS-002" })).approve;
    try testing.expectEqual(2, approve.ids.len);
    try testing.expectEqualStrings("A. Reviewer", approve.by.?);
    try testing.expectEqualStrings("2027-03-01", approve.on.?);
    try testing.expectEqual(null, (try f.run(&.{ "approve", "a.b" })).approve.by);
    try testing.expectEqualStrings("name the items to approve", (try f.run(&.{"approve"})).misuse);
}

test "diff and impact take commits" {
    var f: Fixture = .init();
    defer f.deinit();
    const d = (try f.run(&.{ "diff", "v0.1", "HEAD", "--json" })).diff;
    try testing.expectEqual(2, d.revisions.len);
    try testing.expectEqualStrings("HEAD", d.revisions[1]);
    try testing.expect(d.json and !d.impact and !d.markdown);
    const i = (try f.run(&.{ "impact", "--markdown" })).diff;
    try testing.expect(i.impact and i.markdown);
    try testing.expectEqual(0, i.revisions.len);
    try testing.expectEqualStrings("diff takes one commit or two", (try f.run(&.{ "diff", "a", "b", "c" })).misuse);
    try testing.expectEqualStrings("impact takes one commit: it is about the project as it is now", (try f.run(&.{ "impact", "a", "b" })).misuse);
    try testing.expectEqualStrings("give --json or --markdown, not both", (try f.run(&.{ "diff", "--json", "--markdown" })).misuse);
}

test "export takes what to export" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(.json, (try f.run(&.{"export"})).exporting.what);
    const e = (try f.run(&.{ "export", "links", "--profile", "s0" })).exporting;
    try testing.expectEqual(.links, e.what);
    try testing.expectEqualStrings("s0", e.profile.?);
    try testing.expectEqualStrings("export: json, items, links, citations or gitlab-requirements", (try f.run(&.{ "export", "everything" })).misuse);
}

test "lsp takes nothing but the transport" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(.lsp, try f.run(&.{"lsp"}));
    try testing.expectEqual(.lsp, try f.run(&.{ "lsp", "--stdio" }));
    try testing.expectEqualStrings("lsp takes no arguments", (try f.run(&.{ "lsp", "--port", "1" })).misuse);
}

test "link takes two items and a type" {
    var f: Fixture = .init();
    defer f.deinit();
    const l = (try f.run(&.{ "link", "c.one", "verifies", "lex.a" })).link;
    try testing.expectEqualStrings("c.one", l.from);
    try testing.expectEqualStrings("verifies", l.type_name);
    try testing.expectEqualStrings("lex.a", l.to);
    try testing.expectEqualStrings("link takes the item, the link type, and the item to link to", (try f.run(&.{ "link", "c.one" })).misuse);
}

test "the forge commands: mirror, sync, publish with its forge and address, rewrite-refs" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqual(false, (try f.run(&.{"mirror"})).mirror.common.offline);
    try testing.expect((try f.run(&.{ "sync", "--dry-run" })).sync.dry_run);
    const p = (try f.run(&.{ "publish", "--to", "gitlab:group/project", "--url", "http://gitlab.example:8080", "--dry-run" })).publish;
    try testing.expectEqualStrings("gitlab:group/project", p.to.?);
    try testing.expectEqualStrings("http://gitlab.example:8080", p.url.?);
    try testing.expect(p.dry_run);
    try testing.expect((try f.run(&.{ "rewrite-refs", "--dry-run" })).rewrite_refs.dry_run);
}

test "new takes a type, and maybe an ID" {
    var f: Fixture = .init();
    defer f.deinit();
    const n = (try f.run(&.{ "new", "srs", "--to", "requirements" })).new;
    try testing.expectEqualStrings("srs", n.type_name);
    try testing.expectEqual(null, n.id);
    try testing.expectEqualStrings("requirements", n.to.?);
    try testing.expectEqualStrings("lex.a", (try f.run(&.{ "new", "rule", "lex.a" })).new.id.?);
    try testing.expectEqualStrings("new takes an item type, and the ID where the type's IDs are not numbered", (try f.run(&.{"new"})).misuse);
}

test "move takes two IDs" {
    var f: Fixture = .init();
    defer f.deinit();
    const m = (try f.run(&.{ "move", "lex.a", "lex.b" })).move;
    try testing.expectEqualStrings("lex.a", m.old);
    try testing.expectEqualStrings("lex.b", m.new);
    try testing.expectEqualStrings("move takes the ID an item has, and the ID it is to have", (try f.run(&.{ "move", "lex.a" })).misuse);
}

test "render needs a place to write to" {
    var f: Fixture = .init();
    defer f.deinit();
    try testing.expectEqualStrings("site", (try f.run(&.{ "render", "--out", "site", "--format", "markdown" })).render.out);
    try testing.expectEqualStrings("render: say where the files go, with --out DIR", (try f.run(&.{"render"})).misuse);
    try testing.expectEqual(.html, (try f.run(&.{ "render", "--out", "x", "--format", "html" })).render.format);
    try testing.expectEqualStrings("render: the formats are markdown, html and document", (try f.run(&.{ "render", "--out", "x", "--format", "pdf" })).misuse);
}

test "import takes a format and what to import" {
    var f: Fixture = .init();
    defer f.deinit();
    const i = (try f.run(&.{ "import", "doorstop", "docs/sys", "docs/srs" })).import;
    try testing.expectEqual(.doorstop, i.format);
    try testing.expectEqual(2, i.paths.len);
    try testing.expectEqualStrings("docs/srs", i.paths[1]);
    try testing.expect(std.mem.startsWith(u8, (try f.run(&.{"import"})).misuse, "import: doorstop DIR..."));
    try testing.expect(std.mem.startsWith(u8, (try f.run(&.{ "import", "excel", "x" })).misuse, "import: doorstop DIR..."));
    try testing.expectEqualStrings("import doorstop: name the directories of the Doorstop documents", (try f.run(&.{ "import", "doorstop" })).misuse);
}

test "pin, and the state of the other repositories" {
    var f: Fixture = .init();
    defer f.deinit();
    const all = (try f.run(&.{"pin"})).pin;
    try testing.expectEqual(null, all.name);
    const one = (try f.run(&.{ "pin", "compiler", "v1.2" })).pin;
    try testing.expectEqualStrings("compiler", one.name.?);
    try testing.expectEqualStrings("v1.2", one.revision.?);
    try testing.expectEqualStrings("pin takes a repository, and a commit of it", (try f.run(&.{ "pin", "a", "b", "c" })).misuse);
    try testing.expectEqual(.recorded, (try f.run(&.{"check"})).check.common.state);
    try testing.expectEqual(.current, (try f.run(&.{ "check", "--current" })).check.common.state);
    try testing.expectEqual(.working, (try f.run(&.{ "trace", "x", "--working" })).trace.common.state);
    try testing.expectEqualStrings("give --current or --working, not both", (try f.run(&.{ "check", "--current", "--working" })).misuse);
    try testing.expect((try f.run(&.{ "pin", "--offline" })).pin.common.offline);
    try testing.expect((try f.run(&.{ "render", "--out", "x", "--offline" })).render.common.offline);
    try testing.expectEqualStrings("--current does not go with pin", (try f.run(&.{ "pin", "--current" })).misuse);
}
