//! What skein reads of Markdown: the blocks of a file, and the markers
//! that make blocks items. Not a renderer.

const blocks = @import("markdown/blocks.zig");

pub const Block = blocks.Block;
pub const Marker = @import("markdown/Marker.zig");
pub const list = @import("markdown/list.zig");
pub const scan = blocks.scan;
pub const references = @import("markdown/references.zig");
pub const fence = @import("markdown/fence.zig");

test {
    _ = blocks;
    _ = Marker;
    _ = list;
    _ = references;
    _ = fence;
}
