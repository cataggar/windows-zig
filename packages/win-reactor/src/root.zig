//! `win-reactor` — backend-agnostic hook-slot engine for the future
//! Reactor render tree and reconciler.
//!
//! This package intentionally stays pure Zig + `std`: no WinRT, WinUI3,
//! COM, or `win-core` dependency. The core abstraction is a per-node
//! `RenderCx` whose render-order hook slots persist state, memo values,
//! deferred effects, async state, and context subscriptions across
//! re-renders.

const context = @import("context.zig");
const element = @import("element.zig");
const recording_backend = @import("recording_backend.zig");
const backend = @import("backend.zig");
const reconciler = @import("reconciler.zig");
const render_cx = @import("render_cx.zig");

pub const ContextId = context.ContextId;
pub const Context = context.Context;
pub const ContextScope = context.ContextScope;
pub const ContextStack = context.ContextStack;

pub const WidgetKind = element.WidgetKind;
pub const EventCallback = element.EventCallback;
pub const EventHandler = element.EventHandler;
pub const Property = element.Property;
pub const ContextProvision = element.ContextProvision;
pub const WidgetElement = element.WidgetElement;
pub const ComponentElement = element.ComponentElement;
pub const ProviderElement = element.ProviderElement;
pub const GroupElement = element.GroupElement;
pub const Visitor = element.Visitor;
pub const Element = element.Element;
pub const ElementError = element.Error;
pub const LeafBuilder = element.LeafBuilder;
pub const ContainerBuilder = element.ContainerBuilder;
pub const leaf = element.leaf;
pub const container = element.container;
pub const component = element.component;
pub const memo = element.memo;
pub const group = element.group;
pub const provide = element.provide;
pub const intoElement = element.intoElement;
pub const collectElements = element.collectElements;

pub const WidgetId = backend.WidgetId;
pub const Backend = backend.Backend;
pub const RecordingBackend = recording_backend.RecordingBackend;

pub const RequestRerender = render_cx.RequestRerender;
pub const ContextIdSet = render_cx.ContextIdSet;
pub const HookSlot = render_cx.HookSlot;
pub const RenderCx = render_cx.RenderCx;

pub const SetState = render_cx.SetState;
pub const StateResult = render_cx.StateResult;
pub const Updater = render_cx.Updater;
pub const ReducerResult = render_cx.ReducerResult;
pub const Dispatch = render_cx.Dispatch;
pub const ReducerFnResult = render_cx.ReducerFnResult;
pub const HookRef = render_cx.HookRef;
pub const AsyncSetState = render_cx.AsyncSetState;
pub const AsyncStateResult = render_cx.AsyncStateResult;

pub const Tree = reconciler.Tree;
pub const MountedWidget = reconciler.MountedWidget;
pub const MountedComponent = reconciler.MountedComponent;
pub const MountedProvider = reconciler.MountedProvider;
pub const MountedGroup = reconciler.MountedGroup;
pub const MountedElement = reconciler.MountedElement;
pub const Reconciler = reconciler.Reconciler;

pub const Error = render_cx.Error;

test {
    _ = @import("backend.zig");
    _ = @import("context.zig");
    _ = @import("element.zig");
    _ = @import("recording_backend.zig");
    _ = @import("reconciler.zig");
    _ = @import("render_cx.zig");
}
