//! Runtime helpers shared by generated reactor event-connector glue.

const std = @import("std");
const win_core = @import("win-core");

pub const InvokeFn = *const fn (
    this: *const anyopaque,
    sender: ?*const anyopaque,
    args: ?*const anyopaque,
) callconv(.winapi) win_core.HRESULT;

pub fn Connection(comptime Token: type) type {
    return struct {
        token: ?Token = null,

        pub fn isConnected(self: @This()) bool {
            return self.token != null;
        }
    };
}

pub fn connect(
    comptime Token: type,
    comptime iid: win_core.GUID,
    target: anytype,
    allocator: std.mem.Allocator,
    invoke: InvokeFn,
    user_data: ?*anyopaque,
    add_fn: anytype,
) (win_core.hresult.Error || error{OutOfMemory})!Connection(Token) {
    const D = win_core.Delegate(std.meta.Child(@TypeOf(invoke)), iid);
    const handler = try D.create(allocator, invoke, user_data);
    defer _ = D.release(handler);

    const add_info = @typeInfo(@TypeOf(add_fn)).@"fn";
    const delegate_param_ty = add_info.params[1].type orelse
        @compileError("event add helper must accept a typed delegate parameter");

    var token: Token = undefined;
    try win_core.hresult.ok(@call(.auto, add_fn, .{
        target,
        @as(delegate_param_ty, @ptrCast(@alignCast(handler))),
        &token,
    }));
    return .{ .token = token };
}

pub fn disconnect(
    comptime Token: type,
    target: anytype,
    connection: *Connection(Token),
    remove_fn: anytype,
) win_core.hresult.Error!void {
    const token = connection.token orelse return;
    try win_core.hresult.ok(@call(.auto, remove_fn, .{ target, token }));
    connection.token = null;
}

test "connect and disconnect swap handlers without leaking registrations" {
    const TestToken = extern struct {
        Value: i64,
    };
    const EventConnection = Connection(TestToken);
    const test_iid = comptime win_core.GUID.parse("8a34c319-52f8-4b5a-bcf1-623b7fa9d81b");

    const FakeDelegate = opaque {};

    const DelegateView = extern struct {
        vtable: *const Vtbl,

        const Vtbl = extern struct {
            base: win_core.IUnknown_Vtbl,
            Invoke: InvokeFn,
        };
    };

    const Counter = struct {
        fired: usize = 0,
    };

    const FakeSourceState = struct {
        next_token: i64 = 1,
        token: ?TestToken = null,
        handler: ?*anyopaque = null,
    };

    const FakeSource = struct {
        state: *FakeSourceState,

        fn addClicked(self: *@This(), handler: *FakeDelegate, token: *TestToken) callconv(.winapi) win_core.HRESULT {
            if (self.state.handler != null) return win_core.hresult.E_FAIL;

            const raw_handler: *anyopaque = @ptrCast(handler);
            const view: *const DelegateView = @ptrCast(@alignCast(raw_handler));
            _ = view.vtable.base.AddRef(raw_handler);

            token.* = .{ .Value = self.state.next_token };
            self.state.next_token += 1;
            self.state.token = token.*;
            self.state.handler = raw_handler;
            return win_core.hresult.S_OK;
        }

        fn removeClicked(self: *@This(), token: TestToken) callconv(.winapi) win_core.HRESULT {
            const active = self.state.token orelse return win_core.hresult.S_OK;
            if (active.Value != token.Value) return win_core.hresult.E_INVALIDARG;

            const raw_handler = self.state.handler orelse return win_core.hresult.E_FAIL;
            const view: *const DelegateView = @ptrCast(@alignCast(raw_handler));
            _ = view.vtable.base.Release(raw_handler);

            self.state.token = null;
            self.state.handler = null;
            return win_core.hresult.S_OK;
        }

        fn fire(self: *@This()) !void {
            const raw_handler = self.state.handler orelse return;
            const view: *const DelegateView = @ptrCast(@alignCast(raw_handler));
            try win_core.hresult.ok(view.vtable.Invoke(raw_handler, null, null));
        }
    };

    const Callbacks = struct {
        fn onInvoked(this: *const anyopaque, sender: ?*const anyopaque, args: ?*const anyopaque) callconv(.winapi) win_core.HRESULT {
            _ = sender;
            _ = args;

            const D = win_core.Delegate(@TypeOf(onInvoked), test_iid);
            const raw_ctx = D.userData(@constCast(this)) orelse return win_core.hresult.S_OK;
            const counter: *Counter = @ptrCast(@alignCast(raw_ctx));
            counter.fired += 1;
            return win_core.hresult.S_OK;
        }
    };

    var state: FakeSourceState = .{};
    var source: FakeSource = .{ .state = &state };
    var first: Counter = .{};
    var second: Counter = .{};
    var connection: EventConnection = .{};

    connection = try connect(
        TestToken,
        test_iid,
        &source,
        std.testing.allocator,
        Callbacks.onInvoked,
        &first,
        FakeSource.addClicked,
    );
    const first_token = connection.token.?;
    try std.testing.expect(connection.isConnected());

    try source.fire();
    try std.testing.expectEqual(@as(usize, 1), first.fired);
    try std.testing.expectEqual(@as(usize, 0), second.fired);

    try disconnect(TestToken, &source, &connection, FakeSource.removeClicked);
    try std.testing.expect(!connection.isConnected());
    try std.testing.expect(state.handler == null);

    try disconnect(TestToken, &source, &connection, FakeSource.removeClicked);
    try std.testing.expect(state.handler == null);

    try source.fire();
    try std.testing.expectEqual(@as(usize, 1), first.fired);
    try std.testing.expectEqual(@as(usize, 0), second.fired);

    connection = try connect(
        TestToken,
        test_iid,
        &source,
        std.testing.allocator,
        Callbacks.onInvoked,
        &second,
        FakeSource.addClicked,
    );
    const second_token = connection.token.?;
    try std.testing.expect(connection.isConnected());
    try std.testing.expect(first_token.Value != second_token.Value);

    try source.fire();
    try std.testing.expectEqual(@as(usize, 1), first.fired);
    try std.testing.expectEqual(@as(usize, 1), second.fired);

    try disconnect(TestToken, &source, &connection, FakeSource.removeClicked);
    try std.testing.expect(!connection.isConnected());
    try std.testing.expect(state.handler == null);
}
