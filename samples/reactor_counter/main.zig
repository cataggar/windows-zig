//! Minimal end-to-end counter built on the real WinUI-backed reactor stack.
//!
//! Run interactively:
//!   zig build run-reactor-counter
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-reactor-counter -- --exit-after-ms 1500

const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const CountLabel = struct {
    buffers: [2][32]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), count: i32) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(&self.buffers[next], "Count: {d}", .{count}) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const ClickCapture = struct {
    count: i32 = 0,
    setter: ?reactor.SetState(i32) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.setter.?.call(self.count + 1);
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
    const count = try cx.useState(i32, 0);

    const label_state = try cx.useRef(CountLabel, .{});
    const label_text = label_state.getMut().update(count.value.*);

    const click_capture = try cx.useRef(ClickCapture, .{});
    click_capture.getMut().* = .{
        .count = count.value.*,
        .setter = count.set,
    };

    const rows = reactor.GridTracks.init(.{
        reactor.GridTrack.auto(),
        reactor.GridTrack.auto(),
        reactor.GridTrack.auto(),
    });
    const columns = reactor.GridTracks.init(.{
        reactor.GridTrack.star(1),
        reactor.GridTrack.auto(),
    });

    var title_builder = reactor.text_block_builder(allocator);
    defer title_builder.deinit();
    _ = try (try (try title_builder.prop("Text", @as([]const u8, "Nested layout counter")))
        .prop("Grid.Row", @as(i32, 0)))
        .prop("Grid.ColumnSpan", @as(i32, 2));
    var title = try title_builder.build();
    defer title.deinit(allocator);

    var label_builder = reactor.text_block_builder(allocator);
    defer label_builder.deinit();
    _ = try (try (try label_builder.prop("Text", label_text))
        .prop("Grid.Row", @as(i32, 1)))
        .prop("Grid.Column", @as(i32, 0));
    var label = try label_builder.build();
    defer label.deinit(allocator);

    var increment_builder = reactor.button_builder(allocator);
    defer increment_builder.deinit();
    _ = try (try (try increment_builder.prop("Content", @as([]const u8, "+")))
        .prop("Grid.Row", @as(i32, 1)))
        .prop("Grid.Column", @as(i32, 1));
    _ = try increment_builder.on(
        "Click",
        reactor.EventCallback.init(@ptrCast(click_capture.getMut()), ClickCapture.onClick),
    );
    var increment = try increment_builder.build();
    defer increment.deinit(allocator);

    var detail_builder = reactor.text_block_builder(allocator);
    defer detail_builder.deinit();
    _ = try (try (try detail_builder.prop("Text", @as([]const u8, "ScrollViewer → Border → Grid")))
        .prop("Grid.Row", @as(i32, 2)))
        .prop("Grid.ColumnSpan", @as(i32, 2));
    var detail = try detail_builder.build();
    defer detail.deinit(allocator);

    var content = try reactor.grid(
        allocator,
        .{
            .row_definitions = rows,
            .column_definitions = columns,
        },
        .{ &title, &label, &increment, &detail },
    );
    defer content.deinit(allocator);

    var chrome = try reactor.border(
        allocator,
        .{
            .border_thickness = reactor.uniform_thickness(1),
            .corner_radius = reactor.uniform_corner_radius(12),
            .background = reactor.Color.rgb(0x24, 0x24, 0x24),
        },
        &content,
    );
    defer chrome.deinit(allocator);

    var scroller = try reactor.scroll_viewer(allocator, &chrome);
    defer scroller.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor layout counter"));
    _ = try window_builder.child(&scroller);
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
