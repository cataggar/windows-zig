const std = @import("std");

const backend = @import("backend.zig");
const element = @import("element.zig");
const attached_props = @import("reactor-generated-attached-props");
const RecordingBackend = @import("recording_backend.zig").RecordingBackend;
const Reconciler = @import("reconciler.zig").Reconciler;
const RequestRerender = @import("render_cx.zig").RequestRerender;
const render_cx = @import("render_cx.zig");

pub const Allocator = element.Allocator;
pub const CanvasBuilder = element.CanvasBuilder;
pub const PointerEventInfo = element.PointerEventInfo;
pub const canvas_builder = element.canvas;

pub fn canvas(allocator: Allocator, children: anytype) element.Error!element.Element {
    var builder = element.canvas(allocator);
    defer builder.deinit();
    _ = try builder.childrenFrom(children);
    return builder.build();
}

pub fn canvas_position(
    builder: anytype,
    left: f64,
    top: f64,
) element.Error!@TypeOf(builder) {
    _ = try (try builder.attached(attached_props.Canvas.left(left))).attached(attached_props.Canvas.top(top));
    return builder;
}

pub fn canvas_position_z(
    builder: anytype,
    left: f64,
    top: f64,
    z_index: i32,
) element.Error!@TypeOf(builder) {
    _ = try (try canvas_position(builder, left, top)).attached(attached_props.Canvas.z_index(z_index));
    return builder;
}

test "canvas helper builds manifest-backed canvas elements" {
    var child_builder = element.text_block(std.testing.allocator);
    defer child_builder.deinit();
    _ = try child_builder.prop("Text", @as([]const u8, "Drag me"));

    var child = try child_builder.build();
    defer child.deinit(std.testing.allocator);

    var root = try canvas(std.testing.allocator, .{&child});
    defer root.deinit(std.testing.allocator);

    try std.testing.expect(root == .widget);
    try std.testing.expectEqual(element.WidgetKind.canvas, root.widget.kind);
    try std.testing.expectEqual(@as(usize, 1), root.widget.children.len);
    try std.testing.expectEqual(element.WidgetKind.text_block, root.widget.children[0].widget.kind);
}

test "canvas position helpers write attached-property names" {
    var builder = element.button(std.testing.allocator);
    defer builder.deinit();

    _ = try builder.prop("Content", @as([]const u8, "Drag me"));
    _ = try canvas_position_z(&builder, 32, 64, 3);

    var positioned = try builder.build();
    defer positioned.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f64, 32), positioned.widget.propertyValue(f64, "Left").?);
    try std.testing.expectEqual(@as(f64, 64), positioned.widget.propertyValue(f64, "Top").?);
    try std.testing.expectEqual(@as(i32, 3), positioned.widget.propertyValue(i32, "ZIndex").?);
}

test "pointer drag handlers update canvas positioned widgets through the reconciler" {
    const DragState = struct {
        left: f64 = 20,
        top: f64 = 30,
        dragging: bool = false,
        offset_x: f64 = 0,
        offset_y: f64 = 0,
    };

    const Capture = struct {
        state: DragState = .{},
        setter: ?render_cx.SetState(DragState) = null,

        fn onPressed(raw: ?*anyopaque, info: PointerEventInfo) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var next = self.state;
            next.dragging = true;
            next.offset_x = info.x - self.state.left;
            next.offset_y = info.y - self.state.top;
            self.setter.?.call(next);
        }

        fn onMoved(raw: ?*anyopaque, info: PointerEventInfo) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!self.state.dragging) return;

            var next = self.state;
            next.left = info.x - self.state.offset_x;
            next.top = info.y - self.state.offset_y;
            self.setter.?.call(next);
        }

        fn onReleased(raw: ?*anyopaque, info: PointerEventInfo) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!self.state.dragging) return;

            var next = self.state;
            next.left = info.x - self.state.offset_x;
            next.top = info.y - self.state.offset_y;
            next.dragging = false;
            self.setter.?.call(next);
        }
    };

    const Props = struct {
        capture: *Capture,
    };

    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!element.Element {
            const state = try cx.useState(DragState, .{});
            props.capture.state = state.value.*;
            props.capture.setter = state.set;

            var button_builder = element.button(cx.getAllocator());
            defer button_builder.deinit();

            _ = try button_builder.prop("Content", @as([]const u8, "Drag me"));
            _ = try button_builder.on(
                "PointerPressed",
                element.EventCallback.initTyped(
                    PointerEventInfo,
                    @ptrCast(props.capture),
                    Capture.onPressed,
                ),
            );
            _ = try button_builder.on(
                "PointerMoved",
                element.EventCallback.initTyped(
                    PointerEventInfo,
                    @ptrCast(props.capture),
                    Capture.onMoved,
                ),
            );
            _ = try button_builder.on(
                "PointerReleased",
                element.EventCallback.initTyped(
                    PointerEventInfo,
                    @ptrCast(props.capture),
                    Capture.onReleased,
                ),
            );
            _ = try canvas_position_z(
                &button_builder,
                state.value.*.left,
                state.value.*.top,
                if (state.value.*.dragging) 1 else 0,
            );

            var button = try button_builder.build();
            defer button.deinit(cx.getAllocator());
            return canvas(cx.getAllocator(), .{&button});
        }
    };

    var capture: Capture = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();

    var reconciler = Reconciler.init(
        std.testing.allocator,
        backend.Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var first = try element.component(
        std.testing.allocator,
        "drag-surface",
        Props{ .capture = &capture },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;

    const canvas_id = backend_state.rootChildren()[0];
    const button_id = backend_state.childrenOf(canvas_id)[0];

    try std.testing.expectEqual(element.WidgetKind.canvas, backend_state.kindOf(canvas_id).?);
    try std.testing.expectEqual(@as(f64, 20), backend_state.propertyValue(f64, button_id, "Left").?);
    try std.testing.expectEqual(@as(f64, 30), backend_state.propertyValue(f64, button_id, "Top").?);
    try std.testing.expect(backend_state.hasEventHandler(button_id, "PointerPressed"));
    try std.testing.expect(backend_state.hasEventHandler(button_id, "PointerMoved"));
    try std.testing.expect(backend_state.hasEventHandler(button_id, "PointerReleased"));

    backend_state.clearCalls();
    try backend_state.fireEventValue(button_id, "PointerPressed", .{
        .pointer = .{
            .x = 35,
            .y = 50,
            .is_left_button_pressed = true,
        },
    });

    var second = try element.component(
        std.testing.allocator,
        "drag-surface",
        Props{ .capture = &capture },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(i32, 1), backend_state.propertyValue(i32, button_id, "ZIndex").?);
    try std.testing.expectEqual(@as(usize, 0), backend_state.callCountOf(.attach_event));
    try std.testing.expectEqual(@as(usize, 0), backend_state.callCountOf(.detach_event));

    backend_state.clearCalls();
    try backend_state.fireEventValue(button_id, "PointerMoved", .{
        .pointer = .{
            .x = 70,
            .y = 95,
            .is_left_button_pressed = true,
        },
    });

    var third = try element.component(
        std.testing.allocator,
        "drag-surface",
        Props{ .capture = &capture },
        Render.call,
    );
    defer third.deinit(std.testing.allocator);

    try reconciler.update(&tree, &third);
    try std.testing.expectEqual(@as(f64, 55), backend_state.propertyValue(f64, button_id, "Left").?);
    try std.testing.expectEqual(@as(f64, 75), backend_state.propertyValue(f64, button_id, "Top").?);

    backend_state.clearCalls();
    try backend_state.fireEventValue(button_id, "PointerReleased", .{
        .pointer = .{
            .x = 80,
            .y = 120,
        },
    });

    var fourth = try element.component(
        std.testing.allocator,
        "drag-surface",
        Props{ .capture = &capture },
        Render.call,
    );
    defer fourth.deinit(std.testing.allocator);

    try reconciler.update(&tree, &fourth);
    try std.testing.expectEqual(@as(f64, 65), backend_state.propertyValue(f64, button_id, "Left").?);
    try std.testing.expectEqual(@as(f64, 100), backend_state.propertyValue(f64, button_id, "Top").?);
    try std.testing.expectEqual(@as(i32, 0), backend_state.propertyValue(i32, button_id, "ZIndex").?);
}
