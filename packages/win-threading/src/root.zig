//! `win-threading` — thin, Zig-idiomatic wrappers over the Win32 thread pool.
//!
//! Mirrors the small `windows-threading` Rust crate: submit work to the
//! shared pool, create private pools with thread limits, and use `scope`
//! to safely submit callbacks that borrow stack-local state.

const std = @import("std");
const win_sys = @import("win-sys");

const ThreadingIndex = win_sys.index.@"Windows.Win32.System.Threading";
const FoundationIndex = win_sys.index.@"Windows.Win32.Foundation";
const TP_CALLBACK_ENVIRON_V3 = win_sys.structs.TP_CALLBACK_ENVIRON_V3;

const win = win_sys.project(.{
    .@"Windows.Win32.System.Threading" = .{
        "CreateThreadpool",
        "CreateThreadpoolCleanupGroup",
        "SetThreadpoolThreadMaximum",
        "SetThreadpoolThreadMinimum",
        "CloseThreadpool",
        "CloseThreadpoolCleanupGroup",
        "CloseThreadpoolCleanupGroupMembers",
        "TrySubmitThreadpoolCallback",
        "GetCurrentThreadId",
        "Sleep",
    },
});

const test_win = win_sys.project(.{
    .@"Windows.Win32.Foundation" = .{"CloseHandle"},
    .@"Windows.Win32.System.Threading" = .{
        "CreateEventW",
        "SetEvent",
        "WaitForSingleObject",
    },
});

const task_allocator = std.heap.smp_allocator;

pub const Error = error{OutOfMemory};

const TaskHeader = struct {
    run: *const fn (*TaskHeader) void,
};

fn TaskEntry(comptime Context: type, comptime callback: anytype) type {
    return struct {
        const Self = @This();

        header: TaskHeader = .{ .run = run },
        context: Context,

        fn run(header: *TaskHeader) void {
            const self: *Self = @fieldParentPtr("header", header);
            defer task_allocator.destroy(self);
            callback(self.context);
        }
    };
}

fn threadpoolCallback(_: ?*anyopaque, raw_context: ?*anyopaque) callconv(.winapi) void {
    const header: *TaskHeader = @ptrCast(@alignCast(raw_context orelse unreachable));
    header.run(header);
}

fn requireNonZero(result: anytype) Error!@TypeOf(result) {
    if (result == 0) return error.OutOfMemory;
    return result;
}

fn submitWithEnvironment(
    environment: ?*TP_CALLBACK_ENVIRON_V3,
    context: anytype,
    comptime callback: anytype,
) Error!void {
    const Entry = TaskEntry(@TypeOf(context), callback);
    const entry = try task_allocator.create(Entry);
    errdefer task_allocator.destroy(entry);
    entry.* = .{ .context = context };

    _ = try requireNonZero(win.TrySubmitThreadpoolCallback(
        @ptrCast(&threadpoolCallback),
        @ptrCast(entry),
        environment,
    ));
}

fn callScopeBodyWithInfo(
    comptime body: anytype,
    comptime fn_info: std.builtin.Type.Fn,
    scope: *Scope,
    context: anytype,
) !void {
    const Return = fn_info.return_type orelse void;
    switch (@typeInfo(Return)) {
        .void => body(scope, context),
        .error_union => try body(scope, context),
        else => @compileError("win-threading: scope body must return void or !void"),
    }
}

fn callScopeBody(comptime body: anytype, scope: *Scope, context: anytype) !void {
    switch (@typeInfo(@TypeOf(body))) {
        .@"fn" => |fn_info| try callScopeBodyWithInfo(body, fn_info, scope, context),
        .pointer => |ptr_info| switch (@typeInfo(ptr_info.child)) {
            .@"fn" => |fn_info| try callScopeBodyWithInfo(body, fn_info, scope, context),
            else => @compileError("win-threading: scope body must be a function"),
        },
        else => @compileError("win-threading: scope body must be a function"),
    }
}

/// Submit a callback to the default Win32 thread pool.
///
/// Any pointers reachable from `context` must remain valid until the
/// callback runs. Use `Pool.scope` when borrowing stack-local state.
pub fn submit(context: anytype, comptime callback: anytype) Error!void {
    try submitWithEnvironment(null, context, callback);
}

/// Call `callback(context, item)` for every value in `values`, waiting for all
/// work to finish before returning. Supports anything Zig's `for` can iterate.
pub fn forEach(values: anytype, context: anytype, comptime callback: anytype) !void {
    const State = struct {
        values: @TypeOf(values),
        context: @TypeOf(context),
    };

    var work_state = State{
        .values = values,
        .context = context,
    };

    try Pool.withScope(&work_state, struct {
        fn run(scope: *Scope, for_each_state: *State) !void {
            for (for_each_state.values) |item| {
                const Work = struct {
                    context: @TypeOf(for_each_state.context),
                    item: @TypeOf(item),
                };

                try scope.submit(
                    Work{
                        .context = for_each_state.context,
                        .item = item,
                    },
                    struct {
                        fn call(work: Work) void {
                            callback(work.context, work.item);
                        }
                    }.call,
                );
            }
        }
    }.run);
}

/// The thread identifier of the calling thread.
pub fn threadId() u32 {
    return win.GetCurrentThreadId();
}

/// Suspend the calling thread for `milliseconds`.
pub fn sleep(milliseconds: u32) void {
    win.Sleep(milliseconds);
}

const PoolState = struct {
    environment: TP_CALLBACK_ENVIRON_V3,
};

/// A private Win32 thread pool with its own thread limits and cleanup group.
pub const Pool = struct {
    state: ?*PoolState,

    pub fn init() Error!Pool {
        const state = try task_allocator.create(PoolState);
        errdefer task_allocator.destroy(state);

        state.* = .{
            .environment = std.mem.zeroes(TP_CALLBACK_ENVIRON_V3),
        };
        state.environment.Version = 3;
        state.environment.CallbackPriority = ThreadingIndex.TP_CALLBACK_PRIORITY_NORMAL;
        state.environment.Size = @sizeOf(TP_CALLBACK_ENVIRON_V3);
        state.environment.Pool.Value = try requireNonZero(win.CreateThreadpool(null));
        errdefer win.CloseThreadpool(state.environment.Pool.Value);

        state.environment.CleanupGroup.Value =
            try requireNonZero(win.CreateThreadpoolCleanupGroup());
        errdefer win.CloseThreadpoolCleanupGroup(state.environment.CleanupGroup.Value);

        return .{ .state = state };
    }

    pub fn new() Error!Pool {
        return init();
    }

    pub fn deinit(self: *Pool) void {
        const state = self.state orelse return;
        self.join();
        win.CloseThreadpoolCleanupGroup(state.environment.CleanupGroup.Value);
        win.CloseThreadpool(state.environment.Pool.Value);
        task_allocator.destroy(state);
        self.state = null;
    }

    fn statePtr(self: *const Pool) *PoolState {
        return self.state orelse @panic("win-threading: pool used after deinit");
    }

    fn environment(self: *Pool) *TP_CALLBACK_ENVIRON_V3 {
        return &self.statePtr().environment;
    }

    /// Set the minimum and maximum number of threads for the pool.
    pub fn setThreadLimits(self: *const Pool, min: u32, max: u32) Error!void {
        const state = self.statePtr();
        _ = try requireNonZero(win.SetThreadpoolThreadMinimum(state.environment.Pool.Value, min));
        win.SetThreadpoolThreadMaximum(state.environment.Pool.Value, max);
    }

    /// Submit a callback to this pool.
    ///
    /// Any pointers reachable from `context` must outlive the callback. Use
    /// `scope` for stack-local borrows.
    pub fn submit(self: *Pool, context: anytype, comptime callback: anytype) Error!void {
        try submitWithEnvironment(self.environment(), context, callback);
    }

    /// Create a scope that waits for all submitted callbacks before returning.
    pub fn scope(self: *Pool, context: anytype, comptime body: anytype) !void {
        defer self.join();

        var scoped = Scope{ .pool = self };
        try callScopeBody(body, &scoped, context);
    }

    /// Convenience helper: create a pool, run `body`, then wait and clean up.
    pub fn withScope(context: anytype, comptime body: anytype) !void {
        var pool = try Pool.init();
        defer pool.deinit();
        try pool.scope(context, body);
    }

    /// Wait for all callbacks currently associated with the pool to finish.
    pub fn join(self: *const Pool) void {
        const state = self.statePtr();
        win.CloseThreadpoolCleanupGroupMembers(state.environment.CleanupGroup.Value, 0, null);
    }
};

/// A scope that allows borrowing local state while submitting to a pool.
pub const Scope = struct {
    pool: *Pool,

    pub fn submit(self: *Scope, context: anytype, comptime callback: anytype) Error!void {
        try self.pool.submit(context, callback);
    }

    pub fn setThreadLimits(self: *Scope, min: u32, max: u32) Error!void {
        try self.pool.setThreadLimits(min, max);
    }

    pub fn join(self: *Scope) void {
        self.pool.join();
    }
};

test "submit runs callback on the shared thread pool" {
    const event = test_win.CreateEventW(null, 1, 0, null);
    try std.testing.expect(event != null);
    defer _ = test_win.CloseHandle(event);

    try submit(event, struct {
        fn run(handle: ?*anyopaque) void {
            std.debug.assert(test_win.SetEvent(handle) != 0);
        }
    }.run);

    try std.testing.expectEqual(
        @as(u32, FoundationIndex.WAIT_OBJECT_0),
        test_win.WaitForSingleObject(event, 5_000),
    );
}

test "Pool.scope waits for stack-backed callbacks" {
    var pool = try Pool.init();
    defer pool.deinit();
    try pool.setThreadLimits(1, 1);

    var thread_ids = [_]u32{0} ** 4;
    try pool.scope(&thread_ids, struct {
        fn run(scope: *Scope, slots: *[4]u32) !void {
            var i: usize = 0;
            while (i < slots.len) : (i += 1) {
                try scope.submit(&slots[i], struct {
                    fn call(slot: *u32) void {
                        slot.* = threadId();
                        sleep(10);
                    }
                }.call);
            }
        }
    }.run);

    const first = thread_ids[0];
    try std.testing.expect(first != 0);
    for (thread_ids[1..]) |tid| {
        try std.testing.expectEqual(first, tid);
    }
}

test "forEach waits for all items" {
    var total = std.atomic.Value(u32).init(0);
    const values = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    try forEach(values[0..], &total, struct {
        fn run(sum: *std.atomic.Value(u32), item: u32) void {
            _ = sum.fetchAdd(item, .acq_rel);
        }
    }.run);

    try std.testing.expectEqual(@as(u32, 45), total.load(.acquire));
}
