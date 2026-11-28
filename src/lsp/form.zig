//! skein's requests for the editor's item forms (edit/form.zig):
//!
//! - `skein/form` (`{ "id": ID }` or `{ "type": TYPE }`): what a form shows
//! - `skein/saveItem`: writes a form into the item's marker or front
//!   matter, or starts a new item as `skein new` does (edit/item_form.zig)

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Server = @import("Server.zig");
const edit_form = @import("../edit/form.zig");
const item_form = @import("../edit/item_form.zig");
const protocol = @import("protocol.zig");

pub fn form(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    var ws = s.open(a, params) orelse return s.respond(a, id, null);
    defer ws.close();
    const want_id = Server.field(params, "id");
    const want_type = Server.field(params, "type");
    switch (try edit_form.build(s.io, a, &ws, if (want_id == .string) want_id.string else null, if (want_type == .string) want_type.string else null)) {
        .ok => |f| try s.respond(a, id, f),
        .refused => |why| try s.respondError(a, id, protocol.error_codes.invalid_params, why),
    }
}

pub fn save(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const p = Server.parse(edit_form.Save, a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein/saveItem: no type");
    var ws = s.open(a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    switch (try item_form.write(s.io, a, &ws, p)) {
        .refused => |why| return s.respondError(a, id, protocol.error_codes.invalid_params, why),
        .written => |w| try s.respond(a, id, .{ .id = w.id, .uri = try s.uriOf(a, &ws, w.file), .line = w.line }),
    }
    try s.publishAll(a);
}
