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

const DialogResultLabel = struct {
    buffers: [2][48]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), result: ?reactor.ContentDialogResult) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        const value = result orelse {
            self.text = "Last dialog result: <none>";
            return self.text;
        };

        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "Last dialog result: {s}",
            .{@tagName(value)},
        ) catch unreachable;
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

const DialogWorker = struct {
    future: reactor.ContentDialogFuture,
    result_setter: reactor.AsyncSetState(?reactor.ContentDialogResult),
};

const DialogClickCapture = struct {
    dialog: ?reactor.ContentDialogHandle = null,
    result_setter: ?reactor.AsyncSetState(?reactor.ContentDialogResult) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var future = self.dialog.?.showAsync() catch return;

        const worker = std.heap.page_allocator.create(DialogWorker) catch {
            future.deinit();
            return;
        };
        worker.* = .{
            .future = future,
            .result_setter = self.result_setter.?,
        };

        const thread = std.Thread.spawn(.{}, waitForDialogResult, .{worker}) catch {
            worker.future.deinit();
            std.heap.page_allocator.destroy(worker);
            return;
        };
        thread.detach();
    }
};

fn waitForDialogResult(worker: *DialogWorker) void {
    defer std.heap.page_allocator.destroy(worker);

    const hr = reactor.Win.core.winrt.RoInitialize(.multi_threaded);
    const should_uninitialize = hr >= 0;
    defer if (should_uninitialize) reactor.Win.core.winrt.RoUninitialize();

    const result = worker.future.wait(std.heap.page_allocator) catch return;
    worker.result_setter.call(result);
}

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
    const dialog_result = try cx.useAsyncState(?reactor.ContentDialogResult, null);

    const label_state = try cx.useRef(CountLabel, .{});
    const label_text = label_state.getMut().update(count.value.*);

    const dialog_label_state = try cx.useRef(DialogResultLabel, .{});
    const dialog_label_text = dialog_label_state.getMut().update(dialog_result.value);

    const click_capture = try cx.useRef(ClickCapture, .{});
    click_capture.getMut().* = .{
        .count = count.value.*,
        .setter = count.set,
    };

    const dialog_ref = try cx.useRef(reactor.WidgetRef, .{});
    const dialog_handle = try reactor.useContentDialog(cx, dialog_ref.getMut());

    const dialog_click_capture = try cx.useRef(DialogClickCapture, .{});
    dialog_click_capture.getMut().* = .{
        .dialog = dialog_handle,
        .result_setter = dialog_result.set,
    };

    var label = try reactor.text_block(allocator, label_text);
    defer label.deinit(allocator);

    var increment = try reactor.button(
        allocator,
        "+",
        reactor.EventCallback.init(@ptrCast(click_capture.getMut()), ClickCapture.onClick),
    );
    defer increment.deinit(allocator);

    var show_dialog = try reactor.button(
        allocator,
        "Show dialog",
        reactor.EventCallback.init(@ptrCast(dialog_click_capture.getMut()), DialogClickCapture.onClick),
    );
    defer show_dialog.deinit(allocator);

    var dialog_result_label = try reactor.text_block(allocator, dialog_label_text);
    defer dialog_result_label.deinit(allocator);

    var dialog_body = try reactor.text_block(
        allocator,
        "Dismiss the ContentDialog to round-trip a ContentDialogResult through win-future.",
    );
    defer dialog_body.deinit(allocator);

    var dialog = try reactor.content_dialog(
        allocator,
        .{
            .title = "Reactor dialog sample",
            .primary_button_text = "Primary",
            .secondary_button_text = "Secondary",
            .close_button_text = "Close",
            .ref = dialog_ref.getMut(),
        },
        &dialog_body,
    );
    defer dialog.deinit(allocator);

    var content = try reactor.vstack(
        allocator,
        .{ &label, &increment, &show_dialog, &dialog_result_label, &dialog },
    );
    defer content.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor counter"));
    _ = try window_builder.child(&content);
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
