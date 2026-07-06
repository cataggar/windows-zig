//! Dotsweeper reactor sample using `useReducer` and `useEffectWithCleanup`.
//!
//! Run interactively:
//!   zig build run-reactor-dotsweeper
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-dotsweeper -- --exit-after-ms 2500

const std = @import("std");
const reactor = @import("win-reactor");
const win_sys = @import("win-sys");

const timer_sys = win_sys.project(.{
    .@"Windows.Win32.UI.WindowsAndMessaging" = .{
        "KillTimer",
        "SetTimer",
    },
});
const system_sys = win_sys.project(.{
    .@"Windows.Win32.System.SystemInformation" = .{"GetTickCount64"},
});

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const MaxRows: usize = 16;
const MaxCols: usize = 30;
const MaxCells: usize = MaxRows * MaxCols;
const NextSeedDelta: u64 = 0x9E37_79B9_7F4A_7C15;

const Difficulty = struct {
    name: []const u8,
    rows: u8,
    cols: u8,
    mines: u16,
    cell_size: f64,

    const beginner: Difficulty = .{
        .name = "Beginner",
        .rows = 9,
        .cols = 9,
        .mines = 10,
        .cell_size = 36,
    };
    const intermediate: Difficulty = .{
        .name = "Intermediate",
        .rows = 16,
        .cols = 16,
        .mines = 40,
        .cell_size = 28,
    };
    const expert: Difficulty = .{
        .name = "Expert",
        .rows = 16,
        .cols = 30,
        .mines = 99,
        .cell_size = 22,
    };
};

const CellMark = enum {
    none,
    flag,
    question,

    fn cycle(self: @This()) @This() {
        return switch (self) {
            .none => .flag,
            .flag => .question,
            .question => .none,
        };
    }
};

const Cell = struct {
    is_mine: bool = false,
    adjacent_mines: u8 = 0,
    is_revealed: bool = false,
    mark: CellMark = .none,
};

const GamePhase = enum {
    not_started,
    playing,
    won,
    lost,
};

const Board = struct {
    difficulty: Difficulty,
    cells: [MaxCells]Cell = [_]Cell{.{}} ** MaxCells,
    phase: GamePhase = .not_started,
    exploded_index: ?usize = null,
    seed: u64,
};

const AppState = struct {
    board: Board,
    elapsed_seconds: u32 = 0,
    next_seed: u64,

    fn initial(difficulty: Difficulty, seed: u64) @This() {
        return .{
            .board = .{
                .difficulty = difficulty,
                .seed = seed,
            },
            .elapsed_seconds = 0,
            .next_seed = advanceSeed(seed),
        };
    }
};

const Action = union(enum) {
    reveal: usize,
    flag: usize,
    reset: void,
    new_game: Difficulty,
    tick: void,
};

const XorShift64 = struct {
    state: u64,

    fn init(seed: u64) @This() {
        return .{
            .state = if (seed == 0) 0xCAFE_BABE_DEAD_BEEF else seed,
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
    buffers: [2][128]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), state: AppState) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = switch (state.board.phase) {
            .not_started => std.fmt.bufPrint(
                &self.buffers[next],
                "{s} — Mines: {d}",
                .{ state.board.difficulty.name, minesRemaining(&state.board) },
            ) catch unreachable,
            .playing => std.fmt.bufPrint(
                &self.buffers[next],
                "{s} — Mines: {d} — Time: {d}s",
                .{ state.board.difficulty.name, minesRemaining(&state.board), state.elapsed_seconds },
            ) catch unreachable,
            .won => std.fmt.bufPrint(
                &self.buffers[next],
                "{s} — Cleared in {d}s!",
                .{ state.board.difficulty.name, state.elapsed_seconds },
            ) catch unreachable,
            .lost => std.fmt.bufPrint(
                &self.buffers[next],
                "{s} — Boom!",
                .{state.board.difficulty.name},
            ) catch unreachable,
        };
        self.active = next;
        return self.text;
    }
};

const TitleLabel = struct {
    buffers: [2][160]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), state: AppState) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "windows-zig reactor dotsweeper — {s}",
            .{statusSummary(state)},
        ) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const RevealCapture = struct {
    index: usize = 0,
    update: ?reactor.Updater(AppState) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .reveal = self.index }, reduceAction);
    }
};

const FlagCapture = struct {
    index: usize = 0,
    update: ?reactor.Updater(AppState) = null,

    fn onPointerPressed(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        if (!info.is_right_button_pressed) return;
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .flag = self.index }, reduceAction);
    }
};

const ResetCapture = struct {
    update: ?reactor.Updater(AppState) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .reset = {} }, reduceAction);
    }
};

const DifficultyCapture = struct {
    difficulty: Difficulty = Difficulty.beginner,
    update: ?reactor.Updater(AppState) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .new_game = self.difficulty }, reduceAction);
    }
};

const TimerRuntimeContext = struct {
    update: reactor.Updater(AppState),
};

const TimerCleanup = struct {
    id: usize,
    runtime: *TimerRuntimeContext,
};

const TimerEffectContext = struct {
    should_tick: bool,
    update: reactor.Updater(AppState),
};

var g_timer_id: ?usize = null;
var g_timer_context: ?*TimerRuntimeContext = null;

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
    const state = try cx.useReducer(AppState, AppState.initial(Difficulty.beginner, seedFromClock()));

    const should_tick = state.value.*.board.phase == .playing;
    try cx.useEffectWithCleanup(
        TimerCleanup,
        should_tick,
        TimerEffectContext{
            .should_tick = should_tick,
            .update = state.update,
        },
        runTimerEffect,
        cleanupTimer,
    );

    const status_label = try cx.useRef(StatusLabel, .{});
    const status_text = status_label.getMut().update(state.value.*);

    const title_label = try cx.useRef(TitleLabel, .{});
    const title_text = title_label.getMut().update(state.value.*);

    const cell_count = boardCellCount(&state.value.*.board);

    const reveal_captures = try cx.useRef([MaxCells]RevealCapture, [_]RevealCapture{.{}} ** MaxCells);
    const flag_captures = try cx.useRef([MaxCells]FlagCapture, [_]FlagCapture{.{}} ** MaxCells);
    {
        const reveal = reveal_captures.getMut();
        const flag = flag_captures.getMut();
        for (0..cell_count) |index| {
            reveal[index] = .{
                .index = index,
                .update = state.update,
            };
            flag[index] = .{
                .index = index,
                .update = state.update,
            };
        }
    }

    const reset_capture = try cx.useRef(ResetCapture, .{});
    reset_capture.getMut().* = .{
        .update = state.update,
    };

    const difficulty_captures = try cx.useRef([3]DifficultyCapture, [_]DifficultyCapture{.{}} ** 3);
    difficulty_captures.getMut()[0] = .{
        .difficulty = Difficulty.beginner,
        .update = state.update,
    };
    difficulty_captures.getMut()[1] = .{
        .difficulty = Difficulty.intermediate,
        .update = state.update,
    };
    difficulty_captures.getMut()[2] = .{
        .difficulty = Difficulty.expert,
        .update = state.update,
    };

    var status = try reactor.text_block(allocator, status_text);
    defer status.deinit(allocator);

    var beginner = try reactor.button(
        allocator,
        "Beginner",
        reactor.EventCallback.init(@ptrCast(&difficulty_captures.getMut()[0]), DifficultyCapture.onClick),
    );
    defer beginner.deinit(allocator);
    var intermediate = try reactor.button(
        allocator,
        "Intermediate",
        reactor.EventCallback.init(@ptrCast(&difficulty_captures.getMut()[1]), DifficultyCapture.onClick),
    );
    defer intermediate.deinit(allocator);
    var expert = try reactor.button(
        allocator,
        "Expert",
        reactor.EventCallback.init(@ptrCast(&difficulty_captures.getMut()[2]), DifficultyCapture.onClick),
    );
    defer expert.deinit(allocator);
    var reset = try reactor.button(
        allocator,
        "Reset",
        reactor.EventCallback.init(@ptrCast(reset_capture.getMut()), ResetCapture.onClick),
    );
    defer reset.deinit(allocator);

    var toolbar = try reactor.hstack(allocator, .{ &beginner, &intermediate, &expert, &reset });
    defer toolbar.deinit(allocator);

    var row_values: [MaxRows]reactor.GridTrack = undefined;
    const row_count = @as(usize, state.value.*.board.difficulty.rows);
    for (0..row_count) |index| {
        row_values[index] = reactor.GridTrack.pixels(state.value.*.board.difficulty.cell_size);
    }
    const row_tracks = reactor.GridTracks.init(row_values[0..row_count]);

    var column_values: [MaxCols]reactor.GridTrack = undefined;
    const column_count = @as(usize, state.value.*.board.difficulty.cols);
    for (0..column_count) |index| {
        column_values[index] = reactor.GridTrack.pixels(state.value.*.board.difficulty.cell_size);
    }
    const column_tracks = reactor.GridTracks.init(column_values[0..column_count]);

    var cell_elements = try allocator.alloc(reactor.Element, cell_count);
    defer allocator.free(cell_elements);
    var cell_refs = try allocator.alloc(*reactor.Element, cell_count);
    defer allocator.free(cell_refs);

    var built: usize = 0;
    errdefer {
        for (cell_elements[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    const reveal = reveal_captures.getMut();
    const flag = flag_captures.getMut();
    for (0..cell_count) |index| {
        var builder = reactor.button_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop("Content", cellLabel(&state.value.*.board, index));
        _ = try (try builder.prop("Grid.Row", @as(i32, @intCast(index / column_count))))
            .prop("Grid.Column", @as(i32, @intCast(index % column_count)));
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
            .row_definitions = row_tracks,
            .column_definitions = column_tracks,
        },
        cell_refs,
    );
    defer board.deinit(allocator);

    var content = try reactor.vstack(allocator, .{ &status, &toolbar, &board });
    defer content.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", title_text);
    _ = try window_builder.child(&content);
    return window_builder.build();
}

fn reduceAction(action: *const Action, previous: *const AppState) AppState {
    return switch (action.*) {
        .reveal => |index| blk: {
            var next = previous.*;
            const changed = revealOrChord(&next.board, index);
            if (changed) {
                if (next.board.phase == .won or next.board.phase == .lost) {
                    next.elapsed_seconds = next.elapsed_seconds;
                }
            }
            break :blk if (changed) next else previous.*;
        },
        .flag => |index| blk: {
            var next = previous.*;
            if (!toggleMark(&next.board, index)) break :blk previous.*;
            break :blk next;
        },
        .reset => blk: {
            break :blk AppState.initial(previous.board.difficulty, previous.next_seed);
        },
        .new_game => |difficulty| blk: {
            break :blk AppState.initial(difficulty, previous.next_seed);
        },
        .tick => blk: {
            if (previous.board.phase != .playing) break :blk previous.*;
            var next = previous.*;
            next.elapsed_seconds = @min(next.elapsed_seconds + 1, 999);
            break :blk next;
        },
    };
}

fn runTimerEffect(ctx: *const TimerEffectContext) ?TimerCleanup {
    if (!ctx.should_tick) return null;

    const runtime = std.heap.page_allocator.create(TimerRuntimeContext) catch return null;
    runtime.* = .{
        .update = ctx.update,
    };

    if (g_timer_id) |existing| {
        _ = timer_sys.KillTimer(null, existing);
        g_timer_id = null;
    }
    if (g_timer_context) |previous| {
        std.heap.page_allocator.destroy(previous);
        g_timer_context = null;
    }

    g_timer_id = timer_sys.SetTimer(null, 0, 1000, onTick);
    if (g_timer_id == null) {
        std.heap.page_allocator.destroy(runtime);
        return null;
    }

    g_timer_context = runtime;
    return .{
        .id = g_timer_id.?,
        .runtime = runtime,
    };
}

fn cleanupTimer(cleanup: *TimerCleanup) void {
    if (g_timer_id) |active| {
        if (active == cleanup.id) {
            _ = timer_sys.KillTimer(null, active);
            g_timer_id = null;
        }
    }
    if (g_timer_context == cleanup.runtime) {
        g_timer_context = null;
    }
    std.heap.page_allocator.destroy(cleanup.runtime);
}

fn onTick(_: ?*anyopaque, _: u32, id: usize, _: u32) callconv(.winapi) void {
    if (g_timer_id != id) return;
    if (g_timer_context) |runtime| {
        runtime.update.callWith(Action{ .tick = {} }, reduceAction);
    }
}

fn boardCellCount(board: *const Board) usize {
    return @as(usize, board.difficulty.rows) * @as(usize, board.difficulty.cols);
}

fn boardIndex(board: *const Board, row: usize, column: usize) usize {
    return row * @as(usize, board.difficulty.cols) + column;
}

fn inBounds(board: *const Board, row: i32, column: i32) bool {
    return row >= 0 and
        column >= 0 and
        row < board.difficulty.rows and
        column < board.difficulty.cols;
}

fn forEachNeighbor(
    board: *const Board,
    row: usize,
    column: usize,
    comptime callback: anytype,
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
        const next_row = @as(i32, @intCast(row)) + offset[0];
        const next_column = @as(i32, @intCast(column)) + offset[1];
        if (!inBounds(board, next_row, next_column)) continue;
        callback(@intCast(next_row), @intCast(next_column), context);
    }
}

fn minesRemaining(board: *const Board) i32 {
    var flags: i32 = 0;
    const count = boardCellCount(board);
    for (board.cells[0..count]) |cell| {
        if (cell.mark == .flag) flags += 1;
    }
    return @as(i32, board.difficulty.mines) - flags;
}

fn advanceSeed(seed: u64) u64 {
    return seed +% NextSeedDelta;
}

fn seedFromClock() u64 {
    return system_sys.GetTickCount64() +% NextSeedDelta;
}

fn generateMines(board: *Board, safe_index: usize) void {
    const rows = @as(usize, board.difficulty.rows);
    const columns = @as(usize, board.difficulty.cols);
    const safe_row = safe_index / columns;
    const safe_column = safe_index % columns;

    var forbidden: [MaxCells]bool = [_]bool{false} ** MaxCells;
    forEachNeighbor(board, safe_row, safe_column, struct {
        fn mark(row: usize, column: usize, context: anytype) void {
            const forbidden_cells: *[MaxCells]bool = @ptrCast(@constCast(context));
            forbidden_cells[row * MaxCols + column] = true;
        }
    }.mark, &forbidden);
    forbidden[safe_row * MaxCols + safe_column] = true;

    var candidates: [MaxCells]usize = undefined;
    var candidate_count: usize = 0;
    for (0..rows) |row| {
        for (0..columns) |column| {
            if (forbidden[row * MaxCols + column]) continue;
            candidates[candidate_count] = boardIndex(board, row, column);
            candidate_count += 1;
        }
    }

    var rng = XorShift64.init(board.seed);
    const target = @as(usize, board.difficulty.mines);
    for (0..target) |i| {
        const remaining = candidate_count - i;
        const offset = @as(usize, @intCast(rng.next() % remaining));
        const swap_index = i + offset;
        const tmp = candidates[i];
        candidates[i] = candidates[swap_index];
        candidates[swap_index] = tmp;
        board.cells[candidates[i]].is_mine = true;
    }

    for (0..rows) |row| {
        for (0..columns) |column| {
            const index = boardIndex(board, row, column);
            if (board.cells[index].is_mine) continue;
            var count: u8 = 0;
            forEachNeighbor(board, row, column, struct {
                fn countNeighbor(next_row: usize, next_column: usize, context: anytype) void {
                    const state: *struct {
                        board: *Board,
                        count: *u8,
                    } = @ptrCast(@constCast(context));
                    if (state.board.cells[boardIndex(state.board, next_row, next_column)].is_mine) {
                        state.count.* += 1;
                    }
                }
            }.countNeighbor, &struct {
                board: *Board,
                count: *u8,
            }{
                .board = board,
                .count = &count,
            });
            board.cells[index].adjacent_mines = count;
        }
    }

    board.phase = .playing;
}

fn revealOrChord(board: *Board, index: usize) bool {
    if (index >= boardCellCount(board)) return false;
    if (board.phase == .won or board.phase == .lost) return false;

    if (board.cells[index].is_revealed) {
        return chord(board, index);
    }

    return revealIndex(board, index);
}

fn revealIndex(board: *Board, index: usize) bool {
    if (board.phase == .won or board.phase == .lost) return false;
    if (board.cells[index].is_revealed or board.cells[index].mark == .flag) return false;

    if (board.phase == .not_started) {
        generateMines(board, index);
    }

    if (board.cells[index].is_mine) {
        const count = boardCellCount(board);
        for (0..count) |cell_index| {
            if (board.cells[cell_index].is_mine) {
                board.cells[cell_index].is_revealed = true;
            }
        }
        board.phase = .lost;
        board.exploded_index = index;
        return true;
    }

    var queue: [MaxCells]usize = undefined;
    var queued: [MaxCells]bool = [_]bool{false} ** MaxCells;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = index;
    queued[index] = true;
    tail += 1;

    while (head < tail) {
        const current = queue[head];
        head += 1;
        if (board.cells[current].is_revealed) continue;
        if (board.cells[current].mark == .flag) continue;
        if (board.cells[current].is_mine) continue;

        board.cells[current].is_revealed = true;
        if (board.cells[current].adjacent_mines != 0) continue;

        const row = current / @as(usize, board.difficulty.cols);
        const column = current % @as(usize, board.difficulty.cols);
        forEachNeighbor(board, row, column, struct {
            fn visit(next_row: usize, next_column: usize, context: anytype) void {
                const state: *struct {
                    board: *Board,
                    queue: *[MaxCells]usize,
                    queued: *[MaxCells]bool,
                    tail: *usize,
                } = @ptrCast(@constCast(context));
                const neighbor_index = boardIndex(state.board, next_row, next_column);
                const neighbor = state.board.cells[neighbor_index];
                if (!neighbor.is_revealed and
                    neighbor.mark != .flag and
                    !neighbor.is_mine and
                    !state.queued[neighbor_index])
                {
                    state.queued[neighbor_index] = true;
                    state.queue[state.tail.*] = neighbor_index;
                    state.tail.* += 1;
                }
            }
        }.visit, &struct {
            board: *Board,
            queue: *[MaxCells]usize,
            queued: *[MaxCells]bool,
            tail: *usize,
        }{
            .board = board,
            .queue = &queue,
            .queued = &queued,
            .tail = &tail,
        });
    }

    finalizeBoardState(board);
    return true;
}

fn chord(board: *Board, index: usize) bool {
    if (board.phase != .playing) return false;
    const cell = board.cells[index];
    if (!cell.is_revealed or cell.adjacent_mines == 0) return false;

    const row = index / @as(usize, board.difficulty.cols);
    const column = index % @as(usize, board.difficulty.cols);
    var flags: u8 = 0;
    forEachNeighbor(board, row, column, struct {
        fn countFlags(next_row: usize, next_column: usize, context: anytype) void {
            const state: *struct {
                board: *const Board,
                flags: *u8,
            } = @ptrCast(@constCast(context));
            if (state.board.cells[boardIndex(state.board, next_row, next_column)].mark == .flag) {
                state.flags.* += 1;
            }
        }
    }.countFlags, &struct {
        board: *const Board,
        flags: *u8,
    }{
        .board = board,
        .flags = &flags,
    });

    if (flags != cell.adjacent_mines) return false;

    var changed = false;
    forEachNeighbor(board, row, column, struct {
        fn revealNeighbor(next_row: usize, next_column: usize, context: anytype) void {
            const state: *struct {
                board: *Board,
                changed: *bool,
            } = @ptrCast(@constCast(context));
            const neighbor_index = boardIndex(state.board, next_row, next_column);
            const neighbor = state.board.cells[neighbor_index];
            if (neighbor.mark == .flag or neighbor.is_revealed) return;
            if (revealIndex(state.board, neighbor_index)) {
                state.changed.* = true;
            }
        }
    }.revealNeighbor, &struct {
        board: *Board,
        changed: *bool,
    }{
        .board = board,
        .changed = &changed,
    });
    return changed;
}

fn toggleMark(board: *Board, index: usize) bool {
    if (index >= boardCellCount(board)) return false;
    if (board.phase == .won or board.phase == .lost) return false;
    if (board.cells[index].is_revealed) return false;
    board.cells[index].mark = board.cells[index].mark.cycle();
    return true;
}

fn finalizeBoardState(board: *Board) void {
    const count = boardCellCount(board);
    var revealed_safe: usize = 0;
    for (0..count) |index| {
        if (!board.cells[index].is_mine and board.cells[index].is_revealed) {
            revealed_safe += 1;
        }
    }

    const safe_total = count - @as(usize, board.difficulty.mines);
    if (revealed_safe == safe_total) {
        board.phase = .won;
        for (0..count) |index| {
            if (board.cells[index].is_mine and board.cells[index].mark == .none) {
                board.cells[index].mark = .flag;
            }
        }
    } else if (board.phase != .lost) {
        board.phase = .playing;
    }
}

fn cellLabel(board: *const Board, index: usize) []const u8 {
    const cell = board.cells[index];
    if (!cell.is_revealed) {
        return switch (cell.mark) {
            .none => "·",
            .flag => "F",
            .question => "?",
        };
    }
    if (cell.is_mine) return "*";
    return switch (cell.adjacent_mines) {
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

fn statusSummary(state: AppState) []const u8 {
    return switch (state.board.phase) {
        .not_started => "Ready",
        .playing => "Playing",
        .won => "Won",
        .lost => "Boom!",
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
