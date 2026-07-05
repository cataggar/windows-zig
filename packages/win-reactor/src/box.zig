const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub fn maybeDeinitValue(comptime T: type, allocator: Allocator, value: *T) void {
    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => return,
    }
    if (!@hasDecl(T, "deinit")) return;

    const deinit_fn = T.deinit;
    const fn_info = @typeInfo(@TypeOf(deinit_fn)).@"fn";
    switch (fn_info.params.len) {
        1 => value.deinit(),
        2 => value.deinit(allocator),
        else => @compileError("unsupported deinit signature for " ++ @typeName(T)),
    }
}

pub fn replaceValue(comptime T: type, allocator: Allocator, slot: *T, value: T) void {
    maybeDeinitValue(T, allocator, slot);
    slot.* = value;
}

pub fn valueOwnsResources(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => false,
        .optional => |info| valueOwnsResources(info.child),
        .array => |info| valueOwnsResources(info.child),
        .vector => |info| valueOwnsResources(info.child),
        .error_union => |info| valueOwnsResources(info.payload),
        .@"struct" => |info| blk: {
            if (@hasDecl(T, "deinit")) break :blk true;
            inline for (info.fields) |field| {
                if (valueOwnsResources(field.type)) break :blk true;
            }
            break :blk false;
        },
        .@"union" => |info| blk: {
            if (@hasDecl(T, "deinit")) break :blk true;
            inline for (info.fields) |field| {
                if (valueOwnsResources(field.type)) break :blk true;
            }
            break :blk false;
        },
        .@"enum", .@"opaque" => @hasDecl(T, "deinit"),
        else => false,
    };
}

pub fn assertBorrowedValueType(comptime T: type, comptime usage: []const u8) void {
    if (valueOwnsResources(T)) {
        @compileError(
            usage ++ " requires copy-safe value types; store owned resources behind pointers " ++
                "or inside useRef instead (" ++ @typeName(T) ++ ")",
        );
    }
}

pub const AnyBox = struct {
    ptr: *anyopaque,
    ops: *const Ops,

    const Ops = struct {
        type_name: []const u8,
        destroy: *const fn (allocator: Allocator, ptr: *anyopaque) void,
        replace: *const fn (allocator: Allocator, ptr: *anyopaque, value: *const anyopaque) void,
    };

    pub fn init(allocator: Allocator, value: anytype) Allocator.Error!AnyBox {
        const T = @TypeOf(value);
        const boxed = try allocator.create(T);
        boxed.* = value;
        return .{
            .ptr = @ptrCast(boxed),
            .ops = opsFor(T),
        };
    }

    pub fn deinit(self: *AnyBox, allocator: Allocator) void {
        self.ops.destroy(allocator, self.ptr);
        self.* = undefined;
    }

    pub fn is(self: AnyBox, comptime T: type) bool {
        return self.ops == opsFor(T);
    }

    pub fn get(self: AnyBox, comptime T: type) *T {
        std.debug.assert(self.is(T));
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn getConst(self: AnyBox, comptime T: type) *const T {
        std.debug.assert(self.is(T));
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn replace(self: *AnyBox, allocator: Allocator, value: anytype) void {
        const T = @TypeOf(value);
        std.debug.assert(self.is(T));
        var tmp = value;
        self.ops.replace(allocator, self.ptr, @ptrCast(&tmp));
    }

    pub fn typeName(self: AnyBox) []const u8 {
        return self.ops.type_name;
    }

    fn opsFor(comptime T: type) *const Ops {
        return &struct {
            fn destroy(allocator: Allocator, raw: *anyopaque) void {
                const typed: *T = @ptrCast(@alignCast(raw));
                maybeDeinitValue(T, allocator, typed);
                allocator.destroy(typed);
            }

            fn replaceFn(allocator: Allocator, raw: *anyopaque, raw_value: *const anyopaque) void {
                const typed: *T = @ptrCast(@alignCast(raw));
                const next: *const T = @ptrCast(@alignCast(raw_value));
                replaceValue(T, allocator, typed, next.*);
            }

            const value = Ops{
                .type_name = @typeName(T),
                .destroy = destroy,
                .replace = replaceFn,
            };
        }.value;
    }
};

pub const EqBox = struct {
    inner: AnyBox,
    eql_fn: *const fn (lhs: *const anyopaque, rhs: *const anyopaque) bool,

    pub fn init(allocator: Allocator, value: anytype) Allocator.Error!EqBox {
        const T = @TypeOf(value);
        return .{
            .inner = try AnyBox.init(allocator, value),
            .eql_fn = eqlFn(T),
        };
    }

    pub fn deinit(self: *EqBox, allocator: Allocator) void {
        self.inner.deinit(allocator);
        self.* = undefined;
    }

    pub fn is(self: EqBox, comptime T: type) bool {
        return self.inner.is(T);
    }

    pub fn eqlValue(self: *const EqBox, value: anytype) bool {
        const T = @TypeOf(value);
        if (!self.is(T)) return false;
        var tmp = value;
        return self.eql_fn(self.inner.ptr, @ptrCast(&tmp));
    }

    pub fn eqlBox(self: *const EqBox, other: *const EqBox) bool {
        if (self.eql_fn != other.eql_fn) return false;
        return self.eql_fn(self.inner.ptr, other.inner.ptr);
    }

    pub fn typeName(self: EqBox) []const u8 {
        return self.inner.typeName();
    }

    fn eqlFn(comptime T: type) *const fn (lhs: *const anyopaque, rhs: *const anyopaque) bool {
        return &struct {
            fn call(lhs_raw: *const anyopaque, rhs_raw: *const anyopaque) bool {
                const lhs: *const T = @ptrCast(@alignCast(lhs_raw));
                const rhs: *const T = @ptrCast(@alignCast(rhs_raw));
                return std.meta.eql(lhs.*, rhs.*);
            }
        }.call;
    }
};

/// Cloneable/equatable boxed value for copy-safe data carried through the
/// element tree (generic props, component props, provider values). Like the
/// hook-state contract, callers should keep owned resources behind pointers
/// and pass only copy-safe values by value here.
pub const ValueBox = struct {
    inner: AnyBox,
    eql_fn: *const fn (lhs: *const anyopaque, rhs: *const anyopaque) bool,
    clone_fn: *const fn (allocator: Allocator, source: *const anyopaque) Allocator.Error!AnyBox,

    pub fn init(allocator: Allocator, value: anytype) Allocator.Error!ValueBox {
        const T = @TypeOf(value);
        comptime assertBorrowedValueType(T, "ValueBox.init");
        return .{
            .inner = try AnyBox.init(allocator, value),
            .eql_fn = EqBox.eqlFn(T),
            .clone_fn = cloneFn(T),
        };
    }

    pub fn deinit(self: *ValueBox, allocator: Allocator) void {
        self.inner.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: *const ValueBox, allocator: Allocator) Allocator.Error!ValueBox {
        return .{
            .inner = try self.clone_fn(allocator, self.inner.ptr),
            .eql_fn = self.eql_fn,
            .clone_fn = self.clone_fn,
        };
    }

    pub fn is(self: ValueBox, comptime T: type) bool {
        return self.inner.is(T);
    }

    pub fn get(self: ValueBox, comptime T: type) *T {
        return self.inner.get(T);
    }

    pub fn getConst(self: ValueBox, comptime T: type) *const T {
        return self.inner.getConst(T);
    }

    pub fn eqlValue(self: *const ValueBox, value: anytype) bool {
        const T = @TypeOf(value);
        if (!self.is(T)) return false;
        var tmp = value;
        return self.eql_fn(self.inner.ptr, @ptrCast(&tmp));
    }

    pub fn eqlBox(self: *const ValueBox, other: *const ValueBox) bool {
        if (self.eql_fn != other.eql_fn) return false;
        return self.eql_fn(self.inner.ptr, other.inner.ptr);
    }

    pub fn typeName(self: ValueBox) []const u8 {
        return self.inner.typeName();
    }

    pub fn rawConstPtr(self: *const ValueBox) *const anyopaque {
        return self.inner.ptr;
    }

    fn cloneFn(comptime T: type) *const fn (allocator: Allocator, source: *const anyopaque) Allocator.Error!AnyBox {
        return &struct {
            fn call(allocator: Allocator, source_raw: *const anyopaque) Allocator.Error!AnyBox {
                const source: *const T = @ptrCast(@alignCast(source_raw));
                return AnyBox.init(allocator, source.*);
            }
        }.call;
    }
};
