const std = @import("std");
const box = @import("box.zig");

pub const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{
    ContextTypeMismatch,
};

var next_context_id = std.atomic.Value(u32).init(1);

pub const ContextId = struct {
    raw: u32,

    pub fn init() ContextId {
        return .{ .raw = next_context_id.fetchAdd(1, .seq_cst) };
    }
};

pub fn Context(comptime T: type) type {
    return struct {
        default: T,
        id: ContextId,

        pub fn init(default: T) @This() {
            return .{
                .default = default,
                .id = ContextId.init(),
            };
        }
    };
}

const ContextEntry = struct {
    context_id: ContextId,
    value: box.ValueBox,
};

/// Minimal provider stack that issue #13's `Element` tree can push/pop
/// while descending into provider nodes. `RenderCx.useContext` only needs
/// this interface; no reconciler or tree types are required here.
pub const ContextStack = struct {
    allocator: Allocator,
    entries: std.ArrayListUnmanaged(ContextEntry) = .empty,

    pub fn init(allocator: Allocator) ContextStack {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContextStack) void {
        while (self.entries.items.len > 0) {
            self.popOne();
        }
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn push(self: *ContextStack, comptime T: type, context: *const Context(T), value: T) Error!ContextScope {
        comptime box.assertBorrowedValueType(T, "ContextStack.push");

        var stored = try box.ValueBox.init(self.allocator, value);
        errdefer stored.deinit(self.allocator);

        try self.entries.append(self.allocator, .{
            .context_id = context.id,
            .value = stored,
        });

        return .{ .stack = self };
    }

    pub fn pushBox(self: *ContextStack, context_id: ContextId, value: *const box.ValueBox) Error!void {
        var stored = try value.clone(self.allocator);
        errdefer stored.deinit(self.allocator);

        try self.entries.append(self.allocator, .{
            .context_id = context_id,
            .value = stored,
        });
    }

    pub fn mark(self: *const ContextStack) usize {
        return self.entries.items.len;
    }

    pub fn popToMark(self: *ContextStack, stack_mark: usize) void {
        while (self.entries.items.len > stack_mark) {
            self.popOne();
        }
    }

    pub fn get(self: *const ContextStack, comptime T: type, context: *const Context(T)) Error!?T {
        comptime box.assertBorrowedValueType(T, "ContextStack.get");

        var index = self.entries.items.len;
        while (index > 0) : (index -= 1) {
            const entry = &self.entries.items[index - 1];
            if (entry.context_id.raw != context.id.raw) continue;
            if (!entry.value.is(T)) return error.ContextTypeMismatch;
            return entry.value.getConst(T).*;
        }
        return null;
    }

    fn popOne(self: *ContextStack) void {
        std.debug.assert(self.entries.items.len > 0);
        const index = self.entries.items.len - 1;
        var entry = self.entries.items[index];
        entry.value.deinit(self.allocator);
        self.entries.items.len = index;
    }
};

pub const ContextScope = struct {
    stack: *ContextStack,

    pub fn deinit(self: *ContextScope) void {
        self.stack.popOne();
    }
};

test "context stack returns default-like shadowing order" {
    const ThemeContext = Context([]const u8);
    var stack = ContextStack.init(std.testing.allocator);
    defer stack.deinit();

    const theme = ThemeContext.init("light");
    try std.testing.expect(try stack.get([]const u8, &theme) == null);

    var outer = try stack.push([]const u8, &theme, "dark");
    defer outer.deinit();
    try std.testing.expectEqualStrings("dark", (try stack.get([]const u8, &theme)).?);

    var inner = try stack.push([]const u8, &theme, "high-contrast");
    defer inner.deinit();
    try std.testing.expectEqualStrings("high-contrast", (try stack.get([]const u8, &theme)).?);
}

test "context stack can clone boxed provider values to a mark" {
    const ThemeContext = Context([]const u8);
    const theme = ThemeContext.init("light");

    var stack = ContextStack.init(std.testing.allocator);
    defer stack.deinit();

    var boxed = try box.ValueBox.init(std.testing.allocator, @as([]const u8, "dark"));
    defer boxed.deinit(std.testing.allocator);

    const mark = stack.mark();
    try stack.pushBox(theme.id, &boxed);
    try std.testing.expectEqualStrings("dark", (try stack.get([]const u8, &theme)).?);
    stack.popToMark(mark);
    try std.testing.expect(try stack.get([]const u8, &theme) == null);
}
