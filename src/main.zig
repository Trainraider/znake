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

const GridError = error {
    OutOfBounds,
};

const Grid = struct {
    display: *zbox.Buffer,
    //x,y,width,height are in terms of terminal characters.
    //In the created grid, height is double the below height
    x: u64,
    y: u64,
    width: u64,
    height: u64,

    fn init(display: *zbox.Buffer, x: u64, y: u64, width: u64, height: u64) Grid {
        const cell: zbox.Cell = .{
            .char = '▄',
            .attribs = .{
                .fg_black = true,
                .bg_black = true,
            },
        };
        var i: u64 = 0;
        while (i < width) {
            var j: u64 = 0;
            while (j < height) {
                display.cellRef(j + y, i + x).* = cell;
                j += 1;
            }
            i += 1;
        }
        return Grid{
            .display = display,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    fn setCell(self: *Grid, x: u64, y: u64, on: bool) !void {
        if (x >= self.width or y >= self.height << 1) return GridError.OutOfBounds;

        const upperHalf: bool = (y & 1 == 0 );
        const op: u2 = (@as(u2, @boolToInt(on)) << 1) + @as(u2, @boolToInt(upperHalf));

        var cell = self.*.display.cellRef(self.y + (y >> 1), self.x + x);
        var attribs = &cell.*.attribs;
        switch (op) {
            0 => {cell.char = '▄'; attribs.*.fg_green = false; attribs.*.fg_black = true;},
            1 => {cell.char = '▄'; attribs.*.bg_black = true; attribs.*.bg_green = false;},
            2 => {cell.char = '▄'; attribs.*.fg_green = true; attribs.*.fg_black = false;},
            3 => {cell.char = '▄'; attribs.*.bg_black = false; attribs.*.bg_green = true;},
        }

    }

    fn getCell(self: Grid, x: u64, y: u64) bool {
        const upperHalf: bool = (y & 1 == 0 );
        const attribs = self.display.cellRef(self.y + (y >> 1), self.x + x).*.attribs;

        if (upperHalf) {
            return attribs.bg_green;
        } else {
            return attribs.fg_green;
        }
    }
};

const Snake = struct {
    x: []u64,
    y: []u64,
    dir: ?Direction = null,
    length: u64,
    alloc: Allocator,
    display: *Grid,
    dead: bool = false,
    _head: u64,
    _tail: u64,

    pub fn init(alloc: Allocator, display: *Grid, length: u64) !Snake {
        assert(length > 0);
        const area = mul(u64, display.*.width, display.*.height) catch 4096;
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

        snake.y[0] = display.*.height;
        snake.x[0] = display.*.width >> 1;
        
        return snake;
    }

    pub fn deinit(self: Snake) void {
        self.alloc.free(self.x);
        self.alloc.free(self.y);
    }

    pub fn advance(self: *Snake) !void {
        
        var snakeHead = Coord {
            .x = self.*.x[self.*._head],
            .y = self.*.y[self.*._head],
        };
        
        var snakeTail = Coord {
            .x = self.*.x[self.*._tail],
            .y = self.*.y[self.*._tail],
        };

        if (self.*.dir) |s| {

            if (!self.*.dead) {
                switch (s) {
                    .left => if (snakeHead.x > 0) {snakeHead.x -= 1;},
                    .right => if (snakeHead.x < self.display.*.width - 1) {snakeHead.x += 1;},
                    .up => if (snakeHead.y > 0) {snakeHead.y -= 1;},
                    .down => if (snakeHead.y < (self.display.*.height << 1) - 1) {snakeHead.y += 1;},
                }


                self.*.x[self.*._tail] = snakeHead.x;
                self.*.y[self.*._tail] = snakeHead.y;

                self.*._head = self.*._tail;

                self.*._tail = sub(u64, self.*._tail, 1) catch sub(u64, self.*.length, 1) catch unreachable;

                try self.*.display.setCell(snakeTail.x, snakeTail.y, false);
                if (self.display.getCell(snakeHead.x, snakeHead.y)) self.*.dead = true;
                
                try self.*.display.setCell(snakeHead.x, snakeHead.y, true);

            }
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

    var grid = Grid.init(&output, 0, 1, size.width, size.height - 1);

    var snake = try Snake.init(allocator, &grid, 30);
    defer snake.deinit();

    while (try zbox.nextEvent()) |e| {

        size = try zbox.size();
        try output.resize(size.height, size.width);

        switch (e) {
            .escape => return,
            .left => if (snake.dir != Direction.right) {snake.dir = Direction.left;},
            .right => if (snake.dir != Direction.left) {snake.dir = Direction.right;},
            .up => if (snake.dir != Direction.down) {snake.dir = Direction.up;},
            .down => if (snake.dir != Direction.up) {snake.dir = Direction.down;},
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