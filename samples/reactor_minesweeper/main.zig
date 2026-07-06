//! Minesweeper reactor sample using `useReducerFn`.
//!
//! Run interactively:
//!   zig build run-reactor-minesweeper
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-minesweeper -- --exit-after-ms 1500

const std = @import("std");
const reactor = @import("win-reactor");
const win_sys = @import("win-sys");

const sys = win_sys.project(.{
    .@"Windows.Win32.System.SystemInformation" = .{"GetTickCount64"},
});

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const Width: usize = 9;
const Height: usize = 9;
const Total: usize = Width * Height;
const MineCount: usize = 10;
const BoardTracks = reactor.GridTracks.init(.{
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
    reactor.GridTrack.pixels(40),
});

const TileState = enum {
    hidden,
    flag,
    question,
    revealed,

    fn cycle(self: @This()) @This() {
        return switch (self) {
            .hidden => .flag,
            .flag => .question,
            .question => .hidden,
            .revealed => .revealed,
        };
    }
};

const Status = enum {
    playing,
    won,
    lost,
};

const Game = struct {
    tiles: [Total]TileState = [_]TileState{.hidden} ** Total,
    mines: [Total]bool = [_]bool{false} ** Total,
    neighbors: [Total]u8 = [_]u8{0} ** Total,
    generated: bool = false,
    hit_mine: ?usize = null,
    status: Status = .playing,
    seed: u64 = 0,
};

const Action = union(enum) {
    reveal: usize,
    flag: usize,
    reset: u64,
};

const XorShift64 = struct {
    state: u64,

    fn init(seed: u64) @This() {
        return .{
            .state = if (seed == 0) 0xDEAD_BEEF_CAFE_F00D else seed,
        };
    }

    fn next(self: *@This()) u64 {
        var value = self.state;
        value ^= value << 13;
        value ^= value >> 7;
        value ^= value << 17;
        self.state = value;
        return value;
    }
};

const StatusLabel = struct {
    buffers: [2][96]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), game: Game) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = switch (game.status) {
            .playing => std.fmt.bufPrint(
                &self.buffers[next],
                "Mines remaining: {d}",
                .{@as(i32, @intCast(MineCount)) - @as(i32, @intCast(flagCount(&game)))},
            ) catch unreachable,
            .won => "You cleared the board!",
            .lost => "Boom! Game over.",
        };
        self.active = next;
        return self.text;
    }
};

const TitleLabel = struct {
    buffers: [2][128]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), game: Game) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "windows-zig reactor minesweeper — {s}",
            .{statusSummary(&game)},
        ) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const RevealCapture = struct {
    index: usize = 0,
    dispatch: ?reactor.Dispatch(Game, Action) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.dispatch.?.call(.{ .reveal = self.index });
    }
};

const FlagCapture = struct {
    index: usize = 0,
    dispatch: ?reactor.Dispatch(Game, Action) = null,

    fn onPointerPressed(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        if (!info.is_right_button_pressed) return;
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.dispatch.?.call(.{ .flag = self.index });
    }
};

const ResetCapture = struct {
    dispatch: ?reactor.Dispatch(Game, Action) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.dispatch.?.call(.{ .reset = seedFromClock() });
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    const options = try parseArgs(&args);

    var app = reactor.App.init(allocator);
    app.exit_after_ms = options.exit_after_ms;
    try app.render(renderRoot);
}

fn renderRoot(cx: *reactor.RenderCx) reactor.ElementError!reactor.Element {
    const allocator = cx.getAllocator();
    const game = try cx.useReducerFn(Game, Action, reduce, newGame(seedFromClock()));

    const status_label = try cx.useRef(StatusLabel, .{});
    const status_text = status_label.getMut().update(game.value.*);

    const title_label = try cx.useRef(TitleLabel, .{});
    const title_text = title_label.getMut().update(game.value.*);

    const reveal_captures = try cx.useRef([Total]RevealCapture, [_]RevealCapture{.{}} ** Total);
    const flag_captures = try cx.useRef([Total]FlagCapture, [_]FlagCapture{.{}} ** Total);
    {
        const reveal = reveal_captures.getMut();
        const flag = flag_captures.getMut();
        for (0..Total) |index| {
            reveal[index] = .{
                .index = index,
                .dispatch = game.dispatch,
            };
            flag[index] = .{
                .index = index,
                .dispatch = game.dispatch,
            };
        }
    }

    const reset_capture = try cx.useRef(ResetCapture, .{});
    reset_capture.getMut().* = .{
        .dispatch = game.dispatch,
    };

    var status = try reactor.text_block(allocator, status_text);
    defer status.deinit(allocator);

    var reset = try reactor.button(
        allocator,
        "New Game",
        reactor.EventCallback.init(@ptrCast(reset_capture.getMut()), ResetCapture.onClick),
    );
    defer reset.deinit(allocator);

    var cell_elements = try allocator.alloc(reactor.Element, Total);
    defer allocator.free(cell_elements);
    var cell_refs = try allocator.alloc(*reactor.Element, Total);
    defer allocator.free(cell_refs);

    var built: usize = 0;
    errdefer {
        for (cell_elements[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    const reveal = reveal_captures.getMut();
    const flag = flag_captures.getMut();
    for (0..Total) |index| {
        var builder = reactor.button_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop("Content", tileLabel(game.value.*, index));
        _ = try (try builder.prop("Grid.Row", @as(i32, @intCast(index / Width))))
            .prop("Grid.Column", @as(i32, @intCast(index % Width)));
        _ = try builder.on(
            "Click",
            reactor.EventCallback.init(@ptrCast(&reveal[index]), RevealCapture.onClick),
        );
        _ = try builder.on(
            "PointerPressed",
            reactor.EventCallback.initTyped(
                reactor.PointerEventInfo,
                @ptrCast(&flag[index]),
                FlagCapture.onPointerPressed,
            ),
        );
        cell_elements[index] = try builder.build();
        cell_refs[index] = &cell_elements[index];
        built += 1;
    }
    defer {
        for (cell_elements[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    var board = try reactor.grid(
        allocator,
        .{
            .row_definitions = BoardTracks,
            .column_definitions = BoardTracks,
        },
        cell_refs,
    );
    defer board.deinit(allocator);

    var content = try reactor.vstack(allocator, .{ &status, &board, &reset });
    defer content.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", title_text);
    _ = try window_builder.child(&content);
    return window_builder.build();
}

fn reduce(previous: *const Game, action: Action) Game {
    return switch (action) {
        .reveal => |index| applyReveal(previous, index) orelse previous.*,
        .flag => |index| applyFlag(previous, index) orelse previous.*,
        .reset => |seed| newGame(seed),
    };
}

fn newGame(seed: u64) Game {
    return .{
        .seed = seed,
    };
}

fn applyReveal(previous: *const Game, index: usize) ?Game {
    if (index >= Total) return null;
    if (previous.status != .playing) return null;
    if (previous.tiles[index] != .hidden) return null;

    var next = previous.*;
    if (!next.generated) {
        generateMines(&next, index);
    }

    if (next.mines[index]) {
        for (0..Total) |tile_index| {
            if (next.mines[tile_index]) {
                next.tiles[tile_index] = .revealed;
            }
        }
        next.hit_mine = index;
        next.status = .lost;
        return next;
    }

    var queue: [Total]usize = undefined;
    var queued: [Total]bool = [_]bool{false} ** Total;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = index;
    queued[index] = true;
    tail += 1;

    while (head < tail) {
        const current = queue[head];
        head += 1;

        if (next.tiles[current] != .hidden) continue;
        if (next.mines[current]) continue;

        next.tiles[current] = .revealed;
        if (next.neighbors[current] != 0) continue;

        const x = current % Width;
        const y = current / Width;
        forEachNeighbor(x, y, struct {
            fn visit(nx: usize, ny: usize, context: anytype) void {
                const q: *struct {
                    queue: *[Total]usize,
                    queued: *[Total]bool,
                    tail: *usize,
                    tiles: *const [Total]TileState,
                } = @ptrCast(@constCast(context));
                const neighbor_index = gameIndex(nx, ny);
                if (q.tiles[neighbor_index] == .hidden and !q.queued[neighbor_index]) {
                    q.queued[neighbor_index] = true;
                    q.queue[q.tail.*] = neighbor_index;
                    q.tail.* += 1;
                }
            }
        }.visit, &struct {
            queue: *[Total]usize,
            queued: *[Total]bool,
            tail: *usize,
            tiles: *const [Total]TileState,
        }{
            .queue = &queue,
            .queued = &queued,
            .tail = &tail,
            .tiles = &next.tiles,
        });
    }

    if (checkWon(&next)) {
        next.status = .won;
    }
    return next;
}

fn applyFlag(previous: *const Game, index: usize) ?Game {
    if (index >= Total) return null;
    if (previous.status != .playing) return null;
    if (previous.tiles[index] == .revealed) return null;

    var next = previous.*;
    next.tiles[index] = next.tiles[index].cycle();
    return next;
}

fn checkWon(game: *const Game) bool {
    if (!game.generated) return false;
    for (0..Total) |index| {
        if (!game.mines[index] and game.tiles[index] != .revealed) {
            return false;
        }
    }
    return true;
}

fn generateMines(game: *Game, excluded_index: usize) void {
    var rng = XorShift64.init(game.seed);
    var placed: usize = 0;
    while (placed < MineCount) {
        const candidate = @as(usize, @intCast(rng.next() % Total));
        if (candidate == excluded_index or game.mines[candidate]) continue;
        game.mines[candidate] = true;
        placed += 1;
    }

    for (0..Total) |index| {
        if (game.mines[index]) {
            game.neighbors[index] = 0;
            continue;
        }
        const x = index % Width;
        const y = index / Width;
        var count: u8 = 0;
        forEachNeighbor(x, y, struct {
            fn visit(nx: usize, ny: usize, context: anytype) void {
                const state: *struct {
                    game: *Game,
                    count: *u8,
                } = @ptrCast(@constCast(context));
                if (state.game.mines[gameIndex(nx, ny)]) {
                    state.count.* += 1;
                }
            }
        }.visit, &struct {
            game: *Game,
            count: *u8,
        }{
            .game = game,
            .count = &count,
        });
        game.neighbors[index] = count;
    }

    game.generated = true;
}

fn forEachNeighbor(
    x: usize,
    y: usize,
    comptime callback: fn (usize, usize, anytype) void,
    context: anytype,
) void {
    const offsets = [_][2]i32{
        .{ -1, -1 },
        .{ 0, -1 },
        .{ 1, -1 },
        .{ -1, 0 },
        .{ 1, 0 },
        .{ -1, 1 },
        .{ 0, 1 },
        .{ 1, 1 },
    };

    for (offsets) |offset| {
        const nx = @as(i32, @intCast(x)) + offset[0];
        const ny = @as(i32, @intCast(y)) + offset[1];
        if (nx < 0 or ny < 0) continue;
        if (nx >= Width or ny >= Height) continue;
        callback(@intCast(nx), @intCast(ny), context);
    }
}

fn gameIndex(x: usize, y: usize) usize {
    return y * Width + x;
}

fn flagCount(game: *const Game) usize {
    var total: usize = 0;
    for (game.tiles) |tile| {
        if (tile == .flag) total += 1;
    }
    return total;
}

fn numberLabel(value: u8) []const u8 {
    return switch (value) {
        0 => " ",
        1 => "1",
        2 => "2",
        3 => "3",
        4 => "4",
        5 => "5",
        6 => "6",
        7 => "7",
        8 => "8",
        else => "?",
    };
}

fn tileLabel(game: Game, index: usize) []const u8 {
    return switch (game.tiles[index]) {
        .hidden => "·",
        .flag => "🚩",
        .question => "?",
        .revealed => if (game.mines[index]) "💣" else numberLabel(game.neighbors[index]),
    };
}

fn statusSummary(game: *const Game) []const u8 {
    return switch (game.status) {
        .playing => "Playing",
        .won => "You cleared the board!",
        .lost => "Boom! Game over.",
    };
}

fn seedFromClock() u64 {
    return sys.GetTickCount64();
}

fn parseArgs(args: *std.process.Args.Iterator) !Options {
    var options: Options = .{};

    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--exit-after-ms")) {
            const value = args.next() orelse return error.MissingExitAfterValue;
            options.exit_after_ms = try std.fmt.parseUnsigned(u32, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--exit-after-ms=")) {
            options.exit_after_ms = try std.fmt.parseUnsigned(
                u32,
                arg["--exit-after-ms=".len..],
                10,
            );
        } else {
            return error.UnknownArgument;
        }
    }

    return options;
}
