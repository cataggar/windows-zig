//! Minimal notepad-style reactor sample.
//!
//! Canonical validation sample for real WinUI `TextBox` construction
//! (issues #74/#86). Run interactively:
//!   zig build run-reactor-notepad

const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const TextState = struct {
    revision: u32 = 0,
    text: []const u8 = "",
};

const TextStorage = struct {
    buffers: [2]std.ArrayListUnmanaged(u8) = .{ .empty, .empty },
    active: usize = 0,

    fn current(self: *const @This()) []const u8 {
        return self.buffers[self.active].items;
    }

    fn replace(self: *@This(), allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.buffers[next].clearRetainingCapacity();
        try self.buffers[next].appendSlice(allocator, value);
        self.active = next;
        return self.buffers[next].items;
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (&self.buffers) |*buffer| {
            buffer.deinit(allocator);
        }
    }
};

const TitleLabel = struct {
    buffers: [2][96]u8 = undefined,
    active: usize = 0,
    text: []const u8 = "",

    fn update(self: *@This(), value: []const u8) []const u8 {
        const next = (self.active + 1) % self.buffers.len;
        self.text = std.fmt.bufPrint(
            &self.buffers[next],
            "windows-zig reactor notepad — {d} chars",
            .{value.len},
        ) catch unreachable;
        self.active = next;
        return self.text;
    }
};

const TextChangedCapture = struct {
    allocator: std.mem.Allocator = undefined,
    storage: *TextStorage = undefined,
    state: TextState = .{},
    setter: ?reactor.SetState(TextState) = null,

    fn onTextChanged(raw: ?*anyopaque, value: []const u8) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const next_text = self.storage.replace(self.allocator, value) catch return;
        self.setter.?.call(.{
            .revision = self.state.revision +% 1,
            .text = next_text,
        });
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
    const text = try cx.useState(TextState, .{});
    const storage = try cx.useRef(TextStorage, .{});

    const title = try cx.useRef(TitleLabel, .{});
    const title_text = title.getMut().update(text.value.*.text);

    const text_changed = try cx.useRef(TextChangedCapture, .{});
    text_changed.getMut().* = .{
        .allocator = allocator,
        .storage = storage.getMut(),
        .state = text.value.*,
        .setter = text.set,
    };

    var editor = try reactor.text_box(
        allocator,
        if (text.value.*.text.len > 0) text.value.*.text else storage.get().current(),
        reactor.EventCallback.initTyped(
            []const u8,
            @ptrCast(text_changed.getMut()),
            TextChangedCapture.onTextChanged,
        ),
    );
    defer editor.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", title_text);
    _ = try window_builder.child(&editor);
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
