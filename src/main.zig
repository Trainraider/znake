const std = @import("std");
const builtin = @import("builtin");
const zbox = @import("zbox");

const Allocator = std.mem.Allocator;
const allocator: Allocator = if (builtin.is_test) std.testing.allocator else std.heap.page_allocator;
const mul = std.math.mul;
const sub = std.math.sub;
const assert = std.debug.assert;
const RndGen = std.rand.DefaultPrng;

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

    fn reset(self: *Grid, display: *zbox.Buffer, x: u64, y: u64, width: u64, height: u64) void{
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

        self.display = display;
        self.x = x;
        self.y = y;
        self.width = width;
        self.height = height;
    }

    fn setCell(self: *Grid, x: u64, y: u64, on: bool) !void {
        if (x >= self.width or y >= self.height << 1) return GridError.OutOfBounds;

        const upperHalf: bool = (y & 1 == 0 );

        var cell = self.*.display.cellRef(self.y + (y >> 1), self.x + x);
        var attribs = &cell.*.attribs;
        if (!upperHalf and !on) {cell.char = '▄'; attribs.*.fg_green = false; attribs.*.fg_black = true;}
        else if (upperHalf and !on) {cell.char = '▄'; attribs.*.bg_black = true; attribs.*.bg_green = false;}
        else if (!upperHalf and on) {cell.char = '▄'; attribs.*.fg_green = true; attribs.*.fg_black = false;}
        else if (upperHalf and on) {cell.char = '▄'; attribs.*.bg_black = false; attribs.*.bg_green = true;}

    }

    fn getCell(self: Grid, x: u64, y: u64) !bool {
        if (x >= self.width or y >= self.height << 1) return GridError.OutOfBounds;
        const upperHalf: bool = (y & 1 == 0 );
        const attribs = self.display.cellRef(self.y + (y >> 1), self.x + x).*.attribs;

        if (upperHalf) {
            return attribs.bg_green;
        } else {
            return attribs.fg_green;
        }
    }
};

const Food = struct {
    x: u64,
    y: u64,
    rnd: std.rand.Xoshiro256,
    display: *Grid,

    fn place(self: *Food) void {
        while (true) {
            self.*.x = self.*.rnd.random().int(u64) % self.*.display.width;
            self.*.y = self.*.rnd.random().int(u64) % (self.*.display.height << 1);
            if (!(self.*.display.getCell(self.*.x, self.*.y) catch unreachable)) break;
        }
        self.*.display.setCell(self.*.x, self.*.y, true) catch unreachable;
    }
};

const Snake = struct {
    x: []?u64,
    y: []?u64,
    dir: ?Direction = null,
    length: u64,
    alloc: Allocator,
    display: *Grid,
    dead: bool = false,
    _init_length: u64,
    _head: u64,
    _tail: u64,

    pub fn init(alloc: Allocator, display: *Grid, length: u64) !Snake {
        assert(length > 0);
        const area = mul(u64, display.*.width, display.*.height) catch 4096;
        var snake = Snake{
            .x = try alloc.alloc(?u64, area),
            .y = try alloc.alloc(?u64, area),

            .length = length,
            ._init_length = length,
            .alloc = alloc,
            .display = display,
            ._head = 0,
            ._tail = sub(u64, length, 1) catch unreachable,
        };

        snake.y[0] = display.*.height;
        snake.x[0] = display.*.width >> 1;

        display.setCell(snake.x[0].?, snake.y[0].?, true) catch unreachable;
        
        return snake;
    }

    pub fn reset(self: *Snake) !void {
        for (self.*.x[0..self.*.length]) |_,i| {
            if (self.*.x[i]) |_| {
                const size = try zbox.size();
                if (self.*.x[i].? < size.width and self.*.y[i].? < size.height) {
                    self.*.display.setCell(self.*.x[i].?, self.*.y[i].?, false) catch unreachable;
                }
            }
        }
        std.mem.set(?u64, self.*.x[1..self.*.length], null);
        std.mem.set(?u64, self.*.y[1..self.*.length], null);
        self.*.length = self.*._init_length;
        self.*._head = 0;
        self.*._tail = sub(u64, self.*.length, 1) catch unreachable;
        self.*.dir = null;

        self.*.y[0] = self.*.display.height;
        self.*.x[0] = self.*.display.width >> 1;
        self.*.dead = false;
    }

    pub fn deinit(self: Snake) void {
        self.alloc.free(self.x);
        self.alloc.free(self.y);
    }

    pub fn advance(self: *Snake, food: *Food) !void {
        
        var snakeHead = Coord {
            .x = self.*.x[self.*._head].?,
            .y = self.*.y[self.*._head].?,
        };
        
        var snakeTail: ?Coord = if (self.*.x[self.*._tail] != null and self.*.y[self.*._tail] != null) 
        .{
            .x = self.*.x[self.*._tail].?,
            .y = self.*.y[self.*._tail].?,
        } else null;

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

                if (snakeTail) |st| {
                    self.*.display.setCell(st.x, st.y, false) catch unreachable;
                }
                if (self.display.getCell(snakeHead.x, snakeHead.y) catch true) {
                    if (snakeHead.x == food.*.x and snakeHead.y == food.*.y){
                        self.*.length += 10;
                        food.*.place();
                    } else {
                        self.*.dead = true;
                    }
                }
                
                try self.*.display.setCell(snakeHead.x, snakeHead.y, true);

            }
        }
    }
};

fn reset(snake: *Snake, food: *Food, display: *zbox.Buffer) !void {
    try snake.*.reset();
    const size = try zbox.size();
    snake.*.display.reset(display, 0, 1, size.width, size.height - 1);
    var i: u64 = 0;
    const cell: zbox.Cell = .{
        .char = ' ',
        .attribs = .{.bg_black = false, .fg_black = false, .bg_green = false, .fg_green = false,},
    };
    while (i < size.width) {
        display.cellRef(0, i).* = cell;
        i += 1;
    }
    food.*.place();
}

pub fn main() !void {
    const random = try std.fs.openFileAbsolute("/dev/random", .{
        .mode = std.fs.File.OpenMode.read_only,
    });
    const seed: u64 = try random.reader().readIntNative(u64);
    random.close();

    var rnd = RndGen.init(seed);

    try zbox.init(allocator);
    defer zbox.deinit();

    try zbox.cursorHide();
    defer zbox.cursorShow() catch {};

    try zbox.handleSignalInput();

    var size = try zbox.size();
    var output = try zbox.Buffer.init(allocator, size.height, size.width);
    defer output.deinit();

    var grid = Grid.init(&output, 0, 1, size.width, size.height - 1);

    const initial_length = 30;
    var snake = try Snake.init(allocator, &grid, initial_length);
    defer snake.deinit();

    var food = Food {
        .x = undefined,
        .y = undefined,
        .rnd = rnd,
        .display = &grid,
    };
    food.place();

    while (try zbox.nextEvent()) |e| {

        const new_size = try zbox.size();
        if (new_size.width != size.width or new_size.height != size.height) {
            size.height = new_size.height;
            size.width = new_size.width;
            try output.resize(size.height, size.width);
            try reset(&snake, &food, &output);
        }

        switch (e) {
            .escape => return,
            .left => if (snake.dir != Direction.right) {snake.dir = Direction.left;},
            .right => if (snake.dir != Direction.left) {snake.dir = Direction.right;},
            .up => if (snake.dir != Direction.down) {snake.dir = Direction.up;},
            .down => if (snake.dir != Direction.up) {snake.dir = Direction.down;},
            .other => |data| {
                if (data[0] == 'r' and snake.dead) {
                    try reset(&snake, &food, &output);
                    continue;
                }
            },
            else => {},
        }

        try snake.advance(&food);
        
        var score_curs = output.cursorAt(0,3);
        try score_curs.writer().print("Score: {d}", .{snake.length - initial_length});
        if (snake.dead) {
            try score_curs.writer().print(" Play Again - R", .{});
        }
        
        try zbox.push(output);
    }
}

test "main" {
    try main();
}