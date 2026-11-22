//! What a TOML document holds.

const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: Datetime,
    array: *Array,
    table: *Table,
};

/// Where a key or a table header is in its document: 1-based
pub const Place = struct { line: u32 = 0, column: u32 = 0 };

pub const Table = struct {
    /// keys in the order the document gives them
    map: std.array_hash_map.String(Value) = .empty,
    kind: Kind = .implicit,
    /// where each key of the table is written, by key
    places: std.array_hash_map.String(Place) = .empty,
    /// where the table's header is; nothing for the root and for tables
    /// made on the way
    place: Place = .{},

    pub const Kind = enum {
        root,
        /// made on the way to a deeper `[a.b]`; a later `[a]` may define it
        implicit,
        /// defined by `[a]` or as an element of `[[a]]`
        header,
        /// made by a dotted key (`a.b = 1`)
        dotted,
        /// `{ ... }`: closed once written
        inline_table,
    };

    pub fn get(self: *const Table, key: []const u8) ?Value {
        return self.map.get(key);
    }

    /// Where `key` is written; else where the table's header is
    pub fn placeOf(self: *const Table, key: []const u8) Place {
        return self.places.get(key) orelse self.place;
    }

    pub fn keys(self: *const Table) []const []const u8 {
        return self.map.keys();
    }
};

pub const Array = struct {
    items: std.ArrayList(Value) = .empty,
    /// made by `[[name]]` headers, not written as `[ ... ]`
    of_tables: bool = false,

    pub fn values(self: *const Array) []const Value {
        return self.items.items;
    }
};

/// A date, a time, or both; with an offset from UTC only when both.
pub const Datetime = struct {
    date: ?Date = null,
    time: ?Time = null,
    offset_minutes: ?i16 = null,
};

pub const Date = struct { year: u16, month: u8, day: u8 };

pub const Time = struct { hour: u8, minute: u8, second: u8 = 0, nanosecond: u32 = 0 };
