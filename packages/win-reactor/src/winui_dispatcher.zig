const std = @import("std");
const win_core = @import("win-core");
const System = @import("reactor-windows-system");

const DispatcherQueueOptions = extern struct {
    dwSize: u32,
    threadType: i32,
    apartmentType: i32,
};

const DQTYPE_THREAD_CURRENT: i32 = 2;
const DQTAT_COM_STA: i32 = 2;

extern "CoreMessaging" fn CreateDispatcherQueueController(
    options: DispatcherQueueOptions,
    dispatcher_queue_controller: *?*anyopaque,
) callconv(.winapi) win_core.HRESULT;

pub const DispatcherPriority = enum(i32) {
    low = -10,
    normal = 0,
    high = 10,
};

pub const Task = struct {
    user_data: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque) void,
    cleanup_fn: ?*const fn (?*anyopaque) void = null,

    pub fn invoke(self: Task) void {
        self.invoke_fn(self.user_data);
    }

    pub fn cleanup(self: Task) void {
        if (self.cleanup_fn) |cleanup_fn| {
            cleanup_fn(self.user_data);
        }
    }
};

pub const SendDispatcher = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        enqueue: *const fn (ptr: *anyopaque, priority: DispatcherPriority, task: Task) anyerror!void,
    };

    pub fn from(implementation: anytype) SendDispatcher {
        const Ptr = @TypeOf(implementation);
        const ptr_info = @typeInfo(Ptr);
        if (ptr_info != .pointer or ptr_info.pointer.size != .one) {
            @compileError("SendDispatcher.from expects a single-item pointer");
        }

        const T = ptr_info.pointer.child;
        return .{
            .ptr = @ptrCast(implementation),
            .vtable = &struct {
                fn selfFrom(raw: *anyopaque) *T {
                    return @ptrCast(@alignCast(raw));
                }

                fn enqueueThunk(raw: *anyopaque, priority: DispatcherPriority, task: Task) anyerror!void {
                    return selfFrom(raw).enqueue(priority, task);
                }

                const value = VTable{
                    .enqueue = enqueueThunk,
                };
            }.value,
        };
    }

    pub fn enqueue(self: SendDispatcher, priority: DispatcherPriority, task: Task) anyerror!void {
        return self.vtable.enqueue(self.ptr, priority, task);
    }
};

pub const UiMarshaller = struct {
    dispatcher: SendDispatcher,

    pub fn init(dispatcher: SendDispatcher) UiMarshaller {
        return .{ .dispatcher = dispatcher };
    }

    pub fn dispatch(self: UiMarshaller, user_data: ?*anyopaque, invoke_fn: *const fn (?*anyopaque) void) !void {
        return self.dispatchTask(.normal, .{
            .user_data = user_data,
            .invoke_fn = invoke_fn,
        });
    }

    pub fn dispatchLow(self: UiMarshaller, user_data: ?*anyopaque, invoke_fn: *const fn (?*anyopaque) void) !void {
        return self.dispatchTask(.low, .{
            .user_data = user_data,
            .invoke_fn = invoke_fn,
        });
    }

    pub fn dispatchTask(self: UiMarshaller, priority: DispatcherPriority, task: Task) !void {
        return self.dispatcher.enqueue(priority, task);
    }
};

pub const ChannelDispatcher = struct {
    allocator: std.mem.Allocator,
    high: std.ArrayListUnmanaged(Task) = .empty,
    normal: std.ArrayListUnmanaged(Task) = .empty,
    low: std.ArrayListUnmanaged(Task) = .empty,

    pub fn init(allocator: std.mem.Allocator) ChannelDispatcher {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ChannelDispatcher) void {
        self.cleanupQueue(&self.high);
        self.cleanupQueue(&self.normal);
        self.cleanupQueue(&self.low);
    }

    fn cleanupQueue(self: *ChannelDispatcher, queue: *std.ArrayListUnmanaged(Task)) void {
        for (queue.items) |task| {
            task.cleanup();
        }
        queue.deinit(self.allocator);
    }

    pub fn dispatcher(self: *ChannelDispatcher) SendDispatcher {
        return SendDispatcher.from(self);
    }

    pub fn marshaller(self: *ChannelDispatcher) UiMarshaller {
        return .init(self.dispatcher());
    }

    pub fn enqueue(self: *ChannelDispatcher, priority: DispatcherPriority, task: Task) !void {
        const queue = switch (priority) {
            .high => &self.high,
            .normal => &self.normal,
            .low => &self.low,
        };
        try queue.append(self.allocator, task);
    }

    pub fn drain(self: *ChannelDispatcher) void {
        while (true) {
            if (self.high.items.len > 0) {
                const task = self.high.orderedRemove(0);
                task.invoke();
                task.cleanup();
                continue;
            }
            if (self.normal.items.len > 0) {
                const task = self.normal.orderedRemove(0);
                task.invoke();
                task.cleanup();
                continue;
            }
            if (self.low.items.len > 0) {
                const task = self.low.orderedRemove(0);
                task.invoke();
                task.cleanup();
                continue;
            }
            break;
        }
    }
};

pub const WinUIDispatcher = struct {
    const Error = win_core.hresult.Error || error{
        NoDispatcherQueue,
        EnqueueRejected,
        OutOfMemory,
    };

    queue: *System.DispatcherQueue,
    controller: ?*System.IDispatcherQueueController = null,

    pub fn forCurrentThread() Error!WinUIDispatcher {
        const statics = try System.DispatcherQueue.statics();
        defer statics.deinit();

        const statics_this: *const System.IDispatcherQueueStatics = @ptrCast(@alignCast(statics.ptr));
        var queue: ?*System.DispatcherQueue = null;
        try win_core.hresult.ok(statics_this.GetForCurrentThread(&queue));
        if (queue) |resolved| {
            return .{ .queue = resolved };
        }

        var controller_raw: ?*anyopaque = null;
        try win_core.hresult.ok(CreateDispatcherQueueController(.{
            .dwSize = @sizeOf(DispatcherQueueOptions),
            .threadType = DQTYPE_THREAD_CURRENT,
            .apartmentType = DQTAT_COM_STA,
        }, &controller_raw));
        const controller: *System.IDispatcherQueueController = @ptrCast(@alignCast(controller_raw orelse return error.NoDispatcherQueue));

        try win_core.hresult.ok(controller.get_DispatcherQueue(&queue));
        return .{
            .queue = queue orelse return error.NoDispatcherQueue,
            .controller = controller,
        };
    }

    pub fn deinit(self: *const WinUIDispatcher) void {
        const iface: *const System.IDispatcherQueue = @ptrCast(self.queue);
        _ = iface.Release();
        if (self.controller) |controller| {
            _ = controller.Release();
        }
    }

    pub fn dispatcher(self: *WinUIDispatcher) SendDispatcher {
        return SendDispatcher.from(self);
    }

    pub fn marshaller(self: *WinUIDispatcher) UiMarshaller {
        return .init(self.dispatcher());
    }

    pub fn enqueue(self: *WinUIDispatcher, priority: DispatcherPriority, task: Task) Error!void {
        const Context = struct {
            allocator: std.mem.Allocator,
            task: Task,
        };
        const DispatcherQueueHandlerInvoke = fn (this: *anyopaque) callconv(.winapi) win_core.HRESULT;
        const iid = comptime win_core.GUID.parse("dfa2dc9c-1a2d-4917-98f2-939af1d6e0c8");
        const Delegate = win_core.Delegate(DispatcherQueueHandlerInvoke, iid);

        const context = try std.heap.page_allocator.create(Context);
        errdefer std.heap.page_allocator.destroy(context);
        context.* = .{
            .allocator = std.heap.page_allocator,
            .task = task,
        };

        const Callbacks = struct {
            fn onInvoke(this: *anyopaque) callconv(.winapi) win_core.HRESULT {
                const raw = Delegate.userData(this) orelse return win_core.hresult.S_OK;
                const ctx: *Context = @ptrCast(@alignCast(raw));
                defer ctx.allocator.destroy(ctx);
                ctx.task.invoke();
                ctx.task.cleanup();
                return win_core.hresult.S_OK;
            }
        };

        const handler = try Delegate.create(std.heap.page_allocator, &Callbacks.onInvoke, context);
        var enqueued = false;
        defer {
            const remaining = Delegate.release(handler);
            if (!enqueued and remaining == 0) {
                task.cleanup();
                std.heap.page_allocator.destroy(context);
            }
        }

        const queue_iface: *const System.IDispatcherQueue = @ptrCast(self.queue);
        var accepted: win_core.BOOL = 0;
        try win_core.hresult.ok(queue_iface.TryEnqueue_2(toWinPriority(priority), @ptrCast(@alignCast(handler)), &accepted));
        if (accepted == 0) return error.EnqueueRejected;
        enqueued = true;
    }

    fn toWinPriority(priority: DispatcherPriority) System.DispatcherQueuePriority {
        return switch (priority) {
            .low => .Low,
            .normal => .Normal,
            .high => .High,
        };
    }
};

test "channel dispatcher drains high then normal then low" {
    const Recorder = struct {
        allocator: std.mem.Allocator,
        values: *std.ArrayListUnmanaged(u8),

        fn record(user_data: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(user_data.?));
            self.values.append(self.allocator, 1 + @as(u8, @truncate(self.values.items.len))) catch unreachable;
        }
    };

    var values: std.ArrayListUnmanaged(u8) = .empty;
    defer values.deinit(std.testing.allocator);

    var dispatcher = ChannelDispatcher.init(std.testing.allocator);
    defer dispatcher.deinit();
    const marshaller = dispatcher.marshaller();
    var recorder = Recorder{ .allocator = std.testing.allocator, .values = &values };

    try marshaller.dispatchLow(&recorder, Recorder.record);
    try marshaller.dispatch(&recorder, Recorder.record);
    try marshaller.dispatchTask(.high, .{
        .user_data = &recorder,
        .invoke_fn = Recorder.record,
    });

    dispatcher.drain();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, values.items);
}

test "channel dispatcher preserves fifo order within a priority" {
    const State = struct {
        allocator: std.mem.Allocator,
        values: *std.ArrayListUnmanaged(u8),
        value: u8,

        fn record(user_data: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(user_data.?));
            self.values.append(self.allocator, self.value) catch unreachable;
        }
    };

    var values: std.ArrayListUnmanaged(u8) = .empty;
    defer values.deinit(std.testing.allocator);

    var dispatcher = ChannelDispatcher.init(std.testing.allocator);
    defer dispatcher.deinit();
    const marshaller = dispatcher.marshaller();

    var first = State{ .allocator = std.testing.allocator, .values = &values, .value = 10 };
    var second = State{ .allocator = std.testing.allocator, .values = &values, .value = 20 };
    var third = State{ .allocator = std.testing.allocator, .values = &values, .value = 30 };

    try marshaller.dispatch(&first, State.record);
    try marshaller.dispatch(&second, State.record);
    try marshaller.dispatch(&third, State.record);

    dispatcher.drain();
    try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30 }, values.items);
}
