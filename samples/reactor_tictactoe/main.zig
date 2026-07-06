//! Tic-tac-toe reactor sample using `useState`, `Grid`, and button clicks.
//!
//! Run interactively:
//!   zig build run-reactor-tictactoe
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-tictactoe -- --exit-after-ms 1500

const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const Size: usize = 3;
const Total: usize = Size * Size;
const BoardTracks = reactor.GridTracks.init(.{
    reactor.GridTrack.pixels(96),
    reactor.GridTrack.pixels(96),
    reactor.GridTrack.pixels(96),
});

const Cell = enum {
    empty,
    x,
    o,

    fn label(self: @This()) []const u8 {
        return switch (self) {
            .empty => " ",
            .x => "X",
            .o => "O",
        };
    }
};

const Player = enum {
    x,
    o,

    fn cell(self: @This()) Cell {
        return switch (self) {
            .x => .x,
            .o => .o,
        };
    }

    fn next(self: @This()) @This() {
        return switch (self) {
            .x => .o,
            .o => .x,
        };
    }

    fn label(self: @This()) []const u8 {
        return switch (self) {
            .x => "X",
            .o => "O",
        };
    }
};

const Status = enum {
    playing,
    won_x,
    won_o,
    draw,
};

const Game = struct {
    cells: [Total]Cell = [_]Cell{.empty} ** Total,
    turn: Player = .x,
    status: Status = .playing,
};

const WinningLines = [_][3]usize{
    .{ 0, 1, 2 },
    .{ 3, 4, 5 },
    .{ 6, 7, 8 },
    .{ 0, 3, 6 },
    .{ 1, 4, 7 },
    .{ 2, 5, 8 },
    .{ 0, 4, 8 },
    .{ 2, 4, 6 },
};

const StatusLabel = struct {
    buffers: [2][64]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), game: Game) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = switch (game.status) {
            .playing => std.fmt.bufPrint(
                &self.buffers[next],
                "Turn: {s}",
                .{game.turn.label()},
            ) catch unreachable,
            .won_x => "X wins!",
            .won_o => "O wins!",
            .draw => "It's a draw!",
        };
        self.active = next;
        return self.text;
    }
};

const TitleLabel = struct {
    buffers: [2][96]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), game: Game) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "windows-zig reactor tictactoe — {s}",
            .{statusSummary(game)},
        ) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const CellClickCapture = struct {
    position: usize = 0,
    game: Game = .{},
    setter: ?reactor.SetState(Game) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (applyMove(&self.game, self.position)) |next| {
            self.setter.?.call(next);
        }
    }
};

const ResetCapture = struct {
    setter: ?reactor.SetState(Game) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.setter.?.call(.{});
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
    const game = try cx.useState(Game, .{});

    const status_label = try cx.useRef(StatusLabel, .{});
    const status_text = status_label.getMut().update(game.value.*);

    const title_label = try cx.useRef(TitleLabel, .{});
    const title_text = title_label.getMut().update(game.value.*);

    const cell_captures = try cx.useRef([Total]CellClickCapture, [_]CellClickCapture{.{}} ** Total);
    {
        const captures = cell_captures.getMut();
        for (0..Total) |index| {
            captures[index] = .{
                .position = index,
                .game = game.value.*,
                .setter = game.set,
            };
        }
    }

    const reset_capture = try cx.useRef(ResetCapture, .{});
    reset_capture.getMut().* = .{
        .setter = game.set,
    };

    var status = try reactor.text_block(allocator, status_text);
    defer status.deinit(allocator);

    var reset = try reactor.button(
        allocator,
        "New Game",
        reactor.EventCallback.init(@ptrCast(reset_capture.getMut()), ResetCapture.onClick),
    );
    defer reset.deinit(allocator);

    var cell_elements: [Total]reactor.Element = undefined;
    var built: usize = 0;
    errdefer {
        for (cell_elements[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    const captures = cell_captures.getMut();
    for (0..Total) |index| {
        var builder = reactor.button_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop("Content", game.value.*.cells[index].label());
        _ = try (try builder.attached(reactor.Grid.row(@as(i32, @intCast(index / Size)))))
            .attached(reactor.Grid.column(@as(i32, @intCast(index % Size))));
        _ = try builder.on(
            "Click",
            reactor.EventCallback.init(@ptrCast(&captures[index]), CellClickCapture.onClick),
        );
        cell_elements[index] = try builder.build();
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
        .{
            &cell_elements[0],
            &cell_elements[1],
            &cell_elements[2],
            &cell_elements[3],
            &cell_elements[4],
            &cell_elements[5],
            &cell_elements[6],
            &cell_elements[7],
            &cell_elements[8],
        },
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

fn detectWinner(cells: *const [Total]Cell) ?Player {
    for (WinningLines) |line| {
        const first = cells[line[0]];
        if (first == .empty) continue;
        if (first == cells[line[1]] and first == cells[line[2]]) {
            return switch (first) {
                .x => .x,
                .o => .o,
                .empty => null,
            };
        }
    }
    return null;
}

fn applyMove(game: *const Game, position: usize) ?Game {
    if (position >= Total) return null;
    if (game.status != .playing) return null;
    if (game.cells[position] != .empty) return null;

    var next = game.*;
    next.cells[position] = game.turn.cell();

    if (detectWinner(&next.cells)) |winner| {
        next.status = switch (winner) {
            .x => .won_x,
            .o => .won_o,
        };
        return next;
    }

    var all_filled = true;
    for (next.cells) |cell| {
        if (cell == .empty) {
            all_filled = false;
            break;
        }
    }

    if (all_filled) {
        next.status = .draw;
        return next;
    }

    next.turn = game.turn.next();
    return next;
}

fn statusSummary(game: Game) []const u8 {
    return switch (game.status) {
        .playing => switch (game.turn) {
            .x => "Turn: X",
            .o => "Turn: O",
        },
        .won_x => "X wins!",
        .won_o => "O wins!",
        .draw => "It's a draw!",
    };
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
