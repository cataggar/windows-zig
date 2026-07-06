//! Mini-solitaire reactor sample.
//!
//! This is a reduced-scope Klondike-style demo focused on the issue's Canvas
//! requirements: absolute positioning plus pointer-press / move / release drag
//! handling. Drag the four starter cards onto their matching foundations.
//!
//! Run interactively:
//!   zig build run-reactor-solitaire
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-solitaire -- --exit-after-ms 2500

const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const CardCount: usize = 4;
const FoundationCount: usize = 2;
const TableauCount: usize = 2;

const FoundationX = [_]f64{ 360, 470 };
const FoundationY: f64 = 80;
const TableauX = [_]f64{ 40, 150 };
const TableauY = [_]f64{ 180, 220 };
const DragZ: i32 = 20;

const Suit = enum {
    spades,
    hearts,

    fn symbol(self: @This()) []const u8 {
        return switch (self) {
            .spades => "♠",
            .hearts => "♥",
        };
    }

    fn foundationIndex(self: @This()) usize {
        return switch (self) {
            .spades => 0,
            .hearts => 1,
        };
    }
};

const Card = struct {
    label: []const u8,
    suit: Suit,
    rank: u8,
    home_left: f64,
    home_top: f64,
    left: f64,
    top: f64,
    locked: bool = false,
    dragging: bool = false,
    offset_x: f64 = 0,
    offset_y: f64 = 0,
};

const Game = struct {
    cards: [CardCount]Card = initialCards(),
    foundations: [FoundationCount]u8 = [_]u8{0} ** FoundationCount,
};

const PointerAction = struct {
    card_index: usize,
    info: reactor.PointerEventInfo,
};

const Action = union(enum) {
    reset: void,
    press: PointerAction,
    move: PointerAction,
    release: PointerAction,
};

const TitleLabel = struct {
    buffers: [2][160]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), game: Game) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "windows-zig reactor solitaire — {d}/{d} cards placed",
            .{ placedCardCount(&game), CardCount },
        ) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const DragCapture = struct {
    card_index: usize = 0,
    update: ?reactor.Updater(Game) = null,

    fn onPressed(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        if (!info.is_left_button_pressed) return;
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .press = .{
            .card_index = self.card_index,
            .info = info,
        } }, reduceAction);
    }

    fn onMoved(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .move = .{
            .card_index = self.card_index,
            .info = info,
        } }, reduceAction);
    }

    fn onReleased(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .release = .{
            .card_index = self.card_index,
            .info = info,
        } }, reduceAction);
    }
};

const ResetCapture = struct {
    update: ?reactor.Updater(Game) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.update.?.callWith(Action{ .reset = {} }, reduceAction);
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
    const game = try cx.useReducer(Game, .{});

    const title_label = try cx.useRef(TitleLabel, .{});
    const title_text = title_label.getMut().update(game.value.*);

    const drag_captures = try cx.useRef([CardCount]DragCapture, [_]DragCapture{.{}} ** CardCount);
    {
        const captures = drag_captures.getMut();
        for (0..CardCount) |index| {
            captures[index] = .{
                .card_index = index,
                .update = game.update,
            };
        }
    }

    const reset_capture = try cx.useRef(ResetCapture, .{});
    reset_capture.getMut().* = .{
        .update = game.update,
    };

    const child_count = 1 + 1 + FoundationCount + TableauCount + CardCount;
    var children = try allocator.alloc(reactor.Element, child_count);
    defer allocator.free(children);
    var child_refs = try allocator.alloc(*reactor.Element, child_count);
    defer allocator.free(child_refs);

    var built: usize = 0;
    errdefer {
        for (children[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    {
        var instructions_builder = reactor.text_block_builder(allocator);
        defer instructions_builder.deinit();
        _ = try instructions_builder.prop("Text", @as([]const u8, "Drag the aces and twos to the foundations."));
        _ = try reactor.canvas_position(&instructions_builder, 20, 20);
        children[built] = try instructions_builder.build();
        child_refs[built] = &children[built];
        built += 1;
    }

    {
        var reset_button_builder = reactor.button_builder(allocator);
        defer reset_button_builder.deinit();
        _ = try reset_button_builder.prop("Content", @as([]const u8, "New Deal"));
        _ = try reset_button_builder.on(
            "Click",
            reactor.EventCallback.init(@ptrCast(reset_capture.getMut()), ResetCapture.onClick),
        );
        _ = try reactor.canvas_position(&reset_button_builder, 20, 55);
        children[built] = try reset_button_builder.build();
        child_refs[built] = &children[built];
        built += 1;
    }

    for (0..FoundationCount) |index| {
        var builder = reactor.text_block_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop(
            "Text",
            if (index == 0) @as([]const u8, "Foundation ♠") else @as([]const u8, "Foundation ♥"),
        );
        _ = try reactor.canvas_position(&builder, FoundationX[index], FoundationY - 28);
        children[built] = try builder.build();
        child_refs[built] = &children[built];
        built += 1;
    }

    for (0..TableauCount) |index| {
        var builder = reactor.text_block_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop(
            "Text",
            if (index == 0) @as([]const u8, "Tableau 1") else @as([]const u8, "Tableau 2"),
        );
        _ = try reactor.canvas_position(&builder, TableauX[index], TableauY[0] - 28);
        children[built] = try builder.build();
        child_refs[built] = &children[built];
        built += 1;
    }

    const captures = drag_captures.getMut();
    for (0..CardCount) |index| {
        var builder = reactor.button_builder(allocator);
        defer builder.deinit();
        _ = try builder.prop("Content", game.value.*.cards[index].label);
        _ = try builder.on(
            "PointerPressed",
            reactor.EventCallback.initTyped(
                reactor.PointerEventInfo,
                @ptrCast(&captures[index]),
                DragCapture.onPressed,
            ),
        );
        _ = try builder.on(
            "PointerMoved",
            reactor.EventCallback.initTyped(
                reactor.PointerEventInfo,
                @ptrCast(&captures[index]),
                DragCapture.onMoved,
            ),
        );
        _ = try builder.on(
            "PointerReleased",
            reactor.EventCallback.initTyped(
                reactor.PointerEventInfo,
                @ptrCast(&captures[index]),
                DragCapture.onReleased,
            ),
        );
        _ = try reactor.canvas_position_z(
            &builder,
            game.value.*.cards[index].left,
            game.value.*.cards[index].top,
            if (game.value.*.cards[index].dragging) DragZ else @as(i32, @intCast(index)),
        );
        children[built] = try builder.build();
        child_refs[built] = &children[built];
        built += 1;
    }
    defer {
        for (children[0..built]) |*element| {
            element.deinit(allocator);
        }
    }

    var board = try reactor.canvas(allocator, child_refs);
    defer board.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", title_text);
    _ = try window_builder.child(&board);
    return window_builder.build();
}

fn reduceAction(action: *const Action, previous: *const Game) Game {
    var next = previous.*;
    switch (action.*) {
        .reset => return .{},
        .press => |payload| {
            const card = &next.cards[payload.card_index];
            if (card.locked) return previous.*;
            card.dragging = true;
            card.offset_x = payload.info.x - card.left;
            card.offset_y = payload.info.y - card.top;
            return next;
        },
        .move => |payload| {
            const card = &next.cards[payload.card_index];
            if (!card.dragging) return previous.*;
            card.left = payload.info.x - card.offset_x;
            card.top = payload.info.y - card.offset_y;
            return next;
        },
        .release => |payload| {
            const card = &next.cards[payload.card_index];
            if (!card.dragging) return previous.*;
            const drop_left = payload.info.x - card.offset_x;
            const drop_top = payload.info.y - card.offset_y;
            card.dragging = false;
            card.offset_x = 0;
            card.offset_y = 0;

            if (tryPlaceOnFoundation(&next, payload.card_index, drop_left, drop_top)) {
                return next;
            }

            card.left = card.home_left;
            card.top = card.home_top;
            return next;
        },
    }
}

fn tryPlaceOnFoundation(game: *Game, card_index: usize, drop_left: f64, drop_top: f64) bool {
    const card = &game.cards[card_index];
    const foundation_index = card.suit.foundationIndex();
    const expected_rank = game.foundations[foundation_index] + 1;
    if (card.rank != expected_rank) return false;

    if (!isNear(drop_left, drop_top, FoundationX[foundation_index], FoundationY)) {
        return false;
    }

    game.foundations[foundation_index] = card.rank;
    card.left = FoundationX[foundation_index];
    card.top = FoundationY + (@as(f64, @floatFromInt(card.rank - 1)) * 24);
    card.locked = true;
    return true;
}

fn isNear(left: f64, top: f64, target_left: f64, target_top: f64) bool {
    return @abs(left - target_left) <= 70 and
        @abs(top - target_top) <= 70;
}

fn placedCardCount(game: *const Game) usize {
    var total: usize = 0;
    for (game.cards) |card| {
        if (card.locked) total += 1;
    }
    return total;
}

fn initialCards() [CardCount]Card {
    return .{
        .{
            .label = "A♠",
            .suit = .spades,
            .rank = 1,
            .home_left = TableauX[0],
            .home_top = TableauY[0],
            .left = TableauX[0],
            .top = TableauY[0],
        },
        .{
            .label = "2♠",
            .suit = .spades,
            .rank = 2,
            .home_left = TableauX[0],
            .home_top = TableauY[1],
            .left = TableauX[0],
            .top = TableauY[1],
        },
        .{
            .label = "A♥",
            .suit = .hearts,
            .rank = 1,
            .home_left = TableauX[1],
            .home_top = TableauY[0],
            .left = TableauX[1],
            .top = TableauY[0],
        },
        .{
            .label = "2♥",
            .suit = .hearts,
            .rank = 2,
            .home_left = TableauX[1],
            .home_top = TableauY[1],
            .left = TableauX[1],
            .top = TableauY[1],
        },
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
