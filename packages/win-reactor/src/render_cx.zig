const std = @import("std");
const box = @import("box.zig");
const context = @import("context.zig");

pub const Allocator = std.mem.Allocator;
pub const Error = context.Error || error{
    HookOrderMismatch,
};

pub const ContextIdSet = std.AutoHashMapUnmanaged(context.ContextId, void);

pub const RequestRerender = struct {
    /// Callback target that schedules a root-level rerender. The target is
    /// expected to outlive any setter handles derived from the owning
    /// `RenderCx`; later reconciler/host work should therefore point this at
    /// the root render host or dispatcher, not per-component ephemeral
    /// storage.
    userdata: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque) void = noop,

    pub fn init(userdata: ?*anyopaque, invoke_fn: *const fn (?*anyopaque) void) RequestRerender {
        return .{
            .userdata = userdata,
            .invoke_fn = invoke_fn,
        };
    }

    pub fn invoke(self: *const RequestRerender) void {
        self.invoke_fn(self.userdata);
    }

    pub fn none() RequestRerender {
        return .{};
    }

    fn noop(_: ?*anyopaque) void {}
};

const SpinMutex = struct {
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

    fn lock(self: *SpinMutex) void {
        while (self.state.swap(1, .acquire) != 0) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *SpinMutex) void {
        self.state.store(0, .release);
    }
};

var next_async_token = std.atomic.Value(u64).init(1);
var async_registry_lock = SpinMutex{};
var async_registry: std.AutoHashMapUnmanaged(u64, void) = .empty;

fn allocateAsyncToken() u64 {
    return next_async_token.fetchAdd(1, .seq_cst);
}

fn registerAsyncToken(token: u64) Allocator.Error!void {
    async_registry_lock.lock();
    defer async_registry_lock.unlock();
    try async_registry.put(std.heap.page_allocator, token, {});
}

fn unregisterAsyncToken(token: u64) void {
    async_registry_lock.lock();
    defer async_registry_lock.unlock();

    _ = async_registry.remove(token);
    if (async_registry.count() == 0) {
        async_registry.clearAndFree(std.heap.page_allocator);
    }
}

fn StateCell(comptime T: type) type {
    return struct {
        value: T,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            box.maybeDeinitValue(T, allocator, &self.value);
        }
    };
}

fn RefCellStorage(comptime T: type) type {
    return struct {
        value: T,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            box.maybeDeinitValue(T, allocator, &self.value);
        }
    };
}

fn AsyncStateCell(comptime T: type) type {
    return struct {
        mutex: SpinMutex = .{},
        value: T,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            box.maybeDeinitValue(T, allocator, &self.value);
        }
    };
}

pub fn SetState(comptime T: type) type {
    return struct {
        allocator: Allocator,
        cell: *StateCell(T),
        dirty: *std.atomic.Value(bool),
        request: *const RequestRerender,

        pub fn call(self: @This(), value: T) void {
            if (std.meta.eql(self.cell.value, value)) {
                return;
            }

            box.replaceValue(T, self.allocator, &self.cell.value, value);
            _ = self.dirty.swap(true, .seq_cst);
            self.request.invoke();
        }
    };
}

pub fn Updater(comptime T: type) type {
    return struct {
        allocator: Allocator,
        cell: *StateCell(T),
        dirty: *std.atomic.Value(bool),
        request: *const RequestRerender,

        pub fn call(self: @This(), comptime reducer: *const fn (*const T) T) void {
            const next = reducer(&self.cell.value);
            if (std.meta.eql(self.cell.value, next)) {
                return;
            }

            box.replaceValue(T, self.allocator, &self.cell.value, next);
            _ = self.dirty.swap(true, .seq_cst);
            self.request.invoke();
        }

        pub fn callWith(self: @This(), reducer_context: anytype, comptime reducer: *const fn (*const @TypeOf(reducer_context), *const T) T) void {
            const Context = @TypeOf(reducer_context);
            var context_copy: Context = reducer_context;
            const next = reducer(&context_copy, &self.cell.value);
            if (std.meta.eql(self.cell.value, next)) {
                return;
            }

            box.replaceValue(T, self.allocator, &self.cell.value, next);
            _ = self.dirty.swap(true, .seq_cst);
            self.request.invoke();
        }
    };
}

pub fn Dispatch(comptime State: type, comptime Action: type) type {
    return struct {
        allocator: Allocator,
        cell: *StateCell(State),
        dirty: *std.atomic.Value(bool),
        request: *const RequestRerender,
        reducer: *const fn (*const State, Action) State,

        pub fn call(self: @This(), action: Action) void {
            const next = self.reducer(&self.cell.value, action);
            if (std.meta.eql(self.cell.value, next)) {
                return;
            }

            box.replaceValue(State, self.allocator, &self.cell.value, next);
            _ = self.dirty.swap(true, .seq_cst);
            self.request.invoke();
        }
    };
}

pub fn HookRef(comptime T: type) type {
    return struct {
        allocator: Allocator,
        cell: *RefCellStorage(T),

        pub fn get(self: @This()) *const T {
            return &self.cell.value;
        }

        pub fn getMut(self: @This()) *T {
            return &self.cell.value;
        }

        pub fn set(self: @This(), value: T) void {
            box.replaceValue(T, self.allocator, &self.cell.value, value);
        }

        pub fn replace(self: @This(), value: T) T {
            const old = self.cell.value;
            self.cell.value = value;
            return old;
        }
    };
}

pub fn AsyncSetState(comptime T: type) type {
    return struct {
        allocator: Allocator,
        cell: *AsyncStateCell(T),
        dirty: *std.atomic.Value(bool),
        request: *const RequestRerender,
        token: u64,

        pub fn call(self: @This(), value: T) void {
            async_registry_lock.lock();
            if (!async_registry.contains(self.token)) {
                async_registry_lock.unlock();
                return;
            }

            self.cell.mutex.lock();
            if (std.meta.eql(self.cell.value, value)) {
                self.cell.mutex.unlock();
                async_registry_lock.unlock();
                return;
            }

            box.replaceValue(T, self.allocator, &self.cell.value, value);
            self.cell.mutex.unlock();
            _ = self.dirty.swap(true, .seq_cst);
            const request = self.request.*;
            async_registry_lock.unlock();
            request.invoke();
        }
    };
}

pub fn StateResult(comptime T: type) type {
    return struct {
        value: *const T,
        set: SetState(T),
    };
}

pub fn ReducerResult(comptime T: type) type {
    return struct {
        value: *const T,
        update: Updater(T),
    };
}

pub fn ReducerFnResult(comptime State: type, comptime Action: type) type {
    return struct {
        value: *const State,
        dispatch: Dispatch(State, Action),
    };
}

pub fn AsyncStateResult(comptime T: type) type {
    return struct {
        value: T,
        set: AsyncSetState(T),
    };
}

const CleanupRecord = struct {
    context_value: box.AnyBox,
    cleanup_fn: *const fn (*anyopaque) void,

    fn init(allocator: Allocator, cleanup_context: anytype, comptime cleanup: *const fn (*@TypeOf(cleanup_context)) void) Allocator.Error!CleanupRecord {
        const CleanupContext = @TypeOf(cleanup_context);
        return .{
            .context_value = try box.AnyBox.init(allocator, cleanup_context),
            .cleanup_fn = &struct {
                fn call(raw: *anyopaque) void {
                    const typed: *CleanupContext = @ptrCast(@alignCast(raw));
                    cleanup(typed);
                }
            }.call,
        };
    }

    fn runAndDeinit(self: *CleanupRecord, allocator: Allocator) void {
        self.cleanup_fn(self.context_value.ptr);
        self.context_value.deinit(allocator);
        self.* = undefined;
    }

    fn deinit(self: *CleanupRecord, allocator: Allocator) void {
        self.context_value.deinit(allocator);
        self.* = undefined;
    }
};

const PendingEffect = struct {
    effect_context: box.AnyBox,
    run_fn: *const fn (allocator: Allocator, raw: *anyopaque) Allocator.Error!?CleanupRecord,

    fn init(allocator: Allocator, effect_context: anytype, comptime effect: *const fn (*const @TypeOf(effect_context)) void) Allocator.Error!PendingEffect {
        const EffectContext = @TypeOf(effect_context);
        return .{
            .effect_context = try box.AnyBox.init(allocator, effect_context),
            .run_fn = &struct {
                fn call(_: Allocator, raw: *anyopaque) Allocator.Error!?CleanupRecord {
                    const typed: *const EffectContext = @ptrCast(@alignCast(raw));
                    effect(typed);
                    return null;
                }
            }.call,
        };
    }

    fn initWithCleanup(
        allocator: Allocator,
        effect_context: anytype,
        comptime CleanupContext: type,
        comptime effect: *const fn (*const @TypeOf(effect_context)) ?CleanupContext,
        comptime cleanup: *const fn (*CleanupContext) void,
    ) Allocator.Error!PendingEffect {
        const EffectContext = @TypeOf(effect_context);
        return .{
            .effect_context = try box.AnyBox.init(allocator, effect_context),
            .run_fn = &struct {
                fn call(run_allocator: Allocator, raw: *anyopaque) Allocator.Error!?CleanupRecord {
                    const typed: *const EffectContext = @ptrCast(@alignCast(raw));
                    const maybe_cleanup = effect(typed);
                    if (maybe_cleanup) |cleanup_context| {
                        var owned_cleanup = cleanup_context;
                        errdefer box.maybeDeinitValue(CleanupContext, run_allocator, &owned_cleanup);
                        return try CleanupRecord.init(run_allocator, owned_cleanup, cleanup);
                    }
                    return null;
                }
            }.call,
        };
    }

    fn runAndDeinit(self: *PendingEffect, allocator: Allocator) Allocator.Error!?CleanupRecord {
        const result = try self.run_fn(allocator, self.effect_context.ptr);
        self.effect_context.deinit(allocator);
        self.* = undefined;
        return result;
    }

    fn deinit(self: *PendingEffect, allocator: Allocator) void {
        self.effect_context.deinit(allocator);
        self.* = undefined;
    }
};

pub const HookSlot = union(enum) {
    /// `useState` / `useReducer` / `useReducerFn` / `useRef` all claim a
    /// render-order slot from this family. The stored cell wrapper type
    /// (`StateCell(T)` vs `RefCellStorage(T)`) is what distinguishes
    /// mutable refs from value-state hooks.
    state: StateSlot,
    /// Memoised value gated by dependency equality.
    memo: MemoSlot,
    /// Deferred side effects + cleanups; populated during render and
    /// executed by `flushEffects`.
    effect: EffectSlot,
    /// Thread-safe state cell used by `useAsyncState`.
    async_state: AsyncStateSlot,

    pub const StateSlot = struct {
        cell: box.AnyBox,
        type_name: []const u8,
    };

    pub const MemoSlot = struct {
        value: box.AnyBox,
        deps: ?box.EqBox,
    };

    pub const EffectSlot = struct {
        deps: ?box.EqBox,
        pending: ?PendingEffect,
        cleanup: ?CleanupRecord,
        pending_cleanup: ?CleanupRecord,
    };

    pub const AsyncStateSlot = struct {
        cell: box.AnyBox,
        token: u64,
        type_name: []const u8,
    };

    fn deinit(self: *HookSlot, allocator: Allocator) void {
        switch (self.*) {
            .state => |*slot| {
                slot.cell.deinit(allocator);
            },
            .memo => |*slot| {
                slot.value.deinit(allocator);
                if (slot.deps) |*deps| deps.deinit(allocator);
            },
            .effect => |*slot| {
                if (slot.deps) |*deps| deps.deinit(allocator);
                if (slot.pending) |*pending| pending.deinit(allocator);
                if (slot.cleanup) |*cleanup| cleanup.deinit(allocator);
                if (slot.pending_cleanup) |*cleanup| cleanup.deinit(allocator);
            },
            .async_state => |*slot| {
                unregisterAsyncToken(slot.token);
                slot.cell.deinit(allocator);
            },
        }
    }
};

fn assertCopySafeStateType(comptime T: type) void {
    box.assertBorrowedValueType(T, "state hooks");
}

/// Per-component hook state. Later milestones should allocate one
/// `RenderCx` per mounted component instance, call `beginRender()` before
/// invoking the component, `finishRender()` after the last hook call, then
/// `flushEffects()` once the surrounding tree update commits.
pub const RenderCx = struct {
    allocator: Allocator,
    slots: std.ArrayListUnmanaged(HookSlot) = .empty,
    cursor: usize = 0,
    last_completed_hook_count: ?usize = null,
    request_rerender: RequestRerender = RequestRerender.none(),
    state_dirty: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    context_stack: ?*context.ContextStack = null,
    read_contexts: ContextIdSet = .empty,
    poisoned: bool = false,

    pub fn init(allocator: Allocator, request_rerender: RequestRerender) RenderCx {
        return .{
            .allocator = allocator,
            .request_rerender = request_rerender,
        };
    }

    pub fn deinit(self: *RenderCx) void {
        self.runCleanups();

        for (self.slots.items) |*slot| {
            slot.deinit(self.allocator);
        }
        self.slots.deinit(self.allocator);
        self.read_contexts.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn beginRender(self: *RenderCx) void {
        self.cursor = 0;
        self.read_contexts.clearRetainingCapacity();
        _ = self.state_dirty.swap(false, .seq_cst);
    }

    /// Enforces the "same hook order every render" invariant. A later
    /// render that calls fewer or more hooks than the last completed render
    /// returns `error.HookOrderMismatch`.
    pub fn finishRender(self: *RenderCx) Error!void {
        try self.ensureHealthy();
        if (self.last_completed_hook_count) |expected| {
            if (self.cursor != expected) return self.failHookOrder();
        }

        std.debug.assert(self.cursor == self.slots.items.len);
        self.last_completed_hook_count = self.cursor;
    }

    pub fn flushEffects(self: *RenderCx) Allocator.Error!void {
        if (self.poisoned) return;

        for (self.slots.items) |*slot| {
            switch (slot.*) {
                .effect => |*effect_slot| {
                    if (effect_slot.pending_cleanup) |*cleanup| {
                        cleanup.runAndDeinit(self.allocator);
                        effect_slot.pending_cleanup = null;
                    }
                },
                else => {},
            }
        }

        for (self.slots.items) |*slot| {
            switch (slot.*) {
                .effect => |*effect_slot| {
                    if (effect_slot.pending) |*pending| {
                        const cleanup = try pending.runAndDeinit(self.allocator);
                        effect_slot.pending = null;
                        effect_slot.cleanup = cleanup;
                    }
                },
                else => {},
            }
        }
    }

    pub fn runCleanups(self: *RenderCx) void {
        for (self.slots.items) |*slot| {
            switch (slot.*) {
                .effect => |*effect_slot| {
                    if (effect_slot.pending_cleanup) |*cleanup| {
                        cleanup.runAndDeinit(self.allocator);
                        effect_slot.pending_cleanup = null;
                    }
                    if (effect_slot.cleanup) |*cleanup| {
                        cleanup.runAndDeinit(self.allocator);
                        effect_slot.cleanup = null;
                    }
                },
                else => {},
            }
        }
    }

    pub fn setRequestRerender(self: *RenderCx, request_rerender: RequestRerender) void {
        self.request_rerender = request_rerender;
    }

    pub fn setContextStack(self: *RenderCx, stack: ?*context.ContextStack) void {
        self.context_stack = stack;
    }

    pub fn takeReadContexts(self: *RenderCx) ContextIdSet {
        const out = self.read_contexts;
        self.read_contexts = .empty;
        return out;
    }

    pub fn hookCount(self: *const RenderCx) usize {
        return self.slots.items.len;
    }

    pub fn peekStateDirty(self: *const RenderCx) bool {
        return self.state_dirty.load(.seq_cst);
    }

    pub fn takeStateDirty(self: *RenderCx) bool {
        return self.state_dirty.swap(false, .seq_cst);
    }

    /// Returns a copy of the currently visible context value. Context reads
    /// use the same copy-safe-value restriction as state hooks because the
    /// provider stack owns and frees boxed provider values as scopes pop.
    pub fn useContext(self: *RenderCx, comptime T: type, value_context: *const context.Context(T)) Error!T {
        comptime box.assertBorrowedValueType(T, "useContext");
        try self.ensureHealthy();
        try self.read_contexts.put(self.allocator, value_context.id, {});
        if (self.context_stack) |stack| {
            if (try stack.get(T, value_context)) |value| return value;
        }
        return value_context.default;
    }

    /// Returns a pointer into stable slot storage plus a setter handle that
    /// requests a rerender on real value changes. `T` must be a copy-safe
    /// value type without a custom `deinit`; put owned resources behind a
    /// pointer or inside `useRef` instead. Pointer and slice fields are
    /// treated as externally owned views; the hook slot only stores them
    /// by value.
    pub fn useState(self: *RenderCx, comptime T: type, initial: T) Error!StateResult(T) {
        comptime assertCopySafeStateType(T);
        try self.ensureHealthy();
        const cell = try self.acquireStateCell(T, initial);
        return .{
            .value = &cell.value,
            .set = .{
                .allocator = self.allocator,
                .cell = cell,
                .dirty = &self.state_dirty,
                .request = &self.request_rerender,
            },
        };
    }

    /// `useReducer` shares the same `.state` slot family as `useState`;
    /// only the returned handle type differs.
    pub fn useReducer(self: *RenderCx, comptime T: type, initial: T) Error!ReducerResult(T) {
        comptime assertCopySafeStateType(T);
        try self.ensureHealthy();
        const cell = try self.acquireStateCell(T, initial);
        return .{
            .value = &cell.value,
            .update = .{
                .allocator = self.allocator,
                .cell = cell,
                .dirty = &self.state_dirty,
                .request = &self.request_rerender,
            },
        };
    }

    /// `useReducerFn` stores only the state slot. The reducer function is
    /// carried by the returned dispatch handle so callers can swap reducers
    /// across renders if they choose.
    pub fn useReducerFn(
        self: *RenderCx,
        comptime State: type,
        comptime Action: type,
        reducer: *const fn (*const State, Action) State,
        initial: State,
    ) Error!ReducerFnResult(State, Action) {
        comptime assertCopySafeStateType(State);
        try self.ensureHealthy();
        const cell = try self.acquireStateCell(State, initial);
        return .{
            .value = &cell.value,
            .dispatch = .{
                .allocator = self.allocator,
                .cell = cell,
                .dirty = &self.state_dirty,
                .request = &self.request_rerender,
                .reducer = reducer,
            },
        };
    }

    /// `useRef` stores a dedicated `RefCellStorage(T)` wrapper inside the
    /// `.state` slot family so `useRef(T)` mismatches with `useState(T)`.
    pub fn useRef(self: *RenderCx, comptime T: type, initial: T) Error!HookRef(T) {
        try self.ensureHealthy();
        const slot_index = self.nextSlotIndex();

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            var cell_box = try box.AnyBox.init(self.allocator, RefCellStorage(T){ .value = initial });
            errdefer cell_box.deinit(self.allocator);

            try self.slots.append(self.allocator, .{
                .state = .{
                    .cell = cell_box,
                    .type_name = std.fmt.comptimePrint("ref({s})", .{@typeName(T)}),
                },
            });
        }

        switch (self.slots.items[slot_index]) {
            .state => |*state_slot| {
                if (!state_slot.cell.is(RefCellStorage(T))) return self.failHookOrder();
                const cell = state_slot.cell.get(RefCellStorage(T));
                return .{
                    .allocator = self.allocator,
                    .cell = cell,
                };
            },
            else => return self.failHookOrder(),
        }
    }

    /// Memoised value keyed by dependency equality. The value lives in the
    /// slot and is returned by pointer to avoid implicit cloning of owned
    /// Zig values.
    pub fn useMemo(
        self: *RenderCx,
        comptime T: type,
        deps: anytype,
        memo_context: anytype,
        comptime factory: *const fn (*const @TypeOf(memo_context)) T,
    ) Error!*const T {
        try self.ensureHealthy();
        const slot_index = self.nextSlotIndex();
        const MemoContext = @TypeOf(memo_context);

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            var context_copy: MemoContext = memo_context;
            var new_value = factory(&context_copy);
            errdefer box.maybeDeinitValue(T, self.allocator, &new_value);
            var new_deps = try box.EqBox.init(self.allocator, deps);
            errdefer new_deps.deinit(self.allocator);
            var value_box = try box.AnyBox.init(self.allocator, new_value);
            errdefer value_box.deinit(self.allocator);

            try self.slots.append(self.allocator, .{
                .memo = .{
                    .value = value_box,
                    .deps = new_deps,
                },
            });
        }

        switch (self.slots.items[slot_index]) {
            .memo => |*memo_slot| {
                if (!memo_slot.value.is(T)) return self.failHookOrder();

                if (memo_slot.deps) |*stored_deps| {
                    if (stored_deps.eqlValue(deps)) {
                        return memo_slot.value.getConst(T);
                    }
                }

                var context_copy: MemoContext = memo_context;
                var new_value = factory(&context_copy);
                errdefer box.maybeDeinitValue(T, self.allocator, &new_value);
                var new_deps = try box.EqBox.init(self.allocator, deps);
                errdefer new_deps.deinit(self.allocator);

                memo_slot.value.replace(self.allocator, new_value);
                if (memo_slot.deps) |*old_deps| old_deps.deinit(self.allocator);
                memo_slot.deps = new_deps;
                return memo_slot.value.getConst(T);
            },
            else => return self.failHookOrder(),
        }
    }

    /// Schedules a deferred side effect to run after the render commits.
    pub fn useEffect(
        self: *RenderCx,
        deps: anytype,
        effect_context: anytype,
        comptime effect: *const fn (*const @TypeOf(effect_context)) void,
    ) Error!void {
        try self.ensureHealthy();
        const slot_index = self.nextSlotIndex();

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            var new_deps = try box.EqBox.init(self.allocator, deps);
            errdefer new_deps.deinit(self.allocator);
            var pending = try PendingEffect.init(self.allocator, effect_context, effect);
            errdefer pending.deinit(self.allocator);

            try self.slots.append(self.allocator, .{
                .effect = .{
                    .deps = new_deps,
                    .pending = pending,
                    .cleanup = null,
                    .pending_cleanup = null,
                },
            });
            return;
        }

        switch (self.slots.items[slot_index]) {
            .effect => |*effect_slot| {
                if (effect_slot.deps) |*stored_deps| {
                    if (stored_deps.eqlValue(deps)) return;
                }

                var new_deps = try box.EqBox.init(self.allocator, deps);
                errdefer new_deps.deinit(self.allocator);
                var new_pending = try PendingEffect.init(self.allocator, effect_context, effect);
                errdefer new_pending.deinit(self.allocator);

                if (effect_slot.pending) |*old_pending| old_pending.deinit(self.allocator);
                if (effect_slot.cleanup) |current_cleanup| {
                    effect_slot.pending_cleanup = current_cleanup;
                    effect_slot.cleanup = null;
                }
                if (effect_slot.deps) |*old_deps| old_deps.deinit(self.allocator);

                effect_slot.deps = new_deps;
                effect_slot.pending = new_pending;
            },
            else => return self.failHookOrder(),
        }
    }

    /// Like `useEffect`, but lets the effect return a cleanup context value
    /// that is fed back into `cleanup` on dependency changes or unmount.
    /// The hook slot still owns that cleanup context and automatically
    /// deinits it after `cleanup` returns.
    pub fn useEffectWithCleanup(
        self: *RenderCx,
        comptime CleanupContext: type,
        deps: anytype,
        effect_context: anytype,
        comptime effect: *const fn (*const @TypeOf(effect_context)) ?CleanupContext,
        comptime cleanup: *const fn (*CleanupContext) void,
    ) Error!void {
        try self.ensureHealthy();
        const slot_index = self.nextSlotIndex();

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            var new_deps = try box.EqBox.init(self.allocator, deps);
            errdefer new_deps.deinit(self.allocator);
            var pending = try PendingEffect.initWithCleanup(self.allocator, effect_context, CleanupContext, effect, cleanup);
            errdefer pending.deinit(self.allocator);

            try self.slots.append(self.allocator, .{
                .effect = .{
                    .deps = new_deps,
                    .pending = pending,
                    .cleanup = null,
                    .pending_cleanup = null,
                },
            });
            return;
        }

        switch (self.slots.items[slot_index]) {
            .effect => |*effect_slot| {
                if (effect_slot.deps) |*stored_deps| {
                    if (stored_deps.eqlValue(deps)) return;
                }

                var new_deps = try box.EqBox.init(self.allocator, deps);
                errdefer new_deps.deinit(self.allocator);
                var new_pending = try PendingEffect.initWithCleanup(self.allocator, effect_context, CleanupContext, effect, cleanup);
                errdefer new_pending.deinit(self.allocator);

                if (effect_slot.pending) |*old_pending| old_pending.deinit(self.allocator);
                if (effect_slot.cleanup) |current_cleanup| {
                    effect_slot.pending_cleanup = current_cleanup;
                    effect_slot.cleanup = null;
                }
                if (effect_slot.deps) |*old_deps| old_deps.deinit(self.allocator);

                effect_slot.deps = new_deps;
                effect_slot.pending = new_pending;
            },
            else => return self.failHookOrder(),
        }
    }

    /// Thread-safe state slot used by future resource-style hooks. The
    /// snapshot is returned by value because the underlying cell is
    /// protected by a lock, so the same copy-safe-type restriction as
    /// `useState` applies. Pointer and slice fields are treated as
    /// externally owned views; the hook slot only stores/copies them.
    pub fn useAsyncState(self: *RenderCx, comptime T: type, initial: T) Error!AsyncStateResult(T) {
        comptime assertCopySafeStateType(T);
        try self.ensureHealthy();
        const slot_index = self.nextSlotIndex();

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            const token = allocateAsyncToken();
            var cell_box = try box.AnyBox.init(self.allocator, AsyncStateCell(T){ .value = initial });
            errdefer cell_box.deinit(self.allocator);
            try registerAsyncToken(token);
            errdefer unregisterAsyncToken(token);

            try self.slots.append(self.allocator, .{
                .async_state = .{
                    .cell = cell_box,
                    .token = token,
                    .type_name = std.fmt.comptimePrint("async_state({s})", .{@typeName(T)}),
                },
            });
        }

        switch (self.slots.items[slot_index]) {
            .async_state => |*async_slot| {
                if (!async_slot.cell.is(AsyncStateCell(T))) return self.failHookOrder();
                const cell = async_slot.cell.get(AsyncStateCell(T));
                cell.mutex.lock();
                defer cell.mutex.unlock();

                return .{
                    .value = cell.value,
                    .set = .{
                        .allocator = self.allocator,
                        .cell = cell,
                        .dirty = &self.state_dirty,
                        .request = &self.request_rerender,
                        .token = async_slot.token,
                    },
                };
            },
            else => return self.failHookOrder(),
        }
    }

    fn nextSlotIndex(self: *RenderCx) usize {
        const slot_index = self.cursor;
        self.cursor += 1;
        return slot_index;
    }

    fn ensureCanAllocateNewSlot(self: *RenderCx, slot_index: usize) Error!void {
        if (self.last_completed_hook_count) |previous_count| {
            if (slot_index >= previous_count) return self.failHookOrder();
        }
    }

    fn acquireStateCell(self: *RenderCx, comptime T: type, initial: T) Error!*StateCell(T) {
        const slot_index = self.nextSlotIndex();

        if (slot_index == self.slots.items.len) {
            try self.ensureCanAllocateNewSlot(slot_index);

            var cell_box = try box.AnyBox.init(self.allocator, StateCell(T){ .value = initial });
            errdefer cell_box.deinit(self.allocator);

            try self.slots.append(self.allocator, .{
                .state = .{
                    .cell = cell_box,
                    .type_name = std.fmt.comptimePrint("state({s})", .{@typeName(T)}),
                },
            });
        }

        switch (self.slots.items[slot_index]) {
            .state => |*state_slot| {
                if (!state_slot.cell.is(StateCell(T))) return self.failHookOrder();
                return state_slot.cell.get(StateCell(T));
            },
            else => return self.failHookOrder(),
        }
    }

    fn ensureHealthy(self: *RenderCx) Error!void {
        if (self.poisoned) return self.failHookOrder();
    }

    fn failHookOrder(self: *RenderCx) error{HookOrderMismatch} {
        self.poisoned = true;
        return error.HookOrderMismatch;
    }
};

const CountAction = union(enum) {
    add: i32,
    reset,
};

const EffectLog = struct {
    items: [16][]const u8 = undefined,
    len: usize = 0,

    fn push(self: *EffectLog, item: []const u8) void {
        self.items[self.len] = item;
        self.len += 1;
    }
};

const RerenderCounter = struct {
    count: u32 = 0,

    fn request(raw: ?*anyopaque) void {
        const self: *RerenderCounter = @ptrCast(@alignCast(raw.?));
        self.count += 1;
    }
};

const AsyncRerenderCounter = struct {
    count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    fn request(raw: ?*anyopaque) void {
        const self: *AsyncRerenderCounter = @ptrCast(@alignCast(raw.?));
        _ = self.count.fetchAdd(1, .seq_cst);
    }
};

test "useState persists across re-renders and only rerenders on change" {
    var rerenders = RerenderCounter{};
    var cx = RenderCx.init(
        std.testing.allocator,
        RequestRerender.init(@ptrCast(&rerenders), RerenderCounter.request),
    );
    defer cx.deinit();

    cx.beginRender();
    const state = try cx.useState(i32, 0);
    try std.testing.expectEqual(@as(i32, 0), state.value.*);
    try cx.finishRender();

    state.set.call(1);
    try std.testing.expectEqual(@as(u32, 1), rerenders.count);
    try std.testing.expect(cx.peekStateDirty());

    cx.beginRender();
    const rerendered = try cx.useState(i32, 0);
    try std.testing.expectEqual(@as(i32, 1), rerendered.value.*);
    try cx.finishRender();
    try std.testing.expect(!cx.peekStateDirty());

    rerendered.set.call(1);
    try std.testing.expectEqual(@as(u32, 1), rerenders.count);
}

test "useRef persists mutable storage without scheduling rerender" {
    var rerenders = RerenderCounter{};
    var cx = RenderCx.init(
        std.testing.allocator,
        RequestRerender.init(@ptrCast(&rerenders), RerenderCounter.request),
    );
    defer cx.deinit();

    cx.beginRender();
    const render_count = try cx.useRef(u32, 0);
    render_count.getMut().* += 1;
    try std.testing.expectEqual(@as(u32, 1), render_count.get().*);
    try cx.finishRender();

    cx.beginRender();
    const same_ref = try cx.useRef(u32, 0);
    same_ref.getMut().* += 1;
    try std.testing.expectEqual(@as(u32, 2), same_ref.get().*);
    try cx.finishRender();
    try std.testing.expectEqual(@as(u32, 0), rerenders.count);
}

test "useMemo recomputes only when dependency changes" {
    var rerenders = RerenderCounter{};
    var cx = RenderCx.init(
        std.testing.allocator,
        RequestRerender.init(@ptrCast(&rerenders), RerenderCounter.request),
    );
    defer cx.deinit();

    var call_count: u32 = 0;

    const MemoContext = struct {
        call_count: *u32,
        number: i32,
    };
    const MemoFactory = struct {
        fn run(ctx: *const MemoContext) i32 {
            ctx.call_count.* += 1;
            return ctx.number * 2;
        }
    };

    cx.beginRender();
    const number = try cx.useState(i32, 5);
    const unrelated = try cx.useState(i32, 0);
    const doubled = try cx.useMemo(i32, number.value.*, MemoContext{
        .call_count = &call_count,
        .number = number.value.*,
    }, MemoFactory.run);
    try std.testing.expectEqual(@as(i32, 10), doubled.*);
    try cx.finishRender();
    try std.testing.expectEqual(@as(u32, 1), call_count);

    unrelated.set.call(1);

    cx.beginRender();
    const number_again = try cx.useState(i32, 5);
    const unrelated_again = try cx.useState(i32, 0);
    const doubled_again = try cx.useMemo(i32, number_again.value.*, MemoContext{
        .call_count = &call_count,
        .number = number_again.value.*,
    }, MemoFactory.run);
    _ = unrelated_again;
    try std.testing.expectEqual(@as(i32, 10), doubled_again.*);
    try cx.finishRender();
    try std.testing.expectEqual(@as(u32, 1), call_count);

    number_again.set.call(6);

    cx.beginRender();
    const number_changed = try cx.useState(i32, 5);
    _ = try cx.useState(i32, 0);
    const doubled_changed = try cx.useMemo(i32, number_changed.value.*, MemoContext{
        .call_count = &call_count,
        .number = number_changed.value.*,
    }, MemoFactory.run);
    try std.testing.expectEqual(@as(i32, 12), doubled_changed.*);
    try cx.finishRender();
    try std.testing.expectEqual(@as(u32, 2), call_count);
}

test "useEffect fires on mount and dependency changes" {
    var cx = RenderCx.init(std.testing.allocator, RequestRerender.none());
    defer cx.deinit();

    var log = EffectLog{};

    const EffectContext = struct {
        log: *EffectLog,
        value: i32,
    };
    const RunEffect = struct {
        fn run(ctx: *const EffectContext) void {
            switch (ctx.value) {
                0 => ctx.log.push("effect-0"),
                1 => ctx.log.push("effect-1"),
                else => ctx.log.push("effect-other"),
            }
        }
    };

    cx.beginRender();
    const state = try cx.useState(i32, 0);
    try cx.useEffect(state.value.*, EffectContext{
        .log = &log,
        .value = state.value.*,
    }, RunEffect.run);
    try cx.finishRender();
    try cx.flushEffects();
    try std.testing.expectEqual(@as(usize, 1), log.len);
    try std.testing.expectEqualStrings("effect-0", log.items[0]);

    state.set.call(1);

    cx.beginRender();
    const rerendered = try cx.useState(i32, 0);
    try cx.useEffect(rerendered.value.*, EffectContext{
        .log = &log,
        .value = rerendered.value.*,
    }, RunEffect.run);
    try cx.finishRender();
    try cx.flushEffects();
    try std.testing.expectEqual(@as(usize, 2), log.len);
    try std.testing.expectEqualStrings("effect-1", log.items[1]);
}

test "useEffectWithCleanup runs cleanup before the next effect and on unmount" {
    var cx = RenderCx.init(std.testing.allocator, RequestRerender.none());
    defer cx.deinit();

    var log = EffectLog{};

    const EffectContext = struct {
        log: *EffectLog,
        value: i32,
    };
    const CleanupContext = struct {
        log: *EffectLog,
        value: i32,
    };
    const RunEffect = struct {
        fn run(ctx: *const EffectContext) ?CleanupContext {
            switch (ctx.value) {
                0 => ctx.log.push("effect-0"),
                1 => ctx.log.push("effect-1"),
                else => ctx.log.push("effect-other"),
            }
            return .{
                .log = ctx.log,
                .value = ctx.value,
            };
        }
    };
    const RunCleanup = struct {
        fn run(ctx: *CleanupContext) void {
            switch (ctx.value) {
                0 => ctx.log.push("cleanup-0"),
                1 => ctx.log.push("cleanup-1"),
                else => ctx.log.push("cleanup-other"),
            }
        }
    };

    cx.beginRender();
    const state = try cx.useState(i32, 0);
    try cx.useEffectWithCleanup(CleanupContext, state.value.*, EffectContext{
        .log = &log,
        .value = state.value.*,
    }, RunEffect.run, RunCleanup.run);
    try cx.finishRender();
    try cx.flushEffects();
    try std.testing.expectEqualSlices([]const u8, &[_][]const u8{"effect-0"}, log.items[0..log.len]);

    state.set.call(1);

    cx.beginRender();
    const rerendered = try cx.useState(i32, 0);
    try cx.useEffectWithCleanup(CleanupContext, rerendered.value.*, EffectContext{
        .log = &log,
        .value = rerendered.value.*,
    }, RunEffect.run, RunCleanup.run);
    try cx.finishRender();
    try cx.flushEffects();
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ "effect-0", "cleanup-0", "effect-1" },
        log.items[0..log.len],
    );

    cx.runCleanups();
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ "effect-0", "cleanup-0", "effect-1", "cleanup-1" },
        log.items[0..log.len],
    );
}

fn increment(prev: *const i32) i32 {
    return prev.* + 1;
}

fn countReducer(state: *const i32, action: CountAction) i32 {
    return switch (action) {
        .add => |amount| state.* + amount,
        .reset => 0,
    };
}

test "useReducer and useReducerFn update state through stable slots" {
    var rerenders = RerenderCounter{};
    var cx = RenderCx.init(
        std.testing.allocator,
        RequestRerender.init(@ptrCast(&rerenders), RerenderCounter.request),
    );
    defer cx.deinit();

    cx.beginRender();
    const reduced = try cx.useReducer(i32, 0);
    const reduced_fn = try cx.useReducerFn(i32, CountAction, countReducer, 10);
    try cx.finishRender();

    reduced.update.call(increment);
    reduced.update.call(increment);
    reduced_fn.dispatch.call(.{ .add = 5 });
    reduced_fn.dispatch.call(.reset);
    try std.testing.expectEqual(@as(u32, 4), rerenders.count);

    cx.beginRender();
    const reduced_again = try cx.useReducer(i32, 0);
    const reduced_fn_again = try cx.useReducerFn(i32, CountAction, countReducer, 10);
    try cx.finishRender();

    try std.testing.expectEqual(@as(i32, 2), reduced_again.value.*);
    try std.testing.expectEqual(@as(i32, 0), reduced_fn_again.value.*);
}

test "useContext returns defaults, provided values, and records subscriptions" {
    const ThemeContext = context.Context([]const u8);
    const theme = ThemeContext.init("light");

    var stack = context.ContextStack.init(std.testing.allocator);
    defer stack.deinit();

    var cx = RenderCx.init(std.testing.allocator, RequestRerender.none());
    defer cx.deinit();
    cx.setContextStack(&stack);

    cx.beginRender();
    const default_value = try cx.useContext([]const u8, &theme);
    try std.testing.expectEqualStrings("light", default_value);
    try cx.finishRender();

    var read_contexts = cx.takeReadContexts();
    defer read_contexts.deinit(std.testing.allocator);
    try std.testing.expect(read_contexts.contains(theme.id));

    var scope = try stack.push([]const u8, &theme, "dark");
    defer scope.deinit();

    cx.beginRender();
    const provided_value = try cx.useContext([]const u8, &theme);
    try std.testing.expectEqualStrings("dark", provided_value);
    try cx.finishRender();
}

const AsyncWorker = struct {
    setter: AsyncSetState(i32),
    value: i32,
};

fn setAsyncValue(worker: *const AsyncWorker) void {
    worker.setter.call(worker.value);
}

test "useAsyncState updates from another thread" {
    var rerenders = AsyncRerenderCounter{};
    var cx = RenderCx.init(
        std.testing.allocator,
        RequestRerender.init(@ptrCast(&rerenders), AsyncRerenderCounter.request),
    );
    defer cx.deinit();

    cx.beginRender();
    const async_state = try cx.useAsyncState(i32, 1);
    try std.testing.expectEqual(@as(i32, 1), async_state.value);
    try cx.finishRender();

    const worker = AsyncWorker{ .setter = async_state.set, .value = 7 };
    var thread = try std.Thread.spawn(.{}, setAsyncValue, .{&worker});
    thread.join();

    try std.testing.expectEqual(@as(u32, 1), rerenders.count.load(.seq_cst));
    try std.testing.expect(cx.peekStateDirty());

    cx.beginRender();
    const async_state_again = try cx.useAsyncState(i32, 1);
    try std.testing.expectEqual(@as(i32, 7), async_state_again.value);
    try cx.finishRender();
}

test "hook-order mismatches are reported" {
    var cx = RenderCx.init(std.testing.allocator, RequestRerender.none());
    defer cx.deinit();

    cx.beginRender();
    _ = try cx.useState(i32, 1);
    _ = try cx.useRef(u32, 0);
    try cx.finishRender();

    cx.beginRender();
    _ = try cx.useState(i32, 1);
    try std.testing.expectError(error.HookOrderMismatch, cx.finishRender());

    cx.beginRender();
    try std.testing.expectError(error.HookOrderMismatch, cx.useState(i32, 1));

    var cx2 = RenderCx.init(std.testing.allocator, RequestRerender.none());
    defer cx2.deinit();

    cx2.beginRender();
    _ = try cx2.useState(i32, 1);
    _ = try cx2.useRef(u32, 0);
    try cx2.finishRender();

    cx2.beginRender();
    _ = try cx2.useState(i32, 1);
    try std.testing.expectError(error.HookOrderMismatch, cx2.useState(u32, 0));
}
