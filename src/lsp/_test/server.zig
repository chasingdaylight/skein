//! The language server, given messages as an editor sends them, on a
//! project on disk.

// req: lsp.lifecycle, lsp.diagnostics, lsp.definition, lsp.references, lsp.hover, lsp.completion, lsp.rename
const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const json = std.json;

const Server = @import("../Server.zig");
const jsonrpc = @import("../jsonrpc.zig");
const uri_paths = @import("../uri.zig");

fn write(dir: Io.Dir, path: []const u8, data: []const u8) !void {
    if (Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

const lex =
    \\# Lexical structure
    \\
    \\Narrative about %[lex.token the token].
    \\
    \\%rule[lex.token syntax] A token.
    \\
    \\%rule[lex.keywords syntax] The keywords are %[lex.token tokens]:
    \\
    \\- %rule[.as syntax] `as`, see %[lex.gone].
    \\
    \\%case[c.one verifies=lex.token] Checks.
    \\
;

/// A server on a project in a temporary directory, and what it has sent
const Session = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    out: Io.Writer.Allocating,
    server: Server,
    root: []const u8,
    next_id: i64 = 1,

    fn init(self: *Session) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.out = .init(testing.allocator);
        self.next_id = 1;
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// spec:\"\n");
        try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
        try write(dir, ".skein/types/case.toml", "");
        try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\n");
        try write(dir, "spec/lex.md", lex);
        try write(dir, "tests/a.zig", "// spec: lex.token\n");
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.server = .{ .gpa = testing.allocator, .io = testing.io, .out = &self.out.writer, .version = "test" };
    }

    fn deinit(self: *Session) void {
        self.server.deinit();
        self.out.deinit();
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn uri(self: *Session, file: []const u8) ![]const u8 {
        const a = self.arena.allocator();
        return uri_paths.fromPath(a, try Io.Dir.path.join(a, &.{ self.root, file }), self.server.style);
    }

    /// Sends a message and returns what the server sent for it, parsed
    fn send(self: *Session, comptime fmt: []const u8, args: anytype) ![]const json.Value {
        const a = self.arena.allocator();
        self.out.clearRetainingCapacity();
        try self.server.handle(a, try std.fmt.allocPrint(a, fmt, args));
        var reader: Io.Reader = .fixed(self.out.written());
        var messages: std.ArrayList(json.Value) = .empty;
        while (try jsonrpc.readMessage(a, &reader)) |body| {
            try messages.append(a, try json.parseFromSliceLeaky(json.Value, a, body, .{}));
        }
        return messages.items;
    }

    fn start(self: *Session) !void {
        const answer = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"rootUri\":\"{s}\"}}}}", .{try self.uri("")});
        try testing.expectEqual(1, answer.len);
        try testing.expect(answer[0].object.get("result").?.object.get("capabilities").?.object.get("definitionProvider").?.bool);
    }

    /// The result of a request at a place in the specification
    fn at(self: *Session, method: []const u8, line: usize, character: usize) !json.Value {
        self.next_id += 1;
        const answer = try self.send(
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"textDocument/{s}\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}}}}}}",
            .{ self.next_id, method, try self.uri("spec/lex.md"), line, character },
        );
        try testing.expectEqual(1, answer.len);
        return answer[0].object.get("result").?;
    }
};

fn rangeLine(location: json.Value) i64 {
    return location.object.get("range").?.object.get("start").?.object.get("line").?.integer;
}

test "the problems of the project are published, and cleared when they are gone" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();

    const published = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{{}}}}", .{});
    try testing.expectEqual(1, published.len);
    try testing.expectEqualStrings("textDocument/publishDiagnostics", published[0].object.get("method").?.string);
    const params = published[0].object.get("params").?.object;
    try testing.expectEqualStrings(try s.uri("spec/lex.md"), params.get("uri").?.string);
    const diagnostics = params.get("diagnostics").?.array.items;
    try testing.expectEqual(1, diagnostics.len);
    try testing.expectEqualStrings("lex.keywords.as: the text refers to 'lex.gone', and there is no such item", diagnostics[0].object.get("message").?.string);
    try testing.expectEqual(8, rangeLine(diagnostics[0]));
    try testing.expectEqualStrings("skein", diagnostics[0].object.get("source").?.string);

    // the file is mended and saved: its problems are taken back
    const mended = try std.mem.replaceOwned(u8, s.arena.allocator(), lex, ", see %[lex.gone]", "");
    try write(s.tmp.dir, "spec/lex.md", mended);
    const cleared = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}}}}}}", .{try s.uri("spec/lex.md")});
    try testing.expectEqual(1, cleared.len);
    try testing.expectEqual(0, cleared[0].object.get("params").?.object.get("diagnostics").?.array.items.len);
    // and nothing more is said while nothing is wrong
    try testing.expectEqual(0, (try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}}}}}}", .{try s.uri("spec/lex.md")})).len);
}

test "go to definition, from a reference, a link and a marker with a dot" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();

    // on %[lex.token the token] in the narrative
    const from_reference = try s.at("definition", 2, 20);
    try testing.expectEqualStrings(try s.uri("spec/lex.md"), from_reference.object.get("uri").?.string);
    try testing.expectEqual(4, rangeLine(from_reference));
    // on verifies=lex.token
    try testing.expectEqual(4, rangeLine(try s.at("definition", 10, 22)));
    // on %rule[.as ...]: the part that the marker declares
    try testing.expectEqual(8, rangeLine(try s.at("definition", 8, 9)));
    // on a word that is no ID
    try testing.expect((try s.at("definition", 0, 4)) == .null);
}

test "find references: in items, in narrative, in links and in citations" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();

    const found = (try s.at("references", 4, 8)).array.items;
    // the marker, the reference in the keywords, the link of the case, the narrative, the citation
    try testing.expectEqual(5, found.len);
    try testing.expectEqual(4, rangeLine(found[0]));
    try testing.expectEqual(6, rangeLine(found[1]));
    try testing.expectEqual(10, rangeLine(found[2]));
    try testing.expectEqual(2, rangeLine(found[3]));
    try testing.expectEqualStrings(try s.uri("tests/a.zig"), found[4].object.get("uri").?.string);
}

test "hover shows the item, and what the editor has not saved is used" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();

    const shown = (try s.at("hover", 6, 10)).object.get("contents").?.object.get("value").?.string;
    try testing.expectEqualStrings("**lex.keywords** (rule, syntax, draft)\n\nThe keywords are %[lex.token tokens]:\n\nParts: `lex.keywords.as`", shown);

    // the editor's text has a line more at the top than the file
    _ = try s.send(
        "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"text\":\"See lex.token here.\\n\"}}}}}}",
        .{try s.uri("spec/lex.md")},
    );
    const unsaved = (try s.at("hover", 0, 6)).object.get("contents").?.object.get("value").?.string;
    try testing.expect(std.mem.startsWith(u8, unsaved, "**lex.token** (rule, syntax, draft)"));
}

test "the lifecycle: nothing before initialize, and a clean end" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();

    const early = try s.send("{{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/hover\",\"params\":{{}}}}", .{});
    try testing.expectEqual(-32002, early[0].object.get("error").?.object.get("code").?.integer);
    try s.start();
    const unknown = try s.send("{{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"textDocument/formatting\",\"params\":{{}}}}", .{});
    try testing.expectEqual(-32601, unknown[0].object.get("error").?.object.get("code").?.integer);
    try testing.expectEqual(1, (try s.send("not json", .{})).len);

    try testing.expectEqual(1, s.server.exitCode());
    _ = try s.send("{{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"shutdown\"}}", .{});
    _ = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}}", .{});
    try testing.expect(!s.server.running);
    try testing.expectEqual(0, s.server.exitCode());
}

/// The labels a completion offers at the end of `text`, written as the
/// first line of what the editor shows of `file`
fn labels(s: *Session, file: []const u8, text: []const u8) ![]const []const u8 {
    const a = s.arena.allocator();
    _ = try s.send(
        "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"contentChanges\":[{{\"text\":{f}}}]}}}}",
        .{ try s.uri(file), json.fmt(text, .{}) },
    );
    s.next_id += 1;
    const answer = try s.send(
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"textDocument/completion\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":0,\"character\":{d}}}}}}}",
        .{ s.next_id, try s.uri(file), text.len },
    );
    var out: std.ArrayList([]const u8) = .empty;
    const result = answer[0].object.get("result").?;
    if (result != .array) return out.items;
    for (result.array.items) |item| try out.append(a, item.object.get("label").?.string);
    return out.items;
}

fn expectLabels(expected: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| try testing.expectEqualStrings(e, g);
}

test "completion: item types, IDs, and the words and values of a marker" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();
    try write(s.tmp.dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\nverification = [\"test\"]\n[attributes.stage]\nvalues = [\"s0\", \"s1\"]\n");
    try write(s.tmp.dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\n");

    try expectLabels(&.{ "case", "rule" }, try labels(&s, "spec/lex.md", "- %ru"));
    // every item that is there, for a reference
    try expectLabels(&.{ "lex.token", "lex.keywords", "lex.keywords.as", "c.one" }, try labels(&s, "spec/lex.md", "See %[lex."));
    // a rule: its category, its statuses, its attribute, and no link a rule cannot have
    try expectLabels(&.{ "syntax", "draft", "approved", "deprecated", "removed", "stage", "verification" }, try labels(&s, "spec/lex.md", "%rule[lex.new "));
    try expectLabels(&.{ "s0", "s1" }, try labels(&s, "spec/lex.md", "%rule[lex.new stage="));
    try expectLabels(&.{"test"}, try labels(&s, "spec/lex.md", "%rule[lex.new verification="));
    // a link of a case: the rules it may point to, not other cases
    try expectLabels(&.{ "lex.token", "lex.keywords", "lex.keywords.as" }, try labels(&s, "spec/lex.md", "%case[c.two verifies=lex.token,"));
    // in a test: the IDs after the citation marker
    try expectLabels(&.{ "lex.token", "lex.keywords", "lex.keywords.as", "c.one" }, try labels(&s, "tests/a.zig", "// spec: lex.token, "));
    // and nothing where nothing of skein's is being written
    try expectLabels(&.{}, try labels(&s, "spec/lex.md", "Plain text"));
    try expectLabels(&.{}, try labels(&s, "spec/lex.md", "%rule[lex.new"));
}

test "a completion replaces the word being written" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();
    _ = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"contentChanges\":[{{\"text\":\"See %[lex.to\"}}]}}}}", .{try s.uri("spec/lex.md")});
    const answer = try s.send("{{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/completion\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":0,\"character\":12}}}}}}", .{try s.uri("spec/lex.md")});
    const first = answer[0].object.get("result").?.array.items[0].object;
    try testing.expectEqualStrings("rule, syntax", first.get("detail").?.string);
    const edit = first.get("textEdit").?.object;
    try testing.expectEqualStrings("lex.token", edit.get("newText").?.string);
    const range = edit.get("range").?.object;
    try testing.expectEqual(6, range.get("start").?.object.get("character").?.integer);
    try testing.expectEqual(12, range.get("end").?.object.get("character").?.integer);
}

fn renameAt(s: *Session, line: usize, character: usize, new_name: []const u8) !json.Value {
    s.next_id += 1;
    const answer = try s.send(
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"textDocument/rename\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}},\"newName\":\"{s}\"}}}}",
        .{ s.next_id, try s.uri("spec/lex.md"), line, character, new_name },
    );
    return answer[0];
}

fn errorMessage(answer: json.Value) []const u8 {
    return answer.object.get("error").?.object.get("message").?.string;
}

test "rename from the editor: the item is moved everywhere, once the files are saved" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    try s.start();
    const a = s.arena.allocator();

    // on %[lex.token the token] in the narrative
    const prepared = try s.at("prepareRename", 2, 20);
    try testing.expectEqualStrings("lex.token", prepared.object.get("placeholder").?.string);

    // an unsaved document stops it
    _ = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"text\":\"changed\"}}}}}}", .{try s.uri("spec/lex.md")});
    try testing.expectEqualStrings("skein: save spec/lex.md first: the rename is made in the files", errorMessage(try renameAt(&s, 2, 20, "lex.lexeme")));

    // saved: the rename is made
    _ = try s.send("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}}}}}}", .{try s.uri("spec/lex.md")});
    const done = try renameAt(&s, 2, 20, "lex.lexeme");
    try testing.expect(done.object.get("result") != null);
    const spec = try s.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 20));
    try testing.expect(std.mem.find(u8, spec, "%rule[lex.lexeme syntax] A token.") != null);
    try testing.expect(std.mem.find(u8, spec, "verifies=lex.lexeme]") != null);
    try testing.expectEqualStrings("// spec: lex.lexeme\n", try s.tmp.dir.readFileAlloc(testing.io, "tests/a.zig", a, .limited(1 << 20)));

    // a name that cannot be is refused with the reason skein gives
    try testing.expectEqualStrings("skein: the ID 'lex.keywords' is taken", errorMessage(try renameAt(&s, 4, 8, "lex.keywords")));
}
