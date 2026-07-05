//! `win-reference` — stock `IReference<T>` / `IPropertyValue` boxing for
//! primitive WinRT values.

const std = @import("std");
const win_core = @import("win-core");
const foundation = @import("foundation.zig");

pub const PropertyType = foundation.PropertyType;

extern "ole32" fn CoTaskMemAlloc(cb: usize) callconv(.winapi) ?*anyopaque;
extern "ole32" fn CoTaskMemFree(ptr: ?*anyopaque) callconv(.winapi) void;

pub fn box(value: anytype) !IReference(@TypeOf(value)) {
    return IReference(@TypeOf(value)).from(value);
}

pub fn unbox(comptime T: type, inspectable: win_core.IInspectable) !T {
    const reference = try IReference(T).fromInspectable(inspectable);
    defer reference.deinit();
    return reference.value();
}

pub const BoxedValue = struct {
    ptr: *const foundation.IPropertyValue,

    pub fn fromRaw(raw_ptr: *const foundation.IPropertyValue) BoxedValue {
        return .{ .ptr = raw_ptr };
    }

    pub fn fromInspectable(inspectable: win_core.IInspectable) !BoxedValue {
        var raw_ptr: ?*anyopaque = null;
        try win_core.hresult.ok(inspectable.queryInterface(&foundation.IPropertyValue.IID, &raw_ptr));
        return .{ .ptr = @ptrCast(@alignCast(raw_ptr.?)) };
    }

    pub fn clone(self: BoxedValue) BoxedValue {
        _ = self.addRef();
        return self;
    }

    pub fn deinit(self: BoxedValue) void {
        _ = self.release();
    }

    pub fn addRef(self: BoxedValue) u32 {
        return self.ptr.vtable.base.base.AddRef(@ptrCast(@constCast(self.ptr)));
    }

    pub fn release(self: BoxedValue) u32 {
        return self.ptr.vtable.base.base.Release(@ptrCast(@constCast(self.ptr)));
    }

    pub fn getType(self: BoxedValue) !PropertyType {
        var result: PropertyType = undefined;
        try win_core.hresult.ok(self.ptr.vtable.get_Type(self.ptr, &result));
        return result;
    }

    pub fn isNumericScalar(self: BoxedValue) !bool {
        var result: win_core.BOOL = 0;
        try win_core.hresult.ok(self.ptr.vtable.get_IsNumericScalar(self.ptr, &result));
        return win_core.boolFromWin32(result);
    }

    pub fn get(self: BoxedValue, comptime T: type) !T {
        const Info = ReferenceInfo(T);
        var result: Info.Abi = undefined;
        try win_core.hresult.ok(Info.getPropertyValue(self.ptr, &result));
        return Info.fromAbi(result);
    }

    pub fn raw(self: BoxedValue) *const foundation.IPropertyValue {
        return self.ptr;
    }
};

pub fn IReference(comptime T: type) type {
    const Info = ReferenceInfo(T);
    return struct {
        const Self = @This();

        ptr: *const Info.Iface,

        pub const Abi = Info.Abi;
        pub const Iface = Info.Iface;
        pub const IID = Iface.IID;
        pub const property_type = Info.property_type;
        pub const is_numeric_scalar = Info.is_numeric;

        pub fn from(input: T) !Self {
            return .{ .ptr = try ReferenceImplementation(T).create(input) };
        }

        pub fn fromRaw(raw_ptr: *const Iface) Self {
            return .{ .ptr = raw_ptr };
        }

        pub fn fromInspectable(inspectable: win_core.IInspectable) !Self {
            var raw_ptr: ?*anyopaque = null;
            try win_core.hresult.ok(inspectable.queryInterface(&IID, &raw_ptr));
            return .{ .ptr = @ptrCast(@alignCast(raw_ptr.?)) };
        }

        pub fn clone(self: Self) Self {
            _ = self.addRef();
            return self;
        }

        pub fn deinit(self: Self) void {
            _ = self.release();
        }

        pub fn addRef(self: Self) u32 {
            return self.ptr.vtable.base.base.AddRef(@ptrCast(@constCast(self.ptr)));
        }

        pub fn release(self: Self) u32 {
            return self.ptr.vtable.base.base.Release(@ptrCast(@constCast(self.ptr)));
        }

        pub fn value(self: Self) !T {
            var result: Abi = undefined;
            try win_core.hresult.ok(self.ptr.vtable.get_Value(self.ptr, &result));
            return Info.fromAbi(result);
        }

        pub fn asInspectable(self: Self) win_core.IInspectable {
            _ = self.addRef();
            return .{ .ptr = @ptrCast(@alignCast(@constCast(self.ptr))) };
        }

        pub fn boxedValue(self: Self) !BoxedValue {
            var raw_ptr: ?*anyopaque = null;
            try win_core.hresult.ok(self.ptr.vtable.base.base.QueryInterface(
                @ptrCast(@constCast(self.ptr)),
                &foundation.IPropertyValue.IID,
                &raw_ptr,
            ));
            return .{ .ptr = @ptrCast(@alignCast(raw_ptr.?)) };
        }

        pub fn raw(self: Self) *const Iface {
            return self.ptr;
        }

        pub fn asAnyOpaque(self: Self) *const anyopaque {
            return @ptrCast(self.ptr);
        }
    };
}

fn identity(comptime T: type) fn (T) T {
    return struct {
        fn impl(value: T) T {
            return value;
        }
    }.impl;
}

fn boolToAbi(value: bool) win_core.BOOL {
    return win_core.boolToWin32(value);
}

fn boolFromAbi(value: win_core.BOOL) bool {
    return win_core.boolFromWin32(value);
}

fn referenceInfo(
    comptime Public: type,
    comptime AbiType: type,
    comptime IfaceType: type,
    comptime property_type_value: PropertyType,
    comptime numeric_scalar: bool,
    comptime getter_name: []const u8,
    comptime to_abi: fn (Public) AbiType,
    comptime from_abi: fn (AbiType) Public,
) type {
    return struct {
        pub const Abi = AbiType;
        pub const Iface = IfaceType;
        pub const property_type = property_type_value;
        pub const is_numeric = numeric_scalar;

        pub inline fn toAbi(value: Public) AbiType {
            return to_abi(value);
        }

        pub inline fn fromAbi(value: AbiType) Public {
            return from_abi(value);
        }

        pub fn getPropertyValue(
            prop: *const foundation.IPropertyValue,
            result: *AbiType,
        ) callconv(.winapi) win_core.HRESULT {
            return @field(prop.vtable.*, getter_name)(prop, result);
        }
    };
}

fn ReferenceInfo(comptime T: type) type {
    if (T == bool) {
        return referenceInfo(
            bool,
            win_core.BOOL,
            foundation.IReference__G1__BOOL,
            .Boolean,
            false,
            "GetBoolean",
            boolToAbi,
            boolFromAbi,
        );
    }
    if (T == u8) return referenceInfo(u8, u8, foundation.IReference__G1__u8, .UInt8, true, "GetUInt8", identity(u8), identity(u8));
    if (T == i16) return referenceInfo(i16, i16, foundation.IReference__G1__i16, .Int16, true, "GetInt16", identity(i16), identity(i16));
    if (T == u16) return referenceInfo(u16, u16, foundation.IReference__G1__u16, .UInt16, true, "GetUInt16", identity(u16), identity(u16));
    if (T == i32) return referenceInfo(i32, i32, foundation.IReference__G1__i32, .Int32, true, "GetInt32", identity(i32), identity(i32));
    if (T == u32) return referenceInfo(u32, u32, foundation.IReference__G1__u32, .UInt32, true, "GetUInt32", identity(u32), identity(u32));
    if (T == i64) return referenceInfo(i64, i64, foundation.IReference__G1__i64, .Int64, true, "GetInt64", identity(i64), identity(i64));
    if (T == u64) return referenceInfo(u64, u64, foundation.IReference__G1__u64, .UInt64, true, "GetUInt64", identity(u64), identity(u64));
    if (T == f32) return referenceInfo(f32, f32, foundation.IReference__G1__f32, .Single, true, "GetSingle", identity(f32), identity(f32));
    if (T == f64) return referenceInfo(f64, f64, foundation.IReference__G1__f64, .Double, true, "GetDouble", identity(f64), identity(f64));

    @compileError("win-reference supports bool, u8, i16, u16, i32, u32, i64, u64, f32, and f64");
}

fn ReferenceImplementation(comptime T: type) type {
    const Info = ReferenceInfo(T);

    return struct {
        const RefIface = extern struct {
            vtable: *const Info.Iface.Vtbl,
            state: *anyopaque,
        };

        const PropIface = extern struct {
            vtable: *const foundation.IPropertyValue.Vtbl,
            state: *anyopaque,
        };

        const InterfaceBase = extern struct {
            vtable: *const anyopaque,
            state: *anyopaque,
        };

        const State = struct {
            refcount: u32,
            value: T,
            reference_iface: RefIface,
            property_value_iface: PropIface,
        };

        const reference_vtbl: Info.Iface.Vtbl = .{
            .base = .{
                .base = .{
                    .QueryInterface = queryInterface,
                    .AddRef = addRef,
                    .Release = release,
                },
                .GetIids = getIids,
                .GetRuntimeClassName = getRuntimeClassName,
                .GetTrustLevel = getTrustLevel,
            },
            .get_Value = getValue,
        };

        const property_value_vtbl: foundation.IPropertyValue.Vtbl = .{
            .base = .{
                .base = .{
                    .QueryInterface = queryInterface,
                    .AddRef = addRef,
                    .Release = release,
                },
                .GetIids = getIids,
                .GetRuntimeClassName = getRuntimeClassName,
                .GetTrustLevel = getTrustLevel,
            },
            .get_Type = getType,
            .get_IsNumericScalar = getIsNumericScalar,
            .GetUInt8 = typedGetterFn(u8, .UInt8),
            .GetInt16 = typedGetterFn(i16, .Int16),
            .GetUInt16 = typedGetterFn(u16, .UInt16),
            .GetInt32 = typedGetterFn(i32, .Int32),
            .GetUInt32 = typedGetterFn(u32, .UInt32),
            .GetInt64 = typedGetterFn(i64, .Int64),
            .GetUInt64 = typedGetterFn(u64, .UInt64),
            .GetSingle = typedGetterFn(f32, .Single),
            .GetDouble = typedGetterFn(f64, .Double),
            .GetChar16 = typedGetterFn(u16, .Char16),
            .GetBoolean = typedGetterFn(win_core.BOOL, .Boolean),
            .GetString = typedGetterFn(win_core.HSTRING, .String),
            .GetGuid = typedGetterFn(win_core.GUID, .Guid),
            .GetDateTime = typedGetterFn(foundation.DateTime, .DateTime),
            .GetTimeSpan = typedGetterFn(foundation.TimeSpan, .TimeSpan),
            .GetPoint = typedGetterFn(foundation.Point, .Point),
            .GetSize = typedGetterFn(foundation.Size, .Size),
            .GetRect = typedGetterFn(foundation.Rect, .Rect),
            .GetUInt8Array = notImplementedArrayFn(u8),
            .GetInt16Array = notImplementedArrayFn(i16),
            .GetUInt16Array = notImplementedArrayFn(u16),
            .GetInt32Array = notImplementedArrayFn(i32),
            .GetUInt32Array = notImplementedArrayFn(u32),
            .GetInt64Array = notImplementedArrayFn(i64),
            .GetUInt64Array = notImplementedArrayFn(u64),
            .GetSingleArray = notImplementedArrayFn(f32),
            .GetDoubleArray = notImplementedArrayFn(f64),
            .GetChar16Array = notImplementedArrayFn(u16),
            .GetBooleanArray = notImplementedArrayFn(win_core.BOOL),
            .GetStringArray = notImplementedArrayFn(win_core.HSTRING),
            .GetInspectableArray = notImplementedArrayFn(?*const anyopaque),
            .GetGuidArray = notImplementedArrayFn(win_core.GUID),
            .GetDateTimeArray = notImplementedArrayFn(foundation.DateTime),
            .GetTimeSpanArray = notImplementedArrayFn(foundation.TimeSpan),
            .GetPointArray = notImplementedArrayFn(foundation.Point),
            .GetSizeArray = notImplementedArrayFn(foundation.Size),
            .GetRectArray = notImplementedArrayFn(foundation.Rect),
        };

        pub fn create(value: T) !*const Info.Iface {
            const state = try std.heap.page_allocator.create(State);
            state.* = .{
                .refcount = 1,
                .value = value,
                .reference_iface = undefined,
                .property_value_iface = undefined,
            };
            state.reference_iface = .{
                .vtable = &reference_vtbl,
                .state = @ptrCast(state),
            };
            state.property_value_iface = .{
                .vtable = &property_value_vtbl,
                .state = @ptrCast(state),
            };
            return @ptrCast(&state.reference_iface);
        }

        fn stateFromAny(this: *anyopaque) *State {
            const base: *InterfaceBase = @ptrCast(@alignCast(this));
            return @ptrCast(@alignCast(base.state));
        }

        fn stateFromReference(this: *const Info.Iface) *State {
            const iface: *const RefIface = @ptrCast(@alignCast(this));
            return @ptrCast(@alignCast(iface.state));
        }

        fn stateFromPropertyValue(this: *const foundation.IPropertyValue) *State {
            const iface: *const PropIface = @ptrCast(@alignCast(this));
            return @ptrCast(@alignCast(iface.state));
        }

        fn queryInterface(
            this: *anyopaque,
            riid: *const win_core.GUID,
            out: *?*anyopaque,
        ) callconv(.winapi) win_core.HRESULT {
            const state = stateFromAny(this);

            if (std.meta.eql(riid.*, win_core.IID_IUnknown) or
                std.meta.eql(riid.*, win_core.IID_IInspectable) or
                std.meta.eql(riid.*, Info.Iface.IID))
            {
                _ = addRef(this);
                out.* = @ptrCast(&state.reference_iface);
                return win_core.hresult.S_OK;
            }

            if (std.meta.eql(riid.*, foundation.IPropertyValue.IID)) {
                _ = addRef(this);
                out.* = @ptrCast(&state.property_value_iface);
                return win_core.hresult.S_OK;
            }

            out.* = null;
            return win_core.hresult.E_NOINTERFACE;
        }

        fn addRef(this: *anyopaque) callconv(.winapi) u32 {
            const state = stateFromAny(this);
            return @atomicRmw(u32, &state.refcount, .Add, 1, .acq_rel) + 1;
        }

        fn release(this: *anyopaque) callconv(.winapi) u32 {
            const state = stateFromAny(this);
            const prev = @atomicRmw(u32, &state.refcount, .Sub, 1, .acq_rel);
            if (prev == 1) {
                std.heap.page_allocator.destroy(state);
                return 0;
            }
            return prev - 1;
        }

        fn getIids(
            _: *anyopaque,
            count: *u32,
            values: *?[*]win_core.GUID,
        ) callconv(.winapi) win_core.HRESULT {
            const raw = CoTaskMemAlloc(2 * @sizeOf(win_core.GUID)) orelse {
                count.* = 0;
                values.* = null;
                return win_core.hresult.E_OUTOFMEMORY;
            };
            const buffer: [*]win_core.GUID = @ptrCast(@alignCast(raw));
            buffer[0] = foundation.IPropertyValue.IID;
            buffer[1] = Info.Iface.IID;
            count.* = 2;
            values.* = buffer;
            return win_core.hresult.S_OK;
        }

        fn getRuntimeClassName(
            _: *anyopaque,
            value: *win_core.HSTRING,
        ) callconv(.winapi) win_core.HRESULT {
            value.* = null;
            return win_core.hresult.S_OK;
        }

        fn getTrustLevel(
            _: *anyopaque,
            value: *i32,
        ) callconv(.winapi) win_core.HRESULT {
            value.* = @intFromEnum(win_core.TrustLevel.base_trust);
            return win_core.hresult.S_OK;
        }

        fn getValue(
            this: *const Info.Iface,
            result: *Info.Abi,
        ) callconv(.winapi) win_core.HRESULT {
            const state = stateFromReference(this);
            result.* = Info.toAbi(state.value);
            return win_core.hresult.S_OK;
        }

        fn getType(
            _: *const foundation.IPropertyValue,
            result: *PropertyType,
        ) callconv(.winapi) win_core.HRESULT {
            result.* = Info.property_type;
            return win_core.hresult.S_OK;
        }

        fn getIsNumericScalar(
            _: *const foundation.IPropertyValue,
            result: *win_core.BOOL,
        ) callconv(.winapi) win_core.HRESULT {
            result.* = win_core.boolToWin32(Info.is_numeric);
            return win_core.hresult.S_OK;
        }

        fn typedGetter(
            comptime RequestedAbi: type,
            comptime requested_type: PropertyType,
            this: *const foundation.IPropertyValue,
            result: *RequestedAbi,
        ) win_core.HRESULT {
            if (comptime Info.property_type != requested_type) {
                return win_core.hresult.E_NOTIMPL;
            }

            const state = stateFromPropertyValue(this);
            result.* = Info.toAbi(state.value);
            return win_core.hresult.S_OK;
        }

        fn typedGetterFn(
            comptime RequestedAbi: type,
            comptime requested_type: PropertyType,
        ) *const fn (this: *const foundation.IPropertyValue, result: *RequestedAbi) callconv(.winapi) win_core.HRESULT {
            return struct {
                fn impl(
                    this: *const foundation.IPropertyValue,
                    result: *RequestedAbi,
                ) callconv(.winapi) win_core.HRESULT {
                    return typedGetter(RequestedAbi, requested_type, this, result);
                }
            }.impl;
        }

        fn notImplementedArrayFn(
            comptime Elem: type,
        ) *const fn (this: *const foundation.IPropertyValue, p0_size: *u32, p0_ptr: *[*]Elem) callconv(.winapi) win_core.HRESULT {
            return struct {
                fn impl(
                    this: *const foundation.IPropertyValue,
                    p0_size: *u32,
                    p0_ptr: *[*]Elem,
                ) callconv(.winapi) win_core.HRESULT {
                    _ = this;
                    _ = p0_size;
                    _ = p0_ptr;
                    return win_core.hresult.E_NOTIMPL;
                }
            }.impl;
        }
    };
}

fn expectReferenceSurface(
    comptime T: type,
    value: T,
    expected_type: PropertyType,
    expected_numeric: bool,
) !void {
    const reference = try IReference(T).from(value);
    defer reference.deinit();

    try std.testing.expectEqual(value, try reference.value());

    const inspectable = reference.asInspectable();
    defer inspectable.deinit();

    var iid_count: u32 = 0;
    var iid_values: ?[*]win_core.GUID = null;
    try win_core.hresult.ok(inspectable.vtbl().GetIids(inspectable.ptr, &iid_count, &iid_values));
    const iid_alloc = iid_values orelse unreachable;
    defer CoTaskMemFree(@ptrCast(iid_alloc));
    try std.testing.expectEqual(@as(u32, 2), iid_count);
    try std.testing.expect(std.meta.eql(iid_alloc[0], foundation.IPropertyValue.IID));
    try std.testing.expect(std.meta.eql(iid_alloc[1], IReference(T).IID));

    const rebound = try IReference(T).fromInspectable(inspectable);
    defer rebound.deinit();
    try std.testing.expectEqual(value, try rebound.value());

    const boxed = try BoxedValue.fromInspectable(inspectable);
    defer boxed.deinit();

    try std.testing.expectEqual(expected_type, try boxed.getType());
    try std.testing.expectEqual(expected_numeric, try boxed.isNumericScalar());
    try std.testing.expectEqual(value, try boxed.get(T));
}

test "IReference(bool) IID matches the published golden vector" {
    try std.testing.expect(std.meta.eql(
        win_core.GUID.parse("{3c00fd60-2950-5939-a21a-2d12c5a01b8a}"),
        IReference(bool).IID,
    ));
}

test "supported primitive references expose value and PropertyType metadata" {
    inline for (.{
        .{ .T = bool, .value = true, .property_type = PropertyType.Boolean, .numeric = false },
        .{ .T = u8, .value = @as(u8, 7), .property_type = PropertyType.UInt8, .numeric = true },
        .{ .T = i16, .value = @as(i16, -16), .property_type = PropertyType.Int16, .numeric = true },
        .{ .T = u16, .value = @as(u16, 16), .property_type = PropertyType.UInt16, .numeric = true },
        .{ .T = i32, .value = @as(i32, -32), .property_type = PropertyType.Int32, .numeric = true },
        .{ .T = u32, .value = @as(u32, 32), .property_type = PropertyType.UInt32, .numeric = true },
        .{ .T = i64, .value = @as(i64, -64), .property_type = PropertyType.Int64, .numeric = true },
        .{ .T = u64, .value = @as(u64, 64), .property_type = PropertyType.UInt64, .numeric = true },
        .{ .T = f32, .value = @as(f32, 1.25), .property_type = PropertyType.Single, .numeric = true },
        .{ .T = f64, .value = @as(f64, 2.5), .property_type = PropertyType.Double, .numeric = true },
    }) |case| {
        try expectReferenceSurface(case.T, case.value, case.property_type, case.numeric);
    }
}

test "boxed references surface E_NOTIMPL for mismatched getters and arrays" {
    const reference = try box(true);
    defer reference.deinit();

    const boxed = try reference.boxedValue();
    defer boxed.deinit();

    try std.testing.expectError(win_core.hresult.Error.NotImplemented, boxed.get(i32));

    var out_size: u32 = 0;
    var out_ptr: [*]win_core.BOOL = undefined;
    try std.testing.expectError(
        win_core.hresult.Error.NotImplemented,
        win_core.hresult.ok(boxed.raw().vtable.GetBooleanArray(boxed.raw(), &out_size, &out_ptr)),
    );
}

test "IReference(i32) round-trips through PropertySet" {
    const win = @import("win");
    const Collections = win.WinRT.Collections;
    const PropertySet = Collections.PropertySet;
    const IMap_HSTRING_Object = Collections.IMap__G2__HSTRING__object;

    try win_core.roInitialize(.multi_threaded);
    defer win_core.winrt.RoUninitialize();

    const factory = try win_core.activationFactory(
        win_core.IActivationFactory_Vtbl,
        &win_core.IID_IActivationFactory,
        &PropertySet.NAME_W,
    );
    defer factory.deinit();

    var inspectable_raw: ?*anyopaque = null;
    try win_core.hresult.ok(factory.vtbl().ActivateInstance(factory.ptr, &inspectable_raw));
    const inst: win_core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(inspectable_raw orelse return error.NullActivation)),
    };
    defer inst.deinit();

    const map = try inst.cast(IMap_HSTRING_Object.Vtbl, &IMap_HSTRING_Object.IID);
    defer map.deinit();
    const map_iface: *const IMap_HSTRING_Object = @ptrCast(@alignCast(map.ptr));

    var key = try win_core.Hstring.create(win_core.utf16Lit("answer"));
    defer key.deinit();

    const reference = try box(@as(i32, 42));
    defer reference.deinit();

    var replaced: win_core.BOOL = 0;
    try win_core.hresult.ok(
        map_iface.vtable.Insert(map_iface, key.raw, reference.asAnyOpaque(), &replaced),
    );
    try std.testing.expect(!win_core.boolFromWin32(replaced));

    var stored_raw: ?*const anyopaque = null;
    try win_core.hresult.ok(map_iface.vtable.Lookup(map_iface, key.raw, &stored_raw));
    const stored: win_core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(@constCast(stored_raw.?))),
    };
    defer stored.deinit();

    try std.testing.expectEqual(@as(i32, 42), try unbox(i32, stored));

    try win_core.hresult.ok(map_iface.vtable.Clear(map_iface));
}
