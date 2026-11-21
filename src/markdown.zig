//! What skein reads of Markdown: the blocks of a file, and the markers
//! that make blocks items. Not a renderer.

const blocks = @import("markdown/blocks.zig");

pub const Block = blocks.Block;
pub const Marker = @import("markdown/Marker.zig");
pub const scan = blocks.scan;

test {
    _ = blocks;
    _ = Marker;
}
