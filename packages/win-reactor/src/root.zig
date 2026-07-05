//! `win-reactor` — backend-agnostic hook-slot engine for the future
//! Reactor render tree and reconciler.
//!
//! This package intentionally stays pure Zig + `std`: no WinRT, WinUI3,
//! COM, or `win-core` dependency. The core abstraction is a per-node
//! `RenderCx` whose render-order hook slots persist state, memo values,
//! deferred effects, async state, and context subscriptions across
//! re-renders.

const context = @import("context.zig");
const render_cx = @import("render_cx.zig");

pub const ContextId = context.ContextId;
pub const Context = context.Context;
pub const ContextScope = context.ContextScope;
pub const ContextStack = context.ContextStack;

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

pub const Error = render_cx.Error;

test {
    _ = @import("context.zig");
    _ = @import("render_cx.zig");
}
