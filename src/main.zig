const std = @import("std");
const zbox = @import("zbox");
const c = @cImport({
    @cInclude("stdlib.h");
});

const Coord = struct {
    x: u64,
    y: u64,
};

const Direction = enum {
    left,
    right,
    up,
    down,
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    try zbox.init(alloc);
    defer zbox.deinit();

    try zbox.cursorHide();
    defer zbox.cursorShow() catch {};

    try zbox.handleSignalInput();

    var size = try zbox.size();
    var output = try zbox.Buffer.init(alloc, size.height, size.width);
    defer output.deinit();

    var snakeDir : ?Direction = null;

    var snakeHead = Coord{
        .x = @divTrunc(size.width, 2),
        .y = @divTrunc(size.height, 2),
    };

    while (try zbox.nextEvent()) |e| {
        output.clear();

        size = try zbox.size();
        try output.resize(size.height, size.width);

        switch (e) {
            .escape => return,
            .left => snakeDir = Direction.left,
            .right => snakeDir = Direction.right,
            .up => snakeDir = Direction.up,
            .down => snakeDir = Direction.down,
            else => {},
        }
        if (snakeDir) |s| {
            switch (s) {
                .left => if (snakeHead.x > 0) {snakeHead.x -= 1;},
                .right => if (snakeHead.x < size.width - 1) {snakeHead.x += 1;},
                .up => if (snakeHead.y > 0) {snakeHead.y -= 1;},
                .down => if (snakeHead.y < size.height - 1) {snakeHead.y += 1;},
            }
        }
        
        var score_curs = output.cursorAt(0,3);
        try score_curs.writer().print("420", .{});
        output.cellRef(snakeHead.y, snakeHead.x).* = .{
            .char = '#',
            .attribs = .{ .fg_green = true },
        };
        try zbox.push(output);
    }
}
