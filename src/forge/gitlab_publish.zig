//! GitLab's requirements kept to the items through GitLab's GraphQL API
//! (#247), where `gitlab_requirements.zig` goes through its CSV import and
//! export. Requirements are work items of the type named "Requirement"
//! (Ultimate): an item without one gets one, made with its title and text,
//! and recorded in the map; one whose requirement says otherwise has it
//! brought back to the item's; a removed item's requirement is closed
//! (archived), and reopened when the item is back. Git stays the truth.
//! The API calls are `workItemCreate` and `workItemUpdate`, as GitLab's
//! GraphQL reference gives them (GitLab 19); the CI report keys on the work
//! item's IID (`requirements_v2`).

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const Graph = @import("../graph/Graph.zig");
const github = @import("github.zig");
const gitlab = @import("gitlab.zig");
const requirements = @import("gitlab_requirements.zig");

/// How the API is asked: GitLab itself, or recorded answers in tests
pub var call: *const fn (Io, std.mem.Allocator, *const Forge, []const u8, []const u8) anyerror!github.Reply = gitlab.graphql;

pub const Wanted = struct {
    item: *const Graph.Item,
    /// removed: its requirement is to be closed
    removed: bool,
};

pub const Kind = enum { created, updated, reopened, archived, same };

pub const Done = struct {
    id: []const u8,
    kind: Kind,
    iid: u64,
};

pub const Outcome = union(enum) {
    done: struct { actions: []const Done, entries: []const requirements.Entry },
    failed: []const u8,
};

/// Brings GitLab's requirements to `wanted`, from the map `entries`; with
/// `dry_run`, only says what it would do
pub fn publish(io: Io, arena: std.mem.Allocator, forge: *const Forge, wanted: []const Wanted, entries: []const requirements.Entry, dry_run: bool, body_path: []const u8) !Outcome {
    var ctx: Ctx = .{ .io = io, .arena = arena, .forge = forge, .body_path = body_path };
    var map: std.StringArrayHashMapUnmanaged(u64) = .empty;
    for (entries) |e| try map.put(arena, e.id, e.iid);
    var actions: std.ArrayList(Done) = .empty;
    var type_id: ?[]const u8 = null;
    for (wanted) |w| {
        const title = try requirements.title(arena, w.item);
        const text = std.mem.trim(u8, w.item.text, " \r\n");
        if (map.get(w.item.id)) |iid| {
            const now = switch (try ctx.workItem(iid)) {
                .found => |f| f,
                .missing => return .{ .failed = try arena.print("{s}: GitLab has no work item {d}; take it out of {s}", .{ w.item.id, iid, requirements.map_file }) },
                .failed => |why| return .{ .failed = why },
            };
            var kind: Kind = .same;
            if (w.removed) {
                if (now.open) kind = .archived;
            } else if (!now.open) {
                kind = .reopened;
            } else if (!std.mem.eql(u8, now.title, title) or !std.mem.eql(u8, std.mem.trim(u8, now.description, " \r\n"), text)) {
                kind = .updated;
            }
            if (kind != .same and !dry_run) {
                if (try ctx.update(now.id, if (w.removed) null else title, if (w.removed) null else text, switch (kind) {
                    .archived => "CLOSE",
                    .reopened => "REOPEN",
                    else => null,
                })) |why| return .{ .failed = try arena.print("{s}: {s}", .{ w.item.id, why }) };
            }
            try actions.append(arena, .{ .id = w.item.id, .kind = kind, .iid = iid });
            continue;
        }
        if (w.removed) continue;
        if (dry_run) {
            try actions.append(arena, .{ .id = w.item.id, .kind = .created, .iid = 0 });
            continue;
        }
        if (type_id == null) type_id = switch (try ctx.requirementType()) {
            .found => |id| id,
            .missing => return .{ .failed = "the project has no work item type 'Requirement' (GitLab Ultimate, with requirements)" },
            .failed => |why| return .{ .failed = why },
        };
        const iid = switch (try ctx.create(type_id.?, title, text)) {
            .found => |n| n,
            .missing => unreachable,
            .failed => |why| return .{ .failed = try arena.print("{s}: {s}", .{ w.item.id, why }) },
        };
        try map.put(arena, w.item.id, iid);
        try actions.append(arena, .{ .id = w.item.id, .kind = .created, .iid = iid });
    }
    var out: std.ArrayList(requirements.Entry) = .empty;
    for (map.keys(), map.values()) |id, iid| try out.append(arena, .{ .id = id, .iid = iid });
    return .{ .done = .{ .actions = actions.items, .entries = out.items } };
}

fn Found(comptime T: type) type {
    return union(enum) { found: T, missing, failed: []const u8 };
}

const WorkItem = struct { id: []const u8, title: []const u8, description: []const u8, open: bool };

const Ctx = struct {
    io: Io,
    arena: std.mem.Allocator,
    forge: *const Forge,
    body_path: []const u8,

    /// The `data` of the answer to `query` with `variables` (JSON), or why not
    fn ask(self: *Ctx, query: []const u8, variables: []const u8) !Found(std.json.Value) {
        const body = try self.arena.print("{{\"query\":{f},\"variables\":{s}}}", .{ std.json.fmt(query, .{}), variables });
        const text = switch (try call(self.io, self.arena, self.forge, body, self.body_path)) {
            .body => |t| t,
            .missing => return .missing,
            .unreachable_ => |why| return .{ .failed = why },
        };
        const v = std.json.parseFromSliceLeaky(std.json.Value, self.arena, text, .{}) catch return .{ .failed = "GitLab gave an answer skein cannot read" };
        if (v != .object) return .{ .failed = "GitLab gave an answer skein cannot read" };
        if (v.object.get("errors")) |errors| if (errors == .array and errors.array.items.len > 0) {
            const first = errors.array.items[0];
            const message = if (first == .object) first.object.get("message") else null;
            return .{ .failed = if (message != null and message.? == .string) message.?.string else "GitLab refused the request" };
        };
        return .{ .found = v.object.get("data") orelse return .{ .failed = "GitLab gave no data" } };
    }

    fn requirementType(self: *Ctx) !Found([]const u8) {
        const data = switch (try self.ask("query($p: ID!) { namespace(fullPath: $p) { workItemTypes { nodes { id name } } } }", try self.arena.print("{{\"p\":{f}}}", .{std.json.fmt(self.forge.repository, .{})}))) {
            .found => |d| d,
            .missing => return .missing,
            .failed => |why| return .{ .failed = why },
        };
        const nodes = path(data, &.{ "namespace", "workItemTypes", "nodes" }) orelse return .missing;
        if (nodes != .array) return .missing;
        for (nodes.array.items) |n| {
            const name = path(n, &.{"name"}) orelse continue;
            const id = path(n, &.{"id"}) orelse continue;
            if (name == .string and id == .string and std.ascii.eqlIgnoreCase(name.string, "Requirement")) return .{ .found = id.string };
        }
        return .missing;
    }

    fn workItem(self: *Ctx, iid: u64) !Found(WorkItem) {
        const vars = try self.arena.print("{{\"p\":{f},\"i\":\"{d}\"}}", .{ std.json.fmt(self.forge.repository, .{}), iid });
        const data = switch (try self.ask("query($p: ID!, $i: String!) { namespace(fullPath: $p) { workItem(iid: $i) { id title state widgets { ... on WorkItemWidgetDescription { description } } } } }", vars)) {
            .found => |d| d,
            .missing => return .missing,
            .failed => |why| return .{ .failed = why },
        };
        const w = path(data, &.{ "namespace", "workItem" }) orelse return .missing;
        if (w != .object) return .missing;
        const id = path(w, &.{"id"}) orelse return .missing;
        const title = path(w, &.{"title"}) orelse return .missing;
        const state = path(w, &.{"state"}) orelse return .missing;
        if (id != .string or title != .string or state != .string) return .missing;
        var description: []const u8 = "";
        if (path(w, &.{"widgets"})) |widgets| if (widgets == .array) for (widgets.array.items) |wd| {
            if (path(wd, &.{"description"})) |d| if (d == .string) {
                description = d.string;
            };
        };
        return .{ .found = .{ .id = id.string, .title = title.string, .description = description, .open = std.mem.eql(u8, state.string, "OPEN") } };
    }

    fn create(self: *Ctx, type_id: []const u8, title: []const u8, text: []const u8) !Found(u64) {
        const vars = try self.arena.print("{{\"p\":{f},\"t\":{f},\"d\":{f},\"ty\":{f}}}", .{ std.json.fmt(self.forge.repository, .{}), std.json.fmt(title, .{}), std.json.fmt(text, .{}), std.json.fmt(type_id, .{}) });
        const data = switch (try self.ask("mutation($p: ID!, $t: String!, $d: String!, $ty: WorkItemsTypeID!) { workItemCreate(input: {namespacePath: $p, title: $t, descriptionWidget: {description: $d}, workItemTypeId: $ty}) { workItem { iid } errors } }", vars)) {
            .found => |d| d,
            .missing => return .{ .failed = "GitLab has no such project" },
            .failed => |why| return .{ .failed = why },
        };
        if (try mutationErrors(self.arena, data, "workItemCreate")) |why| return .{ .failed = why };
        const iid = path(data, &.{ "workItemCreate", "workItem", "iid" }) orelse return .{ .failed = "GitLab made no work item" };
        if (iid != .string) return .{ .failed = "GitLab made no work item" };
        return .{ .found = std.fmt.parseInt(u64, iid.string, 10) catch return .{ .failed = "GitLab gave a work item no IID" } };
    }

    /// null when it was written, else why not
    fn update(self: *Ctx, id: []const u8, title: ?[]const u8, text: ?[]const u8, state_event: ?[]const u8) !?[]const u8 {
        var input: std.ArrayList(u8) = .empty;
        try input.print(self.arena, "{{\"id\":{f}", .{std.json.fmt(id, .{})});
        if (title) |t| try input.print(self.arena, ",\"title\":{f}", .{std.json.fmt(t, .{})});
        if (text) |d| try input.print(self.arena, ",\"descriptionWidget\":{{\"description\":{f}}}", .{std.json.fmt(d, .{})});
        if (state_event) |s| try input.print(self.arena, ",\"stateEvent\":\"{s}\"", .{s});
        try input.append(self.arena, '}');
        const data = switch (try self.ask("mutation($in: WorkItemUpdateInput!) { workItemUpdate(input: $in) { workItem { iid } errors } }", try self.arena.print("{{\"in\":{s}}}", .{input.items}))) {
            .found => |d| d,
            .missing => return "GitLab has no such work item",
            .failed => |why| return why,
        };
        return mutationErrors(self.arena, data, "workItemUpdate");
    }
};

/// The first of a mutation's `errors`; null when there are none
fn mutationErrors(arena: std.mem.Allocator, data: std.json.Value, name: []const u8) !?[]const u8 {
    _ = arena;
    const errors = path(data, &.{ name, "errors" }) orelse return null;
    if (errors != .array or errors.array.items.len == 0) return null;
    const first = errors.array.items[0];
    return if (first == .string) first.string else "GitLab refused the change";
}

fn path(v: std.json.Value, keys: []const []const u8) ?std.json.Value {
    var cur = v;
    for (keys) |k| {
        if (cur != .object) return null;
        cur = cur.object.get(k) orelse return null;
    }
    return cur;
}

test {
    _ = @import("_test/gitlab_publish.zig");
}
