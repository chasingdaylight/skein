//! What makes an item type work: its `[planning]` table, which says which
//! of its attributes holds each planning role. skein names no attribute
//! itself (`principle.schema-driven`), so a project names them as it likes.
//!
//!     [attributes.start]
//!     type = "date"
//!     [attributes.days]
//!     type = "integer"
//!
//!     [planning]
//!     start = "start"
//!     duration = "days"

const std = @import("std");

const Attribute = @import("ItemType.zig").Attribute;
const Reader = @import("Reader.zig");

const Planning = @This();

/// The attribute of each role; null for a role the type does not have
roles: std.EnumArray(Role, ?[]const u8) = .initFill(null),

pub const Role = enum {
    start,
    finish,
    /// working days, from the first to the last
    duration,
    /// the effort expected, in days
    estimate,
    /// the effort still to do, in days
    remaining,
    assignees,
    priority,
    milestone,
    /// `fixed` (the dates written are kept) or `float` (scheduled)
    mode,
    /// days to wait after the predecessors finish
    lag,

    /// The kind of attribute the role takes; null when any
    pub fn kind(role: Role) ?Attribute.Kind {
        return switch (role) {
            .start, .finish => .date,
            .duration, .estimate, .remaining, .lag => .integer,
            .mode => .string,
            .assignees, .priority, .milestone => null,
        };
    }
};

pub const Mode = enum { fixed, float };

/// What a link type is to the schedule, by its `[planning] role`
pub const LinkRole = enum {
    /// finish to start: the target starts once the item has finished
    precedes,
    /// the item is part of its target
    parent,
    /// the item blocks its target, without scheduling it
    blocks,
};

pub fn attribute(self: *const Planning, role: Role) ?[]const u8 {
    return self.roles.get(role);
}

/// The `[planning]` table of an item type whose attributes are
/// `attributes`; problems go to the reader's report
pub fn read(r: Reader, attributes: []const Attribute) Reader.Error!Planning {
    var out: Planning = .{};
    const fields = @typeInfo(Role).@"enum".field_names;
    try r.known(fields);
    inline for (fields) |name| {
        const role = @field(Role, name);
        if (try r.string(name)) |attr_name| {
            out.roles.set(role, attr_name);
            const declared = for (attributes) |*a| {
                if (std.mem.eql(u8, a.name, attr_name)) break a;
            } else null;
            if (declared) |a| {
                if (role.kind()) |k| if (a.kind != k) try r.complain(name, "the attribute '{s}' must be of type \"{t}\" for {s}", .{ attr_name, k, name });
                if (role == .mode) for (a.values) |v| {
                    if (std.meta.stringToEnum(Mode, v) == null) try r.complain(name, "the attribute '{s}' may only have the values \"fixed\" and \"float\"", .{attr_name});
                };
            } else try r.complain(name, "there is no attribute '{s}' (declare it under [attributes])", .{attr_name});
        }
    }
    return out;
}

/// The `[planning]` table of a link type: its role
pub fn readLink(r: Reader) Reader.Error!?LinkRole {
    try r.known(&.{"role"});
    const role = try r.string("role") orelse {
        try r.complain("role", "a link type's [planning] needs a role: \"precedes\", \"parent\" or \"blocks\"", .{});
        return null;
    };
    return std.meta.stringToEnum(LinkRole, role) orelse {
        try r.complain("role", "expected \"precedes\", \"parent\" or \"blocks\"", .{});
        return null;
    };
}
