const std = @import("std");
const reactor = @import("win-reactor");

const Options = struct {
    exit_after_ms: ?u32 = null,
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

    var button_builder = reactor.button(allocator);
    defer button_builder.deinit();
    _ = try button_builder.prop("Content", @as([]const u8, "WinUI 3 button"));

    var text_builder = reactor.text_block(allocator);
    defer text_builder.deinit();
    _ = try text_builder.prop("Text", @as([]const u8, "Hello from the reconciler-driven backend."));

    var stack_builder = reactor.stack_panel(allocator);
    defer stack_builder.deinit();
    _ = try stack_builder.prop("Orientation", reactor.XamlControls.Orientation.Vertical);
    _ = try stack_builder.prop("Spacing", @as(f64, 12.0));
    _ = try stack_builder.child(&button_builder);
    _ = try stack_builder.child(&text_builder);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor hello"));
    _ = try window_builder.child(&stack_builder);

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
