//! Reactor code generators for property setters and event connectors.

const std = @import("std");
const winmd = @import("winmd");

const manifest_mod = @import("manifest.zig");

pub const SetPropFileName = "generated_set_prop.zig";
pub const AttachEventFileName = "generated_attach_event.zig";

const Event = manifest_mod.Event;
const EventPayload = manifest_mod.EventPayload;
const EventSource = manifest_mod.EventSource;
const Property = manifest_mod.Property;
const SetterKind = manifest_mod.SetterKind;
const ValueKind = manifest_mod.ValueKind;
const Widget = manifest_mod.Widget;

const Binding = struct {
    widget: *const Widget,
    prop: *const Property,
    value_kind: ValueKind,
    setter_kind: SetterKind,
    setter: ResolvedSetter,
};

const ResolvedSetter = struct {
    interface_namespace: []const u8,
    interface_name: []const u8,
    method_name: []const u8,
    param_ty: winmd.Ty,
    owner_namespace: ?[]const u8 = null,
    owner_name: ?[]const u8 = null,
};

const EventBinding = struct {
    widget: *const Widget,
    event: *const Event,
    payload: ?EventPayload,
    source: EventSource,
    registration: ResolvedEvent,
};

const ResolvedEvent = struct {
    interface_namespace: []const u8,
    interface_name: []const u8,
    add_method_name: []const u8,
    remove_method_name: []const u8,
    delegate_iid: GuidLiteral,
};

const QualifiedName = struct {
    namespace: []const u8,
    name: []const u8,
};

const GuidLiteral = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

pub fn emitSetPropFromManifest(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
) !void {
    var manifest = try manifest_mod.load(gpa);
    defer manifest.deinit();

    try emitSetProp(writer, gpa, file, manifest.widgets);
}

pub fn emitSetProp(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    widgets: []const Widget,
) !void {
    var type_index = try winmd.TypeIndex.init(gpa, file);
    defer type_index.deinit();

    var sig_arena = std.heap.ArenaAllocator.init(gpa);
    defer sig_arena.deinit();

    var bindings = try std.ArrayList(Binding).initCapacity(gpa, 0);
    defer bindings.deinit(gpa);

    for (widgets) |*widget| {
        for (widget.props) |*prop| {
            if (prop.manual) continue;
            try bindings.append(gpa, try resolveBinding(
                sig_arena.allocator(),
                gpa,
                file,
                &type_index,
                widget,
                prop,
            ));
        }
    }

    std.mem.sort(Binding, bindings.items, {}, struct {
        fn lt(_: void, a: Binding, b: Binding) bool {
            const widget_order = std.mem.order(u8, a.widget.class_name, b.widget.class_name);
            if (widget_order != .eq) return widget_order == .lt;
            return std.mem.lessThan(u8, a.prop.name, b.prop.name);
        }
    }.lt);

    var imports: std.StringHashMapUnmanaged(void) = .empty;
    defer imports.deinit(gpa);

    var used_kinds = try std.ArrayList(ValueKind).initCapacity(gpa, 0);
    defer used_kinds.deinit(gpa);

    var needs_win_reference = false;
    for (bindings.items) |binding| {
        try collectImports(gpa, &imports, binding);
        try appendValueKind(gpa, &used_kinds, binding.value_kind);
        needs_win_reference = needs_win_reference or binding.setter_kind == .boxed_reference;
    }

    std.mem.sort(ValueKind, used_kinds.items, {}, struct {
        fn lt(_: void, a: ValueKind, b: ValueKind) bool {
            return @intFromEnum(a) < @intFromEnum(b);
        }
    }.lt);

    try emitHeader(writer, gpa, imports, used_kinds.items, needs_win_reference);

    for (bindings.items) |binding| {
        try emitTypedSetter(writer, binding);
        try emitErasedSetter(writer, binding);
    }

    try emitEntries(writer, bindings.items);
    try emitLookup(writer, bindings.items);
}

pub fn emitAttachEventFromManifest(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
) !void {
    var manifest = try manifest_mod.load(gpa);
    defer manifest.deinit();

    try emitAttachEvent(writer, gpa, file, manifest.widgets);
}

pub fn emitAttachEvent(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    widgets: []const Widget,
) !void {
    var type_index = try winmd.TypeIndex.init(gpa, file);
    defer type_index.deinit();

    var sig_arena = std.heap.ArenaAllocator.init(gpa);
    defer sig_arena.deinit();

    var bindings = try std.ArrayList(EventBinding).initCapacity(gpa, 0);
    defer bindings.deinit(gpa);

    for (widgets) |*widget| {
        for (widget.events) |*event| {
            if (event.manual) continue;
            try bindings.append(gpa, try resolveEventBinding(
                sig_arena.allocator(),
                gpa,
                file,
                &type_index,
                widget,
                event,
            ));
        }
    }

    std.mem.sort(EventBinding, bindings.items, {}, struct {
        fn lt(_: void, a: EventBinding, b: EventBinding) bool {
            const widget_order = std.mem.order(u8, a.widget.class_name, b.widget.class_name);
            if (widget_order != .eq) return widget_order == .lt;
            return std.mem.lessThan(u8, a.event.name, b.event.name);
        }
    }.lt);

    var imports: std.StringHashMapUnmanaged(void) = .empty;
    defer imports.deinit(gpa);
    for (bindings.items) |binding| {
        try collectEventImports(gpa, &imports, binding);
    }

    try emitEventHeader(writer, gpa, imports);
    for (bindings.items) |binding| {
        try emitTypedEventConnect(writer, binding);
        try emitErasedEventConnect(writer, binding);
        try emitTypedEventDisconnect(writer, binding);
        try emitErasedEventDisconnect(writer, binding);
    }
    try emitEventEntries(writer, bindings.items);
    try emitEventLookup(writer, bindings.items);
}

fn emitHeader(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    imports: std.StringHashMapUnmanaged(void),
    used_kinds: []const ValueKind,
    needs_win_reference: bool,
) !void {
    try writer.writeAll("// Generated by winbindgen reactor-bindings - do not edit.\n");
    try writer.writeAll("const std = @import(\"std\");\n");
    try writer.writeAll("const schema = @import(\"reactor-schema\");\n");
    try writer.writeAll("const win_core = @import(\"win-core\");\n");
    if (needs_win_reference) {
        try writer.writeAll("const win_reference = @import(\"win-reference\");\n");
    }

    var namespaces = try std.ArrayList([]const u8).initCapacity(gpa, imports.count());
    defer namespaces.deinit(gpa);

    var it = imports.iterator();
    while (it.next()) |entry| {
        try namespaces.append(gpa, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, namespaces.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    for (namespaces.items) |namespace| {
        try writer.print("const @\"{s}\" = @import(\"{s}\");\n", .{ namespace, namespace });
    }

    try writer.writeAll(
        \\
        \\pub const ValueKind = schema.ValueKind;
        \\pub const SetterKind = schema.SetterKind;
        \\
        \\pub const Error = win_core.hresult.Error || error{
        \\    InterfaceCastFailed,
        \\    ValueKindMismatch,
        \\};
        \\
    );

    try emitSetterValueUnion(writer, used_kinds);

    try writer.writeAll(
        \\pub const SetterFn = *const fn (widget: *anyopaque, value: SetterValue) Error!void;
        \\
        \\pub const PropertySetter = struct {
        \\    widget_class: []const u8,
        \\    widget_name: []const u8,
        \\    handle_name: []const u8,
        \\    property_name: []const u8,
        \\    field_name: []const u8,
        \\    value_kind: ValueKind,
        \\    setter_kind: SetterKind,
        \\    apply: SetterFn,
        \\};
        \\
    );
}

fn emitSetterValueUnion(writer: *std.Io.Writer, used_kinds: []const ValueKind) !void {
    try writer.writeAll("pub const SetterValue = union(enum) {\n");
    for (used_kinds) |kind| {
        try writer.print("    {s}: ", .{@tagName(kind)});
        try writeValueType(writer, kind);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("};\n\n");
}

fn emitTypedSetter(writer: *std.Io.Writer, binding: Binding) !void {
    try writer.writeAll("pub fn ");
    try writeBindingStem(writer, "set", binding);
    try writer.writeAll("(widget: *");
    try writeQualifiedType(writer, .{
        .namespace = binding.widget.namespace,
        .name = binding.widget.short_name,
    });
    try writer.writeAll(", value: ");
    try writeValueType(writer, binding.value_kind);
    try writer.writeAll(") Error!void {\n");

    if (binding.setter_kind == .attached) {
        try emitAttachedSetterCall(writer, binding);
        try writer.writeAll("}\n\n");
        return;
    }

    if (bindingUsesQueryInterface(binding)) {
        try writer.writeAll("    const default_iface: *const ");
        try writeDefaultInterfaceType(writer, binding.widget);
        try writer.writeAll(" = @ptrCast(widget);\n");
        try writer.writeAll("    const target = default_iface.cast(");
        try writeQualifiedType(writer, .{
            .namespace = binding.setter.interface_namespace,
            .name = binding.setter.interface_name,
        });
        try writer.writeAll(") orelse return error.InterfaceCastFailed;\n");
        try writer.writeAll("    defer _ = target.Release();\n");
    } else {
        try writer.writeAll("    const target: *const ");
        try writeQualifiedType(writer, .{
            .namespace = binding.setter.interface_namespace,
            .name = binding.setter.interface_name,
        });
        try writer.writeAll(" = @ptrCast(widget);\n");
    }

    try emitSetterCall(writer, binding, "target");
    try writer.writeAll("}\n\n");
}

fn emitErasedSetter(writer: *std.Io.Writer, binding: Binding) !void {
    try writer.writeAll("fn ");
    try writeBindingStem(writer, "apply", binding);
    try writer.writeAll("(widget: *anyopaque, value: SetterValue) Error!void {\n");
    try writer.writeAll("    const typed_value = switch (value) {\n");
    try writer.print("        .{s} => |v| v,\n", .{@tagName(binding.value_kind)});
    try writer.writeAll("        else => return error.ValueKindMismatch,\n");
    try writer.writeAll("    };\n");
    try writer.writeAll("    try ");
    try writeBindingStem(writer, "set", binding);
    try writer.writeAll("(@ptrCast(@alignCast(widget)), typed_value);\n");
    try writer.writeAll("}\n\n");
}

fn emitEntries(writer: *std.Io.Writer, bindings: []const Binding) !void {
    try writer.writeAll("pub const entries = [_]PropertySetter{\n");
    for (bindings) |binding| {
        try writer.writeAll("    .{\n");
        try writer.print("        .widget_class = \"{s}\",\n", .{binding.widget.class_name});
        try writer.print("        .widget_name = \"{s}\",\n", .{binding.widget.widget_name});
        try writer.print("        .handle_name = \"{s}\",\n", .{binding.widget.handle_name});
        try writer.print("        .property_name = \"{s}\",\n", .{binding.prop.name});
        try writer.print("        .field_name = \"{s}\",\n", .{binding.prop.field});
        try writer.print("        .value_kind = .{s},\n", .{@tagName(binding.value_kind)});
        try writer.print("        .setter_kind = .{s},\n", .{@tagName(binding.setter_kind)});
        try writer.writeAll("        .apply = ");
        try writeBindingStem(writer, "apply", binding);
        try writer.writeAll(",\n");
        try writer.writeAll("    },\n");
    }
    try writer.writeAll("};\n\n");
}

fn emitLookup(writer: *std.Io.Writer, bindings: []const Binding) !void {
    try writer.writeAll("pub const by_widget_prop = std.StaticStringMap(usize).initComptime(.{\n");
    for (bindings, 0..) |binding, i| {
        try writer.print(
            "    .{{ \"{s}#{s}\", {d} }},\n",
            .{ binding.widget.class_name, binding.prop.name, i },
        );
    }
    try writer.writeAll(
        \\});
        \\
        \\pub fn find(widget_class: []const u8, property_name: []const u8) ?*const PropertySetter {
        \\    var key_buf: [512]u8 = undefined;
        \\    const key = std.fmt.bufPrint(&key_buf, "{s}#{s}", .{ widget_class, property_name }) catch return null;
        \\    const index = by_widget_prop.get(key) orelse return null;
        \\    return &entries[index];
        \\}
        \\
        \\pub fn dispatch(widget_class: []const u8, property_name: []const u8, widget: *anyopaque, value: SetterValue) Error!bool {
        \\    const entry = find(widget_class, property_name) orelse return false;
        \\    try entry.apply(widget, value);
        \\    return true;
        \\}
    );
    try writer.writeByte('\n');
}

fn emitEventHeader(
    writer: *std.Io.Writer,
    gpa: std.mem.Allocator,
    imports: std.StringHashMapUnmanaged(void),
) !void {
    try writer.writeAll("// Generated by winbindgen reactor-bindings - do not edit.\n");
    try writer.writeAll("const std = @import(\"std\");\n");
    try writer.writeAll("const schema = @import(\"reactor-schema\");\n");
    try writer.writeAll("const reactor_event_runtime = @import(\"reactor-event-runtime\");\n");
    try writer.writeAll("const win_core = @import(\"win-core\");\n");

    var namespaces = try std.ArrayList([]const u8).initCapacity(gpa, imports.count());
    defer namespaces.deinit(gpa);

    var it = imports.iterator();
    while (it.next()) |entry| {
        try namespaces.append(gpa, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, namespaces.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    for (namespaces.items) |namespace| {
        try writer.print("const @\"{s}\" = @import(\"{s}\");\n", .{ namespace, namespace });
    }

    try writer.writeAll(
        \\
        \\pub const EventPayload = schema.EventPayload;
        \\pub const EventSource = schema.EventSource;
        \\pub const EventRegistrationToken = @"Windows.Foundation".EventRegistrationToken;
        \\pub const InvokeFn = reactor_event_runtime.InvokeFn;
        \\// `null` means "not connected" so disconnect can stay idempotent
        \\// without treating token value 0 as special.
        \\pub const EventConnection = reactor_event_runtime.Connection(EventRegistrationToken);
        \\
        \\pub const Error = win_core.hresult.Error || error{
        \\    ConnectionStillActive,
        \\    InterfaceCastFailed,
        \\    OutOfMemory,
        \\};
        \\
        \\pub const ConnectFn = *const fn (
        \\    widget: *anyopaque,
        \\    allocator: std.mem.Allocator,
        \\    invoke: InvokeFn,
        \\    user_data: ?*anyopaque,
        \\) Error!EventConnection;
        \\pub const DisconnectFn = *const fn (widget: *anyopaque, connection: *EventConnection) Error!void;
        \\
        \\pub const EventConnector = struct {
        \\    widget_class: []const u8,
        \\    widget_name: []const u8,
        \\    handle_name: []const u8,
        \\    event_name: []const u8,
        \\    field_name: []const u8,
        \\    payload: ?EventPayload,
        \\    source: EventSource,
        \\    connect: ConnectFn,
        \\    disconnect: DisconnectFn,
        \\};
        \\
    );
}

fn emitTypedEventConnect(writer: *std.Io.Writer, binding: EventBinding) !void {
    try writer.writeAll("pub fn ");
    try writeEventBindingStem(writer, "connect", binding);
    try writer.writeAll("(widget: *");
    try writeQualifiedType(writer, .{
        .namespace = binding.widget.namespace,
        .name = binding.widget.short_name,
    });
    try writer.writeAll(
        ", allocator: std.mem.Allocator, invoke: InvokeFn, user_data: ?*anyopaque) Error!EventConnection {\n",
    );

    if (eventBindingUsesQueryInterface(binding)) {
        try writer.writeAll("    const default_iface: *const ");
        try writeDefaultInterfaceType(writer, binding.widget);
        try writer.writeAll(" = @ptrCast(widget);\n");
        try writer.writeAll("    const target = default_iface.cast(");
        try writeQualifiedType(writer, .{
            .namespace = binding.registration.interface_namespace,
            .name = binding.registration.interface_name,
        });
        try writer.writeAll(") orelse return error.InterfaceCastFailed;\n");
        try writer.writeAll("    defer _ = target.Release();\n");
    } else {
        try writer.writeAll("    const target: *const ");
        try writeQualifiedType(writer, .{
            .namespace = binding.registration.interface_namespace,
            .name = binding.registration.interface_name,
        });
        try writer.writeAll(" = @ptrCast(widget);\n");
    }

    try writer.writeAll("    return try reactor_event_runtime.connect(\n");
    try writer.writeAll("        EventRegistrationToken,\n");
    try writer.writeAll("        ");
    try writeGuidLiteral(writer, binding.registration.delegate_iid);
    try writer.writeAll(",\n");
    try writer.writeAll(
        \\        target,
        \\        allocator,
        \\        invoke,
        \\        user_data,
    );
    try writer.writeByte('\n');
    try writer.writeAll("        ");
    try writeQualifiedType(writer, .{
        .namespace = binding.registration.interface_namespace,
        .name = binding.registration.interface_name,
    });
    try writer.print(".{s},\n", .{binding.registration.add_method_name});
    try writer.writeAll("    );\n");
    try writer.writeAll("}\n\n");
}

fn emitErasedEventConnect(writer: *std.Io.Writer, binding: EventBinding) !void {
    try writer.writeAll("fn ");
    try writeEventBindingStem(writer, "dispatchConnect", binding);
    try writer.writeAll(
        "(widget: *anyopaque, allocator: std.mem.Allocator, invoke: InvokeFn, user_data: ?*anyopaque) Error!EventConnection {\n",
    );
    try writer.writeAll("    return try ");
    try writeEventBindingStem(writer, "connect", binding);
    try writer.writeAll("(@ptrCast(@alignCast(widget)), allocator, invoke, user_data);\n");
    try writer.writeAll("}\n\n");
}

fn emitTypedEventDisconnect(writer: *std.Io.Writer, binding: EventBinding) !void {
    try writer.writeAll("pub fn ");
    try writeEventBindingStem(writer, "disconnect", binding);
    try writer.writeAll("(widget: *");
    try writeQualifiedType(writer, .{
        .namespace = binding.widget.namespace,
        .name = binding.widget.short_name,
    });
    try writer.writeAll(", connection: *EventConnection) Error!void {\n");

    if (eventBindingUsesQueryInterface(binding)) {
        try writer.writeAll("    const default_iface: *const ");
        try writeDefaultInterfaceType(writer, binding.widget);
        try writer.writeAll(" = @ptrCast(widget);\n");
        try writer.writeAll("    const target = default_iface.cast(");
        try writeQualifiedType(writer, .{
            .namespace = binding.registration.interface_namespace,
            .name = binding.registration.interface_name,
        });
        try writer.writeAll(") orelse return error.InterfaceCastFailed;\n");
        try writer.writeAll("    defer _ = target.Release();\n");
    } else {
        try writer.writeAll("    const target: *const ");
        try writeQualifiedType(writer, .{
            .namespace = binding.registration.interface_namespace,
            .name = binding.registration.interface_name,
        });
        try writer.writeAll(" = @ptrCast(widget);\n");
    }

    try writer.writeAll("    try reactor_event_runtime.disconnect(\n");
    try writer.writeAll(
        \\        EventRegistrationToken,
        \\        target,
        \\        connection,
    );
    try writer.writeByte('\n');
    try writer.writeAll("        ");
    try writeQualifiedType(writer, .{
        .namespace = binding.registration.interface_namespace,
        .name = binding.registration.interface_name,
    });
    try writer.print(".{s},\n", .{binding.registration.remove_method_name});
    try writer.writeAll("    );\n");
    try writer.writeAll("}\n\n");
}

fn emitErasedEventDisconnect(writer: *std.Io.Writer, binding: EventBinding) !void {
    try writer.writeAll("fn ");
    try writeEventBindingStem(writer, "dispatchDisconnect", binding);
    try writer.writeAll("(widget: *anyopaque, connection: *EventConnection) Error!void {\n");
    try writer.writeAll("    try ");
    try writeEventBindingStem(writer, "disconnect", binding);
    try writer.writeAll("(@ptrCast(@alignCast(widget)), connection);\n");
    try writer.writeAll("}\n\n");
}

fn emitEventEntries(writer: *std.Io.Writer, bindings: []const EventBinding) !void {
    try writer.writeAll("pub const entries = [_]EventConnector{\n");
    for (bindings) |binding| {
        try writer.writeAll("    .{\n");
        try writer.print("        .widget_class = \"{s}\",\n", .{binding.widget.class_name});
        try writer.print("        .widget_name = \"{s}\",\n", .{binding.widget.widget_name});
        try writer.print("        .handle_name = \"{s}\",\n", .{binding.widget.handle_name});
        try writer.print("        .event_name = \"{s}\",\n", .{binding.event.name});
        try writer.print("        .field_name = \"{s}\",\n", .{binding.event.field});
        if (binding.payload) |payload| {
            try writer.print("        .payload = .{s},\n", .{@tagName(payload)});
        } else {
            try writer.writeAll("        .payload = null,\n");
        }
        try writer.writeAll("        .source = ");
        try writeEventSourceLiteral(writer, binding.source);
        try writer.writeAll(",\n");
        try writer.writeAll("        .connect = ");
        try writeEventBindingStem(writer, "dispatchConnect", binding);
        try writer.writeAll(",\n");
        try writer.writeAll("        .disconnect = ");
        try writeEventBindingStem(writer, "dispatchDisconnect", binding);
        try writer.writeAll(",\n");
        try writer.writeAll("    },\n");
    }
    try writer.writeAll("};\n\n");
}

fn emitEventLookup(writer: *std.Io.Writer, bindings: []const EventBinding) !void {
    try writer.writeAll("pub const by_widget_event = std.StaticStringMap(usize).initComptime(.{\n");
    for (bindings, 0..) |binding, i| {
        try writer.print(
            "    .{{ \"{s}#{s}\", {d} }},\n",
            .{ binding.widget.class_name, binding.event.name, i },
        );
    }
    try writer.writeAll(
        \\});
        \\
        \\pub fn find(widget_class: []const u8, event_name: []const u8) ?*const EventConnector {
        \\    var key_buf: [512]u8 = undefined;
        \\    const key = std.fmt.bufPrint(&key_buf, "{s}#{s}", .{ widget_class, event_name }) catch return null;
        \\    const index = by_widget_event.get(key) orelse return null;
        \\    return &entries[index];
        \\}
        \\
        \\pub fn dispatchConnect(
        \\    widget_class: []const u8,
        \\    event_name: []const u8,
        \\    widget: *anyopaque,
        \\    allocator: std.mem.Allocator,
        \\    invoke: InvokeFn,
        \\    user_data: ?*anyopaque,
        \\    connection: *EventConnection,
        \\) Error!bool {
        \\    const entry = find(widget_class, event_name) orelse return false;
        \\    if (connection.token != null) return error.ConnectionStillActive;
        \\    connection.* = try entry.connect(widget, allocator, invoke, user_data);
        \\    return true;
        \\}
        \\
        \\pub fn dispatchDisconnect(widget_class: []const u8, event_name: []const u8, widget: *anyopaque, connection: *EventConnection) Error!bool {
        \\    const entry = find(widget_class, event_name) orelse return false;
        \\    try entry.disconnect(widget, connection);
        \\    return true;
        \\}
    );
    try writer.writeByte('\n');
}

fn emitSetterCall(writer: *std.Io.Writer, binding: Binding, target_name: []const u8) !void {
    switch (binding.setter_kind) {
        .direct => try emitDirectSetterCall(writer, binding, target_name),
        .boxed_reference => try emitBoxedReferenceSetterCall(writer, binding, target_name),
        .text_block => try emitTextBlockSetterCall(writer, binding, target_name),
        .enum_i32 => try emitEnumSetterCall(writer, binding, target_name),
        .optional, .attached => return error.UnsupportedSetterStrategy,
    }
}

fn emitDirectSetterCall(writer: *std.Io.Writer, binding: Binding, target_name: []const u8) !void {
    try writer.writeAll("    try win_core.hresult.ok(");
    try writer.writeAll(target_name);
    try writer.writeByte('.');

    if (binding.value_kind == .string) {
        switch (binding.setter.param_ty) {
            .string => {},
            else => return error.UnsupportedSetterStrategy,
        }
        try writer.print("{s}FromUtf16(value)", .{binding.setter.method_name});
        try writer.writeAll(");\n");
        return;
    }

    try writer.print("{s}(", .{binding.setter.method_name});
    switch (binding.value_kind) {
        .bool => {
            switch (binding.setter.param_ty) {
                .bool => {},
                else => return error.UnsupportedSetterStrategy,
            }
            try writer.writeAll("win_core.boolToWin32(value)");
        },
        .f64, .i32, .u32, .color, .date_time, .time_span => {
            try writer.writeAll("value");
        },
        .element => {
            switch (binding.setter.param_ty) {
                .object => try writer.writeAll("@as(?*const anyopaque, @ptrCast(value))"),
                else => try writer.writeAll("@ptrCast(value)"),
            }
        },
        .string, .enum_i32 => unreachable,
    }
    try writer.writeAll("));\n");
}

fn emitEnumSetterCall(writer: *std.Io.Writer, binding: Binding, target_name: []const u8) !void {
    const enum_type = try resolveEnumType(binding);

    try writer.writeAll("    try win_core.hresult.ok(");
    try writer.writeAll(target_name);
    try writer.print(".{s}(@as(", .{binding.setter.method_name});
    try writeQualifiedType(writer, enum_type);
    try writer.writeAll(", @enumFromInt(value))));\n");
}

fn emitAttachedSetterCall(writer: *std.Io.Writer, binding: Binding) !void {
    const owner_namespace = binding.setter.owner_namespace orelse return error.UnsupportedSetterStrategy;
    const owner_name = binding.setter.owner_name orelse return error.UnsupportedSetterStrategy;

    try writer.writeAll(
        \\    const widget_object = win_core.IInspectable.from(@ptrCast(widget));
        \\    const target = try widget_object.cast(@"Microsoft.UI.Xaml".IUIElement_Vtbl, &@"Microsoft.UI.Xaml".IUIElement.IID);
        \\    defer target.deinit();
        \\    const target_iface: *@"Microsoft.UI.Xaml".UIElement = @ptrCast(@alignCast(target.ptr));
    );
    try writer.writeByte('\n');
    try writer.writeAll("    var statics = try ");
    try writer.print("@\"{s}\".{s}.statics();\n", .{ owner_namespace, owner_name });
    try writer.writeAll("    defer statics.deinit();\n");
    try writer.writeAll("    const owner: *const ");
    try writeQualifiedType(writer, .{
        .namespace = binding.setter.interface_namespace,
        .name = binding.setter.interface_name,
    });
    try writer.writeAll(" = @ptrCast(@alignCast(statics.ptr));\n");
    try writer.writeAll("    try win_core.hresult.ok(owner.");
    try writer.writeAll(binding.setter.method_name);
    try writer.writeAll("(target_iface, ");

    switch (binding.value_kind) {
        .bool => {
            switch (binding.setter.param_ty) {
                .bool => try writer.writeAll("win_core.boolToWin32(value)"),
                else => return error.UnsupportedSetterStrategy,
            }
        },
        .f64, .i32, .u32, .color, .date_time, .time_span => try writer.writeAll("value"),
        .enum_i32 => {
            const enum_type = try resolveEnumType(binding);
            try writer.writeAll("@as(");
            try writeQualifiedType(writer, enum_type);
            try writer.writeAll(", @enumFromInt(value))");
        },
        .string, .element => return error.UnsupportedSetterStrategy,
    }

    try writer.writeAll("));\n");
}

fn emitTextBlockSetterCall(writer: *std.Io.Writer, binding: Binding, target_name: []const u8) !void {
    if (binding.value_kind != .string) return error.UnsupportedSetterStrategy;

    try writer.writeAll(
        \\    const text_block = try @"Microsoft.UI.Xaml.Controls".TextBlock.activate();
        \\    const text_block_iface: *const @"Microsoft.UI.Xaml.Controls".ITextBlock = @ptrCast(text_block);
        \\    defer _ = text_block_iface.Release();
        \\    try win_core.hresult.ok(text_block_iface.put_TextFromUtf16(value));
    );
    try writer.writeByte('\n');
    try writer.writeAll("    try win_core.hresult.ok(");
    try writer.writeAll(target_name);
    try writer.writeByte('.');
    try writer.print("{s}(", .{binding.setter.method_name});
    switch (binding.setter.param_ty) {
        .object => try writer.writeAll("@as(?*const anyopaque, @ptrCast(text_block))"),
        .class_name => try writer.writeAll("@ptrCast(text_block)"),
        else => return error.UnsupportedSetterStrategy,
    }
    try writer.writeAll("));\n");
}

fn emitBoxedReferenceSetterCall(writer: *std.Io.Writer, binding: Binding, target_name: []const u8) !void {
    switch (binding.value_kind) {
        .bool, .f64, .i32, .u32, .enum_i32 => {},
        else => return error.UnsupportedBoxedReferenceValue,
    }

    try writer.writeAll(
        \\    var boxed = try win_reference.box(value);
        \\    defer boxed.deinit();
    );
    try writer.writeByte('\n');
    try writer.writeAll("    try win_core.hresult.ok(");
    try writer.writeAll(target_name);
    try writer.writeByte('.');
    try writer.print("{s}(", .{binding.setter.method_name});
    switch (binding.setter.param_ty) {
        .object => try writer.writeAll("@as(?*const anyopaque, boxed.asAnyOpaque())"),
        else => try writer.writeAll("@ptrCast(boxed.raw())"),
    }
    try writer.writeAll("));\n");
}

fn collectEventImports(
    gpa: std.mem.Allocator,
    imports: *std.StringHashMapUnmanaged(void),
    binding: EventBinding,
) !void {
    try imports.put(gpa, "Windows.Foundation", {});
    try imports.put(gpa, binding.widget.namespace, {});
    try imports.put(gpa, binding.registration.interface_namespace, {});
}

fn resolveEventBinding(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    widget: *const Widget,
    event: *const Event,
) !EventBinding {
    return .{
        .widget = widget,
        .event = event,
        .payload = event.payload,
        .source = event.source,
        .registration = try resolveInstanceEvent(
            sig_alloc,
            gpa,
            file,
            type_index,
            widget.class_name,
            event.winrt_name,
            event.delegate,
        ),
    };
}

fn resolveInstanceEvent(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    class_name: []const u8,
    event_name: []const u8,
    delegate_override: ?[]const u8,
) anyerror!ResolvedEvent {
    const class_row = findTypeRowByFullName(type_index, file, class_name) orelse
        return error.WidgetTypeNotFound;

    var visited: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer visited.deinit(gpa);

    return try findEventInClassHierarchy(
        sig_alloc,
        gpa,
        file,
        type_index,
        &visited,
        class_row,
        event_name,
        delegate_override,
    ) orelse error.EventBindingNotFound;
}

fn findEventInClassHierarchy(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    class_row: u32,
    event_name: []const u8,
    delegate_override: ?[]const u8,
) anyerror!?ResolvedEvent {
    if (try findEventInDirectInterfaces(
        sig_alloc,
        gpa,
        file,
        type_index,
        visited,
        class_row,
        event_name,
        delegate_override,
    )) |event| {
        return event;
    }

    const base_type = try winmd.typeDefExtends(file, class_row);
    const base_name = base_type orelse return null;
    const base_row = findTypeRowByTypeName(type_index, file, base_name) orelse return null;
    return try findEventInClassHierarchy(
        sig_alloc,
        gpa,
        file,
        type_index,
        visited,
        base_row,
        event_name,
        delegate_override,
    );
}

fn findEventInDirectInterfaces(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    type_row: u32,
    event_name: []const u8,
    delegate_override: ?[]const u8,
) anyerror!?ResolvedEvent {
    const impls = file.equalRange(.interface_impl, 0, type_row + 1);
    var i = impls.start;
    while (i < impls.end) : (i += 1) {
        const token = file.cell(.interface_impl, i, 1);
        const interface_name = winmd.resolveTypeDefOrRefName(file, token) catch continue;
        const interface_row = findTypeRowByTypeName(type_index, file, interface_name) orelse continue;
        if (try findEventInInterfaceHierarchy(
            sig_alloc,
            gpa,
            file,
            type_index,
            visited,
            interface_row,
            event_name,
            delegate_override,
        )) |event| {
            return event;
        }
    }
    return null;
}

fn findEventInInterfaceHierarchy(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    interface_row: u32,
    event_name: []const u8,
    delegate_override: ?[]const u8,
) anyerror!?ResolvedEvent {
    if (visited.contains(interface_row)) return null;
    try visited.put(gpa, interface_row, {});

    if (try findEventOnInterface(
        sig_alloc,
        file,
        type_index,
        interface_row,
        event_name,
        delegate_override,
    )) |event| {
        return event;
    }

    return try findEventInDirectInterfaces(
        sig_alloc,
        gpa,
        file,
        type_index,
        visited,
        interface_row,
        event_name,
        delegate_override,
    );
}

fn findEventOnInterface(
    sig_alloc: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    interface_row: u32,
    event_name: []const u8,
    delegate_override: ?[]const u8,
) anyerror!?ResolvedEvent {
    var add_name_buf: [256]u8 = undefined;
    const add_name = try std.fmt.bufPrint(&add_name_buf, "add_{s}", .{event_name});
    const add_row = findMethodRow(file, interface_row, add_name) orelse return null;

    var remove_name_buf: [256]u8 = undefined;
    const remove_name = try std.fmt.bufPrint(&remove_name_buf, "remove_{s}", .{event_name});
    const remove_row = findMethodRow(file, interface_row, remove_name) orelse return null;

    const add_sig = try winmd.readMethodSignature(sig_alloc, file, file.blob(.method_def, add_row, 4));
    if (!isEventAddSignature(add_sig)) return null;

    const remove_sig = try winmd.readMethodSignature(sig_alloc, file, file.blob(.method_def, remove_row, 4));
    if (!isEventRemoveSignature(remove_sig)) return null;

    return .{
        .interface_namespace = file.str(.type_def, interface_row, 2),
        .interface_name = file.str(.type_def, interface_row, 1),
        .add_method_name = file.str(.method_def, add_row, 3),
        .remove_method_name = file.str(.method_def, remove_row, 3),
        .delegate_iid = try resolveDelegateGuid(
            sig_alloc,
            file,
            type_index,
            add_sig.params[0],
            delegate_override,
        ),
    };
}

fn resolveDelegateGuid(
    sig_alloc: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    delegate_ty: winmd.Ty,
    delegate_override: ?[]const u8,
) !GuidLiteral {
    if (delegate_override) |full_name| {
        const row = findTypeRowByFullName(type_index, file, full_name) orelse
            return error.EventDelegateTypeNotFound;
        return readTypeDefGuid(sig_alloc, file, row) orelse error.EventDelegateGuidNotFound;
    }

    const delegate_name = switch (delegate_ty) {
        .class_name => |tn| tn,
        else => return error.UnsupportedEventDelegateType,
    };
    if (delegate_name.generics.len != 0) return error.UnsupportedGenericEventDelegate;

    const row = findTypeRowByTypeName(type_index, file, delegate_name) orelse
        return error.EventDelegateTypeNotFound;
    return readTypeDefGuid(sig_alloc, file, row) orelse error.EventDelegateGuidNotFound;
}

fn isEventRegistrationToken(ty: winmd.Ty) bool {
    return switch (ty) {
        .value_name => |tn| std.mem.eql(u8, tn.namespace, "Windows.Foundation") and
            std.mem.eql(u8, tn.name, "EventRegistrationToken"),
        else => false,
    };
}

fn isEventAddSignature(sig: winmd.MethodSignature) bool {
    if (sig.params.len != 1) return false;
    if (!isEventRegistrationToken(sig.return_type)) return false;
    return switch (sig.params[0]) {
        .class_name => true,
        else => false,
    };
}

fn isEventRemoveSignature(sig: winmd.MethodSignature) bool {
    if (sig.params.len != 1) return false;
    if (sig.return_type != .void) return false;
    return isEventRegistrationToken(sig.params[0]);
}

fn readTypeDefGuid(
    arena: std.mem.Allocator,
    file: *const winmd.File,
    type_def_row: u32,
) ?GuidLiteral {
    const attr_row = winmd.findAttribute(file, .type_def, type_def_row, "GuidAttribute") orelse return null;
    const args = winmd.readAttributeArgs(arena, file, attr_row) catch return null;
    if (args.len != 11) return null;

    const data1 = switch (args[0].value) {
        .u32_val => |value| value,
        else => return null,
    };
    const data2 = switch (args[1].value) {
        .u16_val => |value| value,
        else => return null,
    };
    const data3 = switch (args[2].value) {
        .u16_val => |value| value,
        else => return null,
    };

    var data4: [8]u8 = undefined;
    for (0..8) |i| {
        data4[i] = switch (args[3 + i].value) {
            .u8_val => |value| value,
            else => return null,
        };
    }

    return .{
        .data1 = data1,
        .data2 = data2,
        .data3 = data3,
        .data4 = data4,
    };
}

fn eventBindingUsesQueryInterface(binding: EventBinding) bool {
    return !std.mem.eql(u8, binding.registration.interface_namespace, binding.widget.namespace) or
        binding.registration.interface_name.len != binding.widget.short_name.len + 1 or
        binding.registration.interface_name[0] != 'I' or
        !std.mem.eql(u8, binding.registration.interface_name[1..], binding.widget.short_name);
}

fn writeEventBindingStem(writer: *std.Io.Writer, prefix: []const u8, binding: EventBinding) !void {
    try writer.writeAll(prefix);
    for (binding.widget.class_name) |ch| {
        if (ch == '.') continue;
        try writer.writeByte(ch);
    }
    try writer.writeAll(binding.event.name);
}

fn writeEventSourceLiteral(writer: *std.Io.Writer, source: EventSource) !void {
    switch (source) {
        .none => try writer.writeAll(".none"),
        .sender_property => |name| try writer.print(".{{ .sender_property = \"{s}\" }}", .{name}),
        .args_property => |name| try writer.print(".{{ .args_property = \"{s}\" }}", .{name}),
        .paired_bool => |name| try writer.print(".{{ .paired_bool = \"{s}\" }}", .{name}),
    }
}

fn writeGuidLiteral(writer: *std.Io.Writer, guid: GuidLiteral) !void {
    try writer.print(
        ".{{ .data1 = 0x{x:0>8}, .data2 = 0x{x:0>4}, .data3 = 0x{x:0>4}, .data4 = .{{ 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2} }} }}",
        .{
            guid.data1,
            guid.data2,
            guid.data3,
            guid.data4[0],
            guid.data4[1],
            guid.data4[2],
            guid.data4[3],
            guid.data4[4],
            guid.data4[5],
            guid.data4[6],
            guid.data4[7],
        },
    );
}

fn resolveBinding(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    widget: *const Widget,
    prop: *const Property,
) !Binding {
    const setter = if (prop.attached) |attached|
        try resolveAttachedSetter(sig_alloc, file, type_index, attached.owner, attached.setter)
    else
        try resolveInstanceSetter(sig_alloc, gpa, file, type_index, widget.class_name, prop.winrt_name);
    const value_kind = try resolveValueKind(prop, setter.param_ty);
    const setter_kind = resolveSetterKind(prop, value_kind);

    switch (setter_kind) {
        .optional => return error.UnsupportedSetterStrategy,
        .attached => {},
        .text_block => if (value_kind != .string) return error.UnsupportedSetterStrategy,
        .boxed_reference => switch (value_kind) {
            .bool, .f64, .i32, .u32, .enum_i32 => {},
            else => return error.UnsupportedBoxedReferenceValue,
        },
        .direct, .enum_i32 => {},
    }

    return .{
        .widget = widget,
        .prop = prop,
        .value_kind = value_kind,
        .setter_kind = setter_kind,
        .setter = setter,
    };
}

fn collectImports(
    gpa: std.mem.Allocator,
    imports: *std.StringHashMapUnmanaged(void),
    binding: Binding,
) !void {
    try imports.put(gpa, binding.widget.namespace, {});
    try imports.put(gpa, binding.setter.interface_namespace, {});

    switch (binding.value_kind) {
        .color => try imports.put(gpa, "Windows.UI", {}),
        .date_time, .time_span => try imports.put(gpa, "Windows.Foundation", {}),
        .element => try imports.put(gpa, "Microsoft.UI.Xaml", {}),
        else => {},
    }

    if (binding.setter_kind == .attached) {
        try imports.put(gpa, "Microsoft.UI.Xaml", {});
        if (binding.setter.owner_namespace) |owner_namespace| {
            try imports.put(gpa, owner_namespace, {});
        }
    }
    if (binding.setter_kind == .text_block) {
        try imports.put(gpa, "Microsoft.UI.Xaml.Controls", {});
    }
    if (binding.setter_kind == .enum_i32) {
        const enum_type = try resolveEnumType(binding);
        try imports.put(gpa, enum_type.namespace, {});
    }
}

fn appendValueKind(
    gpa: std.mem.Allocator,
    used_kinds: *std.ArrayList(ValueKind),
    kind: ValueKind,
) !void {
    for (used_kinds.items) |existing| {
        if (existing == kind) return;
    }
    try used_kinds.append(gpa, kind);
}

fn resolveInstanceSetter(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    class_name: []const u8,
    prop_name: []const u8,
) anyerror!ResolvedSetter {
    const class_row = findTypeRowByFullName(type_index, file, class_name) orelse
        return error.WidgetTypeNotFound;

    var method_name_buf: [256]u8 = undefined;
    const method_name = try std.fmt.bufPrint(&method_name_buf, "put_{s}", .{prop_name});

    var visited: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer visited.deinit(gpa);

    return try findSetterInClassHierarchy(
        sig_alloc,
        gpa,
        file,
        type_index,
        &visited,
        class_row,
        method_name,
    ) orelse error.PropertySetterNotFound;
}

fn resolveAttachedSetter(
    sig_alloc: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    owner_class_name: []const u8,
    setter_name: []const u8,
) anyerror!ResolvedSetter {
    const owner = try splitQualifiedName(owner_class_name);
    const statics_interface_name = try std.fmt.allocPrint(sig_alloc, "I{s}Statics", .{trimTick(owner.name)});
    const statics_full_name = try std.fmt.allocPrint(
        sig_alloc,
        "{s}.{s}",
        .{ owner.namespace, statics_interface_name },
    );
    const interface_row = findTypeRowByFullName(type_index, file, statics_full_name) orelse
        return error.WidgetTypeNotFound;
    const method_row = findMethodRow(file, interface_row, setter_name) orelse
        return error.PropertySetterNotFound;
    const sig = try winmd.readMethodSignature(sig_alloc, file, file.blob(.method_def, method_row, 4));
    if (sig.params.len != 2) return error.UnsupportedPropertySignature;

    switch (sig.params[0]) {
        .class_name => |type_name| {
            if (!std.mem.eql(u8, type_name.namespace, "Microsoft.UI.Xaml") or
                !std.mem.eql(u8, trimTick(type_name.name), "UIElement"))
            {
                return error.UnsupportedSetterStrategy;
            }
        },
        .object => {},
        else => return error.UnsupportedSetterStrategy,
    }

    return .{
        .interface_namespace = owner.namespace,
        .interface_name = file.str(.type_def, interface_row, 1),
        .method_name = file.str(.method_def, method_row, 3),
        .param_ty = sig.params[1],
        .owner_namespace = owner.namespace,
        .owner_name = owner.name,
    };
}

fn findSetterInClassHierarchy(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    class_row: u32,
    method_name: []const u8,
) anyerror!?ResolvedSetter {
    if (try findSetterInDirectInterfaces(sig_alloc, gpa, file, type_index, visited, class_row, method_name)) |setter| {
        return setter;
    }

    const base_type = try winmd.typeDefExtends(file, class_row);
    const base_name = base_type orelse return null;
    const base_row = findTypeRowByTypeName(type_index, file, base_name) orelse return null;
    return try findSetterInClassHierarchy(sig_alloc, gpa, file, type_index, visited, base_row, method_name);
}

fn findSetterInDirectInterfaces(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    type_row: u32,
    method_name: []const u8,
) anyerror!?ResolvedSetter {
    const impls = file.equalRange(.interface_impl, 0, type_row + 1);
    var i = impls.start;
    while (i < impls.end) : (i += 1) {
        const token = file.cell(.interface_impl, i, 1);
        const interface_name = winmd.resolveTypeDefOrRefName(file, token) catch continue;
        const interface_row = findTypeRowByTypeName(type_index, file, interface_name) orelse continue;
        if (try findSetterInInterfaceHierarchy(sig_alloc, gpa, file, type_index, visited, interface_row, method_name)) |setter| {
            return setter;
        }
    }
    return null;
}

fn findSetterInInterfaceHierarchy(
    sig_alloc: std.mem.Allocator,
    gpa: std.mem.Allocator,
    file: *const winmd.File,
    type_index: *const winmd.TypeIndex,
    visited: *std.AutoHashMapUnmanaged(u32, void),
    interface_row: u32,
    method_name: []const u8,
) anyerror!?ResolvedSetter {
    if (visited.contains(interface_row)) return null;
    try visited.put(gpa, interface_row, {});

    if (findMethodRow(file, interface_row, method_name)) |method_row| {
        const sig = try winmd.readMethodSignature(sig_alloc, file, file.blob(.method_def, method_row, 4));
        if (sig.params.len != 1) return error.UnsupportedPropertySignature;

        return .{
            .interface_namespace = file.str(.type_def, interface_row, 2),
            .interface_name = file.str(.type_def, interface_row, 1),
            .method_name = file.str(.method_def, method_row, 3),
            .param_ty = sig.params[0],
        };
    }

    return try findSetterInDirectInterfaces(
        sig_alloc,
        gpa,
        file,
        type_index,
        visited,
        interface_row,
        method_name,
    );
}

fn resolveValueKind(prop: *const Property, param_ty: winmd.Ty) !ValueKind {
    if (prop.value) |value_kind| return value_kind;

    return switch (param_ty) {
        .string => .string,
        .bool => .bool,
        .f64 => .f64,
        .i32 => .i32,
        .u32 => .u32,
        .class_name => |tn| if (std.mem.eql(u8, tn.namespace, "Microsoft.UI.Xaml") and std.mem.eql(u8, tn.name, "UIElement"))
            .element
        else
            error.UnsupportedValueKindInference,
        else => error.UnsupportedValueKindInference,
    };
}

fn resolveSetterKind(prop: *const Property, value_kind: ValueKind) SetterKind {
    if (prop.attached != null) return .attached;
    return prop.setter orelse switch (value_kind) {
        .enum_i32 => .enum_i32,
        else => .direct,
    };
}

fn resolveEnumType(binding: Binding) !QualifiedName {
    if (binding.prop.winrt_type) |full_name| {
        return splitQualifiedName(full_name);
    }

    return switch (binding.setter.param_ty) {
        .value_name => |tn| .{
            .namespace = tn.namespace,
            .name = tn.name,
        },
        else => error.UnsupportedEnumType,
    };
}

fn bindingUsesQueryInterface(binding: Binding) bool {
    return !std.mem.eql(u8, binding.setter.interface_namespace, binding.widget.namespace) or
        binding.setter.interface_name.len != binding.widget.short_name.len + 1 or
        binding.setter.interface_name[0] != 'I' or
        !std.mem.eql(u8, binding.setter.interface_name[1..], binding.widget.short_name);
}

fn findTypeRowByFullName(
    type_index: *const winmd.TypeIndex,
    file: *const winmd.File,
    full_name: []const u8,
) ?u32 {
    const qualified = splitQualifiedName(full_name) catch return null;
    return findTypeRow(type_index, file, qualified);
}

fn findTypeRowByTypeName(
    type_index: *const winmd.TypeIndex,
    file: *const winmd.File,
    type_name: winmd.TypeName,
) ?u32 {
    return findTypeRow(type_index, file, .{
        .namespace = type_name.namespace,
        .name = type_name.name,
    });
}

fn findTypeRow(
    type_index: *const winmd.TypeIndex,
    file: *const winmd.File,
    qualified: QualifiedName,
) ?u32 {
    const candidates = type_index.get(qualified.namespace, trimTick(qualified.name));
    for (candidates) |candidate| {
        if (std.mem.eql(u8, file.str(.type_def, candidate, 1), qualified.name)) {
            return candidate;
        }
    }

    if (std.mem.indexOfScalar(u8, qualified.name, '`') == null) {
        for (candidates) |candidate| {
            if (std.mem.eql(u8, trimTick(file.str(.type_def, candidate, 1)), qualified.name)) {
                return candidate;
            }
        }
    }

    return null;
}

fn findMethodRow(file: *const winmd.File, type_row: u32, method_name: []const u8) ?u32 {
    const methods = file.list(.type_def, type_row, 5, .method_def);
    var method_row = methods.start;
    while (method_row < methods.end) : (method_row += 1) {
        if (std.mem.eql(u8, file.str(.method_def, method_row, 3), method_name)) {
            return method_row;
        }
    }
    return null;
}

fn splitQualifiedName(full_name: []const u8) !QualifiedName {
    const split_index = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse
        return error.InvalidQualifiedName;

    return .{
        .namespace = full_name[0..split_index],
        .name = full_name[split_index + 1 ..],
    };
}

fn trimTick(name: []const u8) []const u8 {
    const tick = std.mem.indexOfScalar(u8, name, '`') orelse return name;
    return name[0..tick];
}

fn writeBindingStem(writer: *std.Io.Writer, prefix: []const u8, binding: Binding) !void {
    try writer.writeAll(prefix);
    for (binding.widget.class_name) |ch| {
        if (ch == '.') continue;
        try writer.writeByte(ch);
    }
    try writer.writeAll(binding.prop.name);
}

fn writeQualifiedType(writer: *std.Io.Writer, qualified: QualifiedName) !void {
    try writer.print("@\"{s}\".{s}", .{ qualified.namespace, qualified.name });
}

fn writeDefaultInterfaceType(writer: *std.Io.Writer, widget: *const Widget) !void {
    try writer.print("@\"{s}\".I{s}", .{ widget.namespace, widget.short_name });
}

fn writeValueType(writer: *std.Io.Writer, kind: ValueKind) !void {
    switch (kind) {
        .string => try writer.writeAll("[]const u16"),
        .bool => try writer.writeAll("bool"),
        .f64 => try writer.writeAll("f64"),
        .i32 => try writer.writeAll("i32"),
        .u32 => try writer.writeAll("u32"),
        .enum_i32 => try writer.writeAll("i32"),
        .color => try writer.writeAll("@\"Windows.UI\".Color"),
        .date_time => try writer.writeAll("@\"Windows.Foundation\".DateTime"),
        .time_span => try writer.writeAll("@\"Windows.Foundation\".TimeSpan"),
        .element => try writer.writeAll("*@\"Microsoft.UI.Xaml\".UIElement"),
    }
}

test "emitSetPropFromManifest covers the seeded widget props" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var io_instance: std.Io.Threaded = .init(gpa, .{});
    defer io_instance.deinit();
    const io = io_instance.io();

    const repo_root = std.Io.Dir.cwd();
    var mapped = winmd.mmapAndParse(io, repo_root, "vendor/winmd/Microsoft.UI.Xaml.winmd") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer mapped.deinit(io);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    try emitSetPropFromManifest(&out.writer, gpa, &mapped.file);

    const source = out.written();
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlWindowTitle(widget: *@\"Microsoft.UI.Xaml\".Window, value: []const u16) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_TitleFromUtf16(value)") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsTextBlockText(widget: *@\"Microsoft.UI.Xaml.Controls\".TextBlock, value: []const u16) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_TextFromUtf16(value)") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsStackPanelOrientation(widget: *@\"Microsoft.UI.Xaml.Controls\".StackPanel, value: i32) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_Orientation(@as(@\"Microsoft.UI.Xaml.Controls\".Orientation, @enumFromInt(value)))") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsStackPanelSpacing(widget: *@\"Microsoft.UI.Xaml.Controls\".StackPanel, value: f64) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_Spacing(value)") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsButtonContent(widget: *@\"Microsoft.UI.Xaml.Controls\".Button, value: []const u16) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "default_iface.cast(@\"Microsoft.UI.Xaml.Controls\".IContentControl) orelse return error.InterfaceCastFailed;") != null);
    try std.testing.expect(std.mem.find(u8, source, "text_block_iface.put_TextFromUtf16(value)") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_Content(@as(?*const anyopaque, @ptrCast(text_block)))") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsBorderChild(widget: *@\"Microsoft.UI.Xaml.Controls\".Border, value: *@\"Microsoft.UI.Xaml\".UIElement) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "target.put_Child(@ptrCast(value))") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn setMicrosoftUIXamlControlsScrollViewerContent(widget: *@\"Microsoft.UI.Xaml.Controls\".ScrollViewer, value: *@\"Microsoft.UI.Xaml\".UIElement) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "default_iface.cast(@\"Microsoft.UI.Xaml.Controls\".IContentControl) orelse return error.InterfaceCastFailed;") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub const by_widget_prop = std.StaticStringMap(usize).initComptime(.{") != null);
}

test "emitSetPropFromManifest is deterministic for the production manifest" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var io_instance: std.Io.Threaded = .init(gpa, .{});
    defer io_instance.deinit();
    const io = io_instance.io();

    const repo_root = std.Io.Dir.cwd();
    var mapped = winmd.mmapAndParse(io, repo_root, "vendor/winmd/Microsoft.UI.Xaml.winmd") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer mapped.deinit(io);

    var out_a: std.Io.Writer.Allocating = .init(gpa);
    defer out_a.deinit();
    try emitSetPropFromManifest(&out_a.writer, gpa, &mapped.file);

    var out_b: std.Io.Writer.Allocating = .init(gpa);
    defer out_b.deinit();
    try emitSetPropFromManifest(&out_b.writer, gpa, &mapped.file);

    try std.testing.expectEqualStrings(out_a.written(), out_b.written());
}

test "emitAttachEventFromManifest covers the seeded widget events" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var io_instance: std.Io.Threaded = .init(gpa, .{});
    defer io_instance.deinit();
    const io = io_instance.io();

    const repo_root = std.Io.Dir.cwd();
    var mapped = winmd.mmapAndParse(io, repo_root, "vendor/winmd/Microsoft.UI.Xaml.winmd") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer mapped.deinit(io);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    try emitAttachEventFromManifest(&out.writer, gpa, &mapped.file);

    const source = out.written();
    try std.testing.expect(std.mem.find(u8, source, "pub fn connectMicrosoftUIXamlControlsButtonClick(widget: *@\"Microsoft.UI.Xaml.Controls\".Button, allocator: std.mem.Allocator, invoke: InvokeFn, user_data: ?*anyopaque) Error!EventConnection {") != null);
    try std.testing.expect(std.mem.find(u8, source, "default_iface.cast(@\"Microsoft.UI.Xaml.Controls.Primitives\".IButtonBase) orelse return error.InterfaceCastFailed;") != null);
    try std.testing.expect(std.mem.find(u8, source, "@\"Microsoft.UI.Xaml.Controls.Primitives\".IButtonBase.add_Click") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn disconnectMicrosoftUIXamlControlsButtonClick(widget: *@\"Microsoft.UI.Xaml.Controls\".Button, connection: *EventConnection) Error!void {") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn connectMicrosoftUIXamlControlsButtonPointerPressed(widget: *@\"Microsoft.UI.Xaml.Controls\".Button, allocator: std.mem.Allocator, invoke: InvokeFn, user_data: ?*anyopaque) Error!EventConnection {") != null);
    try std.testing.expect(std.mem.find(u8, source, "default_iface.cast(@\"Microsoft.UI.Xaml\".IUIElement) orelse return error.InterfaceCastFailed;") != null);
    try std.testing.expect(std.mem.find(u8, source, "@\"Microsoft.UI.Xaml\".IUIElement.add_PointerPressed") != null);
    try std.testing.expect(std.mem.find(u8, source, "pub fn connectMicrosoftUIXamlControlsTextBoxTextChanged(widget: *@\"Microsoft.UI.Xaml.Controls\".TextBox, allocator: std.mem.Allocator, invoke: InvokeFn, user_data: ?*anyopaque) Error!EventConnection {") != null);
    try std.testing.expect(std.mem.find(u8, source, "@\"Microsoft.UI.Xaml.Controls\".ITextBox.add_TextChanged") != null);
    try std.testing.expect(std.mem.find(u8, source, ".{ \"Microsoft.UI.Xaml.Controls.Button#Click\",") != null);
    try std.testing.expect(std.mem.find(u8, source, ".{ \"Microsoft.UI.Xaml.Controls.Button#PointerPressed\",") != null);
    try std.testing.expect(std.mem.find(u8, source, ".{ \"Microsoft.UI.Xaml.Controls.TextBox#TextChanged\",") != null);
    try std.testing.expect(std.mem.find(u8, source, ".source = .{ .sender_property = \"Text\" },") != null);
    try std.testing.expect(std.mem.find(u8, source, ".payload = .pointer,") != null);
    try std.testing.expect(std.mem.find(u8, source, "if (connection.token != null) return error.ConnectionStillActive;") != null);
}

test "emitAttachEventFromManifest is deterministic for the production manifest" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var io_instance: std.Io.Threaded = .init(gpa, .{});
    defer io_instance.deinit();
    const io = io_instance.io();

    const repo_root = std.Io.Dir.cwd();
    var mapped = winmd.mmapAndParse(io, repo_root, "vendor/winmd/Microsoft.UI.Xaml.winmd") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer mapped.deinit(io);

    var out_a: std.Io.Writer.Allocating = .init(gpa);
    defer out_a.deinit();
    try emitAttachEventFromManifest(&out_a.writer, gpa, &mapped.file);

    var out_b: std.Io.Writer.Allocating = .init(gpa);
    defer out_b.deinit();
    try emitAttachEventFromManifest(&out_b.writer, gpa, &mapped.file);

    try std.testing.expectEqualStrings(out_a.written(), out_b.written());
}
