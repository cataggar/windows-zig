//! Minimal draggable Canvas sample built on the WinUI-backed reactor stack.
//!
//! Run interactively:
//!   zig build run-reactor-canvas-drag
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-canvas-drag -- --exit-after-ms 1500

const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const DragState = struct {
    left: f64 = 32,
    top: f64 = 72,
    dragging: bool = false,
    offset_x: f64 = 0,
    offset_y: f64 = 0,
};

const DragCapture = struct {
    state: DragState = .{},
    setter: ?reactor.SetState(DragState) = null,

    fn onPressed(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var next = self.state;
        next.dragging = true;
        next.offset_x = info.x - self.state.left;
        next.offset_y = info.y - self.state.top;
        self.setter.?.call(next);
    }

    fn onMoved(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (!self.state.dragging) return;

        var next = self.state;
        next.left = info.x - self.state.offset_x;
        next.top = info.y - self.state.offset_y;
        self.setter.?.call(next);
    }

    fn onReleased(raw: ?*anyopaque, info: reactor.PointerEventInfo) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (!self.state.dragging) return;

        var next = self.state;
        next.left = info.x - self.state.offset_x;
        next.top = info.y - self.state.offset_y;
        next.dragging = false;
        self.setter.?.call(next);
    }
};

const PositionLabel = struct {
    buffer: [64]u8 = undefined,
    text: []const u8 = "",

    fn update(self: *@This(), state: DragState) []const u8 {
        self.text = std.fmt.bufPrint(
            &self.buffer,
            "Drag the button (x={d:.0}, y={d:.0})",
            .{ state.left, state.top },
        ) catch unreachable;
        return self.text;
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
    const drag = try cx.useState(DragState, .{});

    const capture = try cx.useRef(DragCapture, .{});
    capture.getMut().* = .{
        .state = drag.value.*,
        .setter = drag.set,
    };

    const label = try cx.useRef(PositionLabel, .{});
    const label_text = label.getMut().update(drag.value.*);

    var instructions_builder = reactor.text_block_builder(allocator);
    defer instructions_builder.deinit();
    _ = try instructions_builder.prop("Text", label_text);
    _ = try reactor.canvas_position(&instructions_builder, 20, 20);
    var instructions = try instructions_builder.build();
    defer instructions.deinit(allocator);

    var draggable_builder = reactor.button_builder(allocator);
    defer draggable_builder.deinit();
    _ = try draggable_builder.prop("Content", @as([]const u8, "Drag me"));
    _ = try draggable_builder.on(
        "PointerPressed",
        reactor.EventCallback.initTyped(
            reactor.PointerEventInfo,
            @ptrCast(capture.getMut()),
            DragCapture.onPressed,
        ),
    );
    _ = try draggable_builder.on(
        "PointerMoved",
        reactor.EventCallback.initTyped(
            reactor.PointerEventInfo,
            @ptrCast(capture.getMut()),
            DragCapture.onMoved,
        ),
    );
    _ = try draggable_builder.on(
        "PointerReleased",
        reactor.EventCallback.initTyped(
            reactor.PointerEventInfo,
            @ptrCast(capture.getMut()),
            DragCapture.onReleased,
        ),
    );
    _ = try reactor.canvas_position_z(
        &draggable_builder,
        drag.value.*.left,
        drag.value.*.top,
        if (drag.value.*.dragging) 1 else 0,
    );
    var draggable = try draggable_builder.build();
    defer draggable.deinit(allocator);

    var surface = try reactor.canvas(allocator, .{ &instructions, &draggable });
    defer surface.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor canvas drag"));
    _ = try window_builder.child(&surface);
    return window_builder.build();
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
