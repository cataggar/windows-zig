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

const CheckCapture = struct {
    setter: ?reactor.SetState(bool) = null,

    fn onChecked(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.setter.?.call(true);
    }

    fn onUnchecked(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.setter.?.call(false);
    }
};

const RotateTextCapture = struct {
    index: usize = 0,
    total: usize = 1,
    setter: ?reactor.SetState(usize) = null,

    fn onClick(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.setter.?.call((self.index + 1) % self.total);
    }
};

const InputStatusLabel = struct {
    buffers: [2][160]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), is_checked: bool, current_text: []const u8) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "CheckBox: {s} | Active preset: {s}",
            .{ if (is_checked) "checked" else "unchecked", current_text },
        ) catch unreachable;
        self.active = next;
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
    app.render(renderRoot) catch |err| {
        std.log.err("reactor-counter failed: {s}", .{@errorName(err)});
        return err;
    };
}

fn renderRoot(cx: *reactor.RenderCx) reactor.ElementError!reactor.Element {
    const allocator = cx.getAllocator();
    const count = try cx.useState(i32, 0);
    const text_index = try cx.useState(usize, 0);
    const is_checked = try cx.useState(bool, false);

    const text_presets = [_][]const u8{
        "Hello from win-reactor",
        "Props updated this TextBox",
        "TextBox + CheckBox sample",
    };
    const current_text = text_presets[text_index.value.*];

    const count_label = try cx.useRef(CountLabel, .{});
    const count_text = count_label.getMut().update(count.value.*);

    const input_status = try cx.useRef(InputStatusLabel, .{});
    const input_status_text = input_status.getMut().update(is_checked.value.*, current_text);

    const click_capture = try cx.useRef(ClickCapture, .{});
    click_capture.getMut().* = .{
        .count = count.value.*,
        .setter = count.set,
    };

    const check_capture = try cx.useRef(CheckCapture, .{});
    check_capture.getMut().* = .{
        .setter = is_checked.set,
    };

    const rotate_capture = try cx.useRef(RotateTextCapture, .{});
    rotate_capture.getMut().* = .{
        .index = text_index.value.*,
        .total = text_presets.len,
        .setter = text_index.set,
    };

    var title = try reactor.text_block(allocator, "Counter + basic input sample");
    defer title.deinit(allocator);

    var counter_text = try reactor.text_block(allocator, count_text);
    defer counter_text.deinit(allocator);

    var increment = try reactor.button(
        allocator,
        "Increment",
        reactor.EventCallback.init(@ptrCast(click_capture.getMut()), ClickCapture.onClick),
    );
    defer increment.deinit(allocator);

    var prompt = try reactor.text_block(allocator, "Rotate the preset and toggle the CheckBox:");
    defer prompt.deinit(allocator);

    var preset = try reactor.text_block(allocator, current_text);
    defer preset.deinit(allocator);

    var accepted = try reactor.check_box(
        allocator,
        "Check me",
        is_checked.value.*,
        reactor.EventCallback.init(@ptrCast(check_capture.getMut()), CheckCapture.onChecked),
        reactor.EventCallback.init(@ptrCast(check_capture.getMut()), CheckCapture.onUnchecked),
    );
    defer accepted.deinit(allocator);

    var rotate = try reactor.button(
        allocator,
        "Rotate Text",
        reactor.EventCallback.init(@ptrCast(rotate_capture.getMut()), RotateTextCapture.onClick),
    );
    defer rotate.deinit(allocator);

    var actions = try reactor.hstack(allocator, .{ &increment, &rotate });
    defer actions.deinit(allocator);

    var status = try reactor.text_block(allocator, input_status_text);
    defer status.deinit(allocator);

    var content = try reactor.vstack(allocator, .{
        &title,
        &counter_text,
        &prompt,
        &preset,
        &accepted,
        &actions,
        &status,
    });
    defer content.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor counter + inputs"));
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
