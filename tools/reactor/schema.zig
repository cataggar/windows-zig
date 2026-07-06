//! Typed schema for the hand-authored WinUI3 reactor widget manifest.

/// Optional widget-level overrides.
pub const WidgetMetaInit = struct {
    /// Public reactor widget/builder name. Defaults to the WinRT short type name.
    widget_name: ?[]const u8 = null,
    /// Handle enum / runtime class name. Defaults to the WinRT short type name.
    handle_name: ?[]const u8 = null,
};

/// Reactor-facing value kinds used by generated property setters.
pub const ValueKind = enum {
    string,
    object,
    bool,
    f64,
    i32,
    u32,
    enum_i32,
    color,
    date_time,
    time_span,
    element,
};

/// Setter strategies for property glue.
pub const SetterKind = enum {
    direct,
    optional,
    boxed_reference,
    text_block,
    enum_i32,
    attached,
};

/// Static owner + setter method for an attached property.
pub const AttachedPropertyInit = struct {
    owner: []const u8,
    setter: []const u8,
};

/// Hand-authored property declaration.
pub const PropInit = struct {
    /// WinRT metadata property name. Defaults to the manifest key.
    winrt_name: ?[]const u8 = null,
    /// Reactor widget field name. Defaults to snake_case(manifest key).
    field: ?[]const u8 = null,
    /// Reactor-facing value kind. Omit to let future codegen infer from metadata.
    value: ?ValueKind = null,
    /// Setter strategy override. Omit to let future codegen infer from metadata.
    setter: ?SetterKind = null,
    /// Optional fully qualified WinRT type (for enum/object overrides).
    winrt_type: ?[]const u8 = null,
    /// Attached-property owner metadata when this is not an instance `put_*` setter.
    attached: ?AttachedPropertyInit = null,
    /// Skip generated setter glue; a hand-written backend path will own it.
    manual: bool = false,
};

/// Reactor-facing event payload kinds used by generated event glue.
pub const EventPayload = enum {
    unit,
    bool,
    string,
    f64,
    i32,
    pointer,
    color,
    date_time,
    time_span,
};

/// Where an event payload comes from.
pub const EventSource = union(enum) {
    none,
    sender_property: []const u8,
    args_property: []const u8,
    paired_bool: []const u8,
};

/// Hand-authored event declaration.
pub const EventInit = struct {
    /// WinRT metadata event name. Defaults to the manifest key.
    winrt_name: ?[]const u8 = null,
    /// Reactor widget handler field name. Defaults to `on_` + snake_case(key).
    field: ?[]const u8 = null,
    /// Optional fully qualified delegate type override.
    delegate: ?[]const u8 = null,
    /// Reactor-facing payload kind. Omit to let future codegen infer from metadata.
    payload: ?EventPayload = null,
    /// Payload extraction strategy. Defaults to `.none`.
    source: ?EventSource = null,
    /// Skip generated attach/detach glue; a hand-written backend path will own it.
    manual: bool = false,
};

/// Normalized widget declaration consumed by future codegen.
pub const Widget = struct {
    class_name: []const u8,
    namespace: []const u8,
    short_name: []const u8,
    widget_name: []const u8,
    handle_name: []const u8,
    props: []const Property,
    events: []const Event,
};

/// Normalized property declaration consumed by future codegen.
pub const Property = struct {
    name: []const u8,
    winrt_name: []const u8,
    field: []const u8,
    value: ?ValueKind = null,
    setter: ?SetterKind = null,
    winrt_type: ?[]const u8 = null,
    attached: ?AttachedPropertyInit = null,
    manual: bool = false,
};

/// Normalized event declaration consumed by future codegen.
pub const Event = struct {
    name: []const u8,
    winrt_name: []const u8,
    field: []const u8,
    delegate: ?[]const u8 = null,
    payload: ?EventPayload = null,
    source: EventSource = .none,
    manual: bool = false,
};
