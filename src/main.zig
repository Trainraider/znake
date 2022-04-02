const std = @import("std");
const builtin = @import("builtin");
const zbox = @import("zbox");
const c = @cImport({
    @cInclude("stdlib.h");
});

const Allocator = std.mem.Allocator;
const allocator: Allocator = if (builtin.is_test) std.testing.allocator else std.heap.page_allocator;
const mul = std.math.mul;
const sub = std.math.sub;
const assert = std.debug.assert;

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

const Snake = struct {
    x: []u64,
    y: []u64,
    dir: ?Direction = null,
    length: u64,
    alloc: Allocator,
    display: *zbox.Buffer,
    headCell: zbox.Cell = .{
        .char = 'ö',
        .attribs = .{ .bg_green = true, .fg_black = true, .bold = true,},
    },
    bodyCell: zbox.Cell= .{
        .char = ' ',
        .attribs = .{ .bg_green = true,},
    },
    _head: u64,
    _tail: u64,

    pub fn init(alloc: Allocator, display: *zbox.Buffer, length: u64) !Snake {
        assert(length > 0);
        const size = try zbox.size();
        const area = mul(u64, size.width, size.height) catch 2048;
        var snake = Snake{
            .x = try alloc.alloc(u64, area),
            .y = try alloc.alloc(u64, area),

            .length = length,
            .alloc = alloc,
            .display = display,
            ._head = 0,
            ._tail = sub(u64, length, 1) catch unreachable,
        };
        
        for (snake.x[1..length]) |*x| {
            x.* = 0;
        }
        
        for (snake.y[1..length]) |*y| {
            y.* = 0;
        }

        snake.y[0] = size.height >> 1;
        snake.x[0] = size.width >> 1;
        
        return snake;
    }

    pub fn deinit(self: Snake) void {
        self.alloc.free(self.x);
        self.alloc.free(self.y);
    }

    pub fn advance(self: *Snake) !void {
        
        const size = try zbox.size();
        
        var snakeHead = Coord {
            .x = self.*.x[self.*._head],
            .y = self.*.y[self.*._head],
        };
        
        var snakeTail = Coord {
            .x = self.*.x[self.*._tail],
            .y = self.*.y[self.*._tail],
        };

        if (self.*.dir) |s| {

            self.*.display.cellRef(snakeHead.y, snakeHead.x).* = self.*.bodyCell;

            switch (s) {
                .left => if (snakeHead.x > 0) {snakeHead.x -= 1;},
                .right => if (snakeHead.x < size.width - 1) {snakeHead.x += 1;},
                .up => if (snakeHead.y > 0) {snakeHead.y -= 1;},
                .down => if (snakeHead.y < size.height - 1) {snakeHead.y += 1;},
            }

            self.*.x[self.*._tail] = snakeHead.x;
            self.*.y[self.*._tail] = snakeHead.y;

            self.*._head = self.*._tail;

            self.*._tail = sub(u64, self.*._tail, 1) catch sub(u64, self.*.length, 1) catch unreachable;

            self.*.display.cellRef(snakeHead.y, snakeHead.x).* = self.*.headCell;
            
            self.*.display.cellRef(snakeTail.y, snakeTail.x).* = .{.char = ' ',};
        }
    }
};

pub fn main() !void {
    try zbox.init(allocator);
    defer zbox.deinit();

    try zbox.cursorHide();
    defer zbox.cursorShow() catch {};

    try zbox.handleSignalInput();

    var size = try zbox.size();
    var output = try zbox.Buffer.init(allocator, size.height, size.width);
    defer output.deinit();

    var snake = try Snake.init(allocator, &output, 60);
    defer snake.deinit();

    while (try zbox.nextEvent()) |e| {

        size = try zbox.size();
        try output.resize(size.height, size.width);

        switch (e) {
            .escape => return,
            .left => snake.dir = Direction.left,
            .right => snake.dir = Direction.right,
            .up => snake.dir = Direction.up,
            .down => snake.dir = Direction.down,
            else => {},
        }

        try snake.advance();
        
        var score_curs = output.cursorAt(0,3);
        try score_curs.writer().print("420", .{});
        
        try zbox.push(output);
    }
}

test "main" {
    try main();
}