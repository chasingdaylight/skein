//! Reading item types, link types and profiles from TOML text.

const std = @import("std");
const testing = std.testing;

const Report = @import("../../Report.zig");
const Schema = @import("../Schema.zig");
const toml = @import("../../toml.zig");

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    report: Report,

    fn init(self: *Fixture) void {
        self.arena = .init(testing.allocator);
        self.report = .{ .arena = self.arena.allocator() };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    fn reader(self: *Fixture, source: []const u8) !Schema.Reader {
        var diag: toml.Diagnostic = .{};
        const a = self.arena.allocator();
        return .{ .report = &self.report, .arena = a, .file = "x.toml", .table = try toml.parse(a, source, &diag) };
    }

    fn expectProblems(self: *Fixture, expected: []const u8) !void {
        try testing.expectEqualStrings(expected, try self.report.render(self.arena.allocator()));
    }
};

test "an item type with everything declared" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const t = try Schema.ItemType.read(try f.reader(
        \\description = "A software requirement"
        \\id = "numbered"
        \\prefix = "SRS"
        \\digits = 4
        \\categories = ["functional", "performance"]
        \\statuses = ["draft", "baselined", "retired"]
        \\tombstone = "retired"
        \\verification = ["test", "analysis", "inspection", "demonstration"]
        \\[attributes.priority]
        \\values = ["low", "high"]
        \\required = true
        \\[attributes.due]
        \\type = "date"
        \\normative = true
    ), "srs");
    try f.expectProblems("");
    try testing.expectEqualStrings("srs", t.name);
    try testing.expectEqualStrings("SRS", t.id.numbered.prefix);
    try testing.expectEqual(4, t.id.numbered.digits);
    try testing.expectEqual(2, t.categories.len);
    try testing.expectEqualStrings("retired", t.tombstone.?);
    try testing.expectEqual(4, t.verification.len);
    try testing.expect(t.attribute("priority").?.required);
    try testing.expectEqual(.date, t.attribute("due").?.kind);
    try testing.expect(t.attribute("due").?.normative);
    try testing.expectEqual(null, t.attribute("other"));
}

test "an empty item type takes the defaults" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const t = try Schema.ItemType.read(try f.reader(""), "rule");
    try f.expectProblems("");
    try testing.expectEqual(.hierarchical, std.meta.activeTag(t.id));
    try testing.expectEqual(4, t.statuses.len);
    try testing.expectEqualStrings("removed", t.tombstone.?);
}

test "statuses without \"removed\" leave the type without a tombstone" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const t = try Schema.ItemType.read(try f.reader("statuses = [\"open\", \"closed\"]"), "task");
    try f.expectProblems("");
    try testing.expectEqual(null, t.tombstone);
}

test "mistakes in an item type are each reported" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    _ = try Schema.ItemType.read(try f.reader(
        \\descripton = "typo"
        \\id = "numbered"
        \\digits = 12
        \\categories = "one"
        \\tombstone = "gone"
        \\[attributes.Priority]
        \\type = "text"
        \\[attributes.count]
        \\type = "integer"
        \\values = ["1"]
        \\maximum = 3
    ), "srs");
    try f.expectProblems(
        \\x.toml: error: attributes.Priority.type: expected "string", "integer", "boolean" or "date"
        \\x.toml: error: attributes.Priority: a name is lowercase letters, digits, '-' and '_', starting with a letter
        \\x.toml: error: attributes.count.maximum: unknown key
        \\x.toml: error: attributes.count.values: only a string attribute lists its values
        \\x.toml: error: categories: expected an array of strings
        \\x.toml: error: descripton: unknown key
        \\x.toml: error: digits: expected 1 to 9
        \\x.toml: error: prefix: a type with numbered IDs needs a prefix
        \\x.toml: error: tombstone: 'gone' is not one of the statuses
        \\
    );
}

test "a link type and a profile" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const l = try Schema.LinkType.read(try f.reader(
        \\description = "A test verifies a rule"
        \\from = ["test"]
        \\to = ["rule"]
        \\expected = true
    ), "verifies");
    const p = try Schema.Profile.read(try f.reader(
        \\types = ["rule"]
        \\statuses = ["approved"]
        \\[where]
        \\stage = "s0"
        \\class = ["a", "b"]
    ), "s0");
    try f.expectProblems("");
    try testing.expect(l.expected and !l.required);
    try testing.expectEqualStrings("rule", l.to[0]);
    try testing.expectEqualStrings("stage", p.where[0].attribute);
    try testing.expectEqualStrings("s0", p.where[0].values[0]);
    try testing.expectEqual(2, p.where[1].values.len);
}

test "a schema's parts are checked against each other" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    const schema: Schema = .{
        .types = &.{.{ .name = "rule", .categories = &.{"syntax"}, .attributes = &.{.{ .name = "stage" }} }},
        .links = &.{.{ .name = "verifies", .from = &.{"test"}, .to = &.{"rule"} }},
        .profiles = &.{
            .{ .name = "good", .types = &.{"rule"}, .categories = &.{"syntax"}, .statuses = &.{"approved"}, .where = &.{.{ .attribute = "stage", .values = &.{"s0"} }} },
            .{ .name = "bad", .types = &.{"need"}, .categories = &.{"legality"}, .statuses = &.{"frozen"}, .where = &.{.{ .attribute = "class", .values = &.{"a"} }} },
        },
    };
    try testing.expect(schema.itemType("rule") != null);
    try testing.expect(schema.linkType("verifies") != null);
    try testing.expect(schema.profile("good") != null);
    try testing.expectEqual(null, schema.itemType("test"));
    try schema.validate(&f.report, ".skein");
    try f.expectProblems(
        \\.skein/links/verifies.toml: error: from: there is no item type 'test'
        \\.skein/profiles/bad.toml: error: categories: no item type of the profile has the category 'legality'
        \\.skein/profiles/bad.toml: error: statuses: no item type of the profile has the status 'frozen'
        \\.skein/profiles/bad.toml: error: types: there is no item type 'need'
        \\.skein/profiles/bad.toml: error: where: no item type of the profile has the attribute 'class'
        \\
    );
}

test "names that skein reads itself, or that a link type has" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    _ = try Schema.ItemType.read(try f.reader("[attributes.status]\n"), "rule");
    const schema: Schema = .{
        .types = &.{.{ .name = "rule", .attributes = &.{.{ .name = "verifies" }} }},
        .links = &.{ .{ .name = "verifies" }, .{ .name = "category" } },
    };
    try schema.validate(&f.report, ".skein");
    try f.expectProblems(
        \\.skein/links/category.toml: error: skein reads the key 'category' itself, so no link type can have the name
        \\.skein/types/rule.toml: error: attributes.verifies: a link type has this name, so no attribute can
        \\x.toml: error: attributes.status: skein reads this key itself, so no attribute can have the name
        \\
    );
}
