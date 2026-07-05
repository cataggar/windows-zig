const std = @import("std");
const core = @import("win-core");
const abi = @import("abi.zig");

const IID_IIterable_template = core.GUID.parse("FAA585EA-6214-4217-AFDA-7F46DE5869B3");
const IID_IIterator_template = core.GUID.parse("6A79E863-4300-459A-9966-CBB660963EE1");
const IID_IKeyValuePair_template = core.GUID.parse("02B51929-C1C4-4A7E-8940-0312B5C18500");
const IID_IMap_template = core.GUID.parse("3C2925FE-8519-45C1-AA79-197B6718C1C1");
const IID_IMapChangedEventArgs_template = core.GUID.parse("9939F4DF-050A-4C0F-AA60-77075F9C4777");
const IID_IMapView_template = core.GUID.parse("E480CE40-A338-4ADA-ADCF-272272E48CB9");
const IID_IObservableMap_template = core.GUID.parse("65DF2BF5-BF39-41B5-AEBC-5A9D865E472B");
const IID_IObservableVector_template = core.GUID.parse("5917EB53-50B4-4A0D-B309-65862B3F1DBC");
const IID_IVector_template = core.GUID.parse("913337E9-11A1-4345-A3A2-4E7F956E222D");
const IID_IVectorView_template = core.GUID.parse("BBE1FA4C-B0E3-4583-BAEF-1F1B2E483E56");
const IID_MapChangedEventHandler_template = core.GUID.parse("179517F3-94EE-41F8-BDDC-768A895544F3");
const IID_VectorChangedEventHandler_template = core.GUID.parse("0C051752-9FBF-4C70-AA0C-0E4C82D9A761");

pub const E_BOUNDS = core.hresult.E_BOUNDS;
pub const EventRegistrationToken = abi.EventRegistrationToken;

pub const CollectionChange = enum(i32) {
    Reset = 0,
    ItemInserted = 1,
    ItemRemoved = 2,
    ItemChanged = 3,
    _,
};
const CollectionChangeTy = CollectionChange;

pub const IVectorChangedEventArgs = extern struct {
    const Self = @This();

    vtable: *const Vtbl,

    pub const Vtbl = extern struct {
        base: core.IInspectable_Vtbl,
        get_CollectionChange: *const fn (this: *const Self, result: *CollectionChangeTy) callconv(.winapi) core.HRESULT,
        get_Index: *const fn (this: *const Self, result: *u32) callconv(.winapi) core.HRESULT,
    };

    pub const IID = core.GUID.parse("575933DF-34FE-4480-AF15-07691F3D5D9B");
    pub const SIGNATURE = abi.guidSignature(IID);
    pub const NAME = "Windows.Foundation.Collections.IVectorChangedEventArgs";
    pub const NAME_W = core.utf16Lit(NAME);

    pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
    }

    pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const Self) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn deinit(self: *const Self) void {
        _ = self.Release();
    }

    pub fn clone(self: *const Self) *Self {
        _ = self.AddRef();
        return @constCast(self);
    }

    pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
        var raw: ?*anyopaque = null;
        try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
        return @ptrCast(@alignCast(raw orelse return error.Pointer));
    }

    pub fn CollectionChange(self: *const Self) core.hresult.Error!CollectionChangeTy {
        var result: CollectionChangeTy = .Reset;
        try core.hresult.ok(self.vtable.get_CollectionChange(self, &result));
        return result;
    }

    pub fn Index(self: *const Self) core.hresult.Error!u32 {
        var result: u32 = 0;
        try core.hresult.ok(self.vtable.get_Index(self, &result));
        return result;
    }
};

pub fn IIterable(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported IIterable element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_IIterable_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.IIterable`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            First: *const fn (this: *const Self, result: **anyopaque) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(T) {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.vtable.First(self, @ptrCast(&raw)));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }
    };
}

pub fn IIterator(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported IIterator element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_IIterator_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.IIterator`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            get_Current: *const fn (this: *const Self, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            get_HasCurrent: *const fn (this: *const Self, result: *core.BOOL) callconv(.winapi) core.HRESULT,
            MoveNext: *const fn (this: *const Self, result: *core.BOOL) callconv(.winapi) core.HRESULT,
            GetMany: *const fn (this: *const Self, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn Current(self: *const Self) core.hresult.Error!T {
            var value: abi.BufferElement(T) = abi.defaultBuffer(T);
            try core.hresult.ok(self.vtable.get_Current(self, &value));
            return abi.takeAbiValue(T, &value);
        }

        pub fn HasCurrent(self: *const Self) core.hresult.Error!bool {
            var value: core.BOOL = 0;
            try core.hresult.ok(self.vtable.get_HasCurrent(self, &value));
            return core.boolFromWin32(value);
        }

        pub fn MoveNext(self: *const Self) core.hresult.Error!bool {
            var value: core.BOOL = 0;
            try core.hresult.ok(self.vtable.MoveNext(self, &value));
            return core.boolFromWin32(value);
        }

        pub fn GetMany(self: *const Self, items: []abi.BufferElement(T)) core.hresult.Error!u32 {
            var result: u32 = 0;
            var dummy: abi.BufferElement(T) = abi.defaultBuffer(T);
            const ptr: [*]abi.BufferElement(T) = if (items.len == 0) @ptrCast(&dummy) else items.ptr;
            try core.hresult.ok(self.vtable.GetMany(self, @intCast(items.len), ptr, &result));
            return result;
        }
    };
}

pub fn IKeyValuePair(comptime K: type, comptime V: type) type {
    if (!abi.isSupportedValueType(K) or !abi.isSupportedValueType(V))
        @compileError("unsupported IKeyValuePair type arguments");

    const signature = abi.signatureG2(IID_IKeyValuePair_template, K, V);
    const name = abi.nameG2("Windows.Foundation.Collections.IKeyValuePair`2", K, V);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            get_Key: *const fn (this: *const Self, result: *abi.BufferElement(K)) callconv(.winapi) core.HRESULT,
            get_Value: *const fn (this: *const Self, result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn Key(self: *const Self) core.hresult.Error!K {
            var value: abi.BufferElement(K) = abi.defaultBuffer(K);
            try core.hresult.ok(self.vtable.get_Key(self, &value));
            return abi.takeAbiValue(K, &value);
        }

        pub fn Value(self: *const Self) core.hresult.Error!V {
            var value: abi.BufferElement(V) = abi.defaultBuffer(V);
            try core.hresult.ok(self.vtable.get_Value(self, &value));
            return abi.takeAbiValue(V, &value);
        }
    };
}

pub fn IVector(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported IVector element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_IVector_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.IVector`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            GetAt: *const fn (this: *const Self, index: u32, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            get_Size: *const fn (this: *const Self, result: *u32) callconv(.winapi) core.HRESULT,
            GetView: *const fn (this: *const Self, result: **anyopaque) callconv(.winapi) core.HRESULT,
            IndexOf: *const fn (this: *const Self, value: abi.BufferElement(T), index: *u32, result: *core.BOOL) callconv(.winapi) core.HRESULT,
            SetAt: *const fn (this: *const Self, index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            InsertAt: *const fn (this: *const Self, index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            RemoveAt: *const fn (this: *const Self, index: u32) callconv(.winapi) core.HRESULT,
            Append: *const fn (this: *const Self, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            RemoveAtEnd: *const fn (this: *const Self) callconv(.winapi) core.HRESULT,
            Clear: *const fn (this: *const Self) callconv(.winapi) core.HRESULT,
            GetMany: *const fn (this: *const Self, start_index: u32, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT,
            ReplaceAll: *const fn (this: *const Self, items_size: u32, items_ptr: [*]const abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(T) {
            const iterable = try self.cast(IIterable(T));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn GetAt(self: *const Self, index: u32) core.hresult.Error!T {
            var value: abi.BufferElement(T) = abi.defaultBuffer(T);
            try core.hresult.ok(self.vtable.GetAt(self, index, &value));
            return abi.takeAbiValue(T, &value);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            var value: u32 = 0;
            try core.hresult.ok(self.vtable.get_Size(self, &value));
            return value;
        }

        pub fn GetView(self: *const Self) core.hresult.Error!*IVectorView(T) {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.vtable.GetView(self, @ptrCast(&raw)));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn IndexOf(self: *const Self, value: T, index: *u32) core.hresult.Error!bool {
            var found: core.BOOL = 0;
            try core.hresult.ok(self.vtable.IndexOf(self, abi.valueToAbiParam(T, value), index, &found));
            return core.boolFromWin32(found);
        }

        pub fn SetAt(self: *const Self, index: u32, value: T) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.SetAt(self, index, abi.valueToAbiParam(T, value)));
        }

        pub fn InsertAt(self: *const Self, index: u32, value: T) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.InsertAt(self, index, abi.valueToAbiParam(T, value)));
        }

        pub fn RemoveAt(self: *const Self, index: u32) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.RemoveAt(self, index));
        }

        pub fn Append(self: *const Self, value: T) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.Append(self, abi.valueToAbiParam(T, value)));
        }

        pub fn RemoveAtEnd(self: *const Self) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.RemoveAtEnd(self));
        }

        pub fn Clear(self: *const Self) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.Clear(self));
        }

        pub fn GetMany(self: *const Self, start_index: u32, items: []abi.BufferElement(T)) core.hresult.Error!u32 {
            var result: u32 = 0;
            var dummy: abi.BufferElement(T) = abi.defaultBuffer(T);
            const ptr: [*]abi.BufferElement(T) = if (items.len == 0) @ptrCast(&dummy) else items.ptr;
            try core.hresult.ok(self.vtable.GetMany(self, start_index, @intCast(items.len), ptr, &result));
            return result;
        }

        pub fn ReplaceAll(self: *const Self, items: []const abi.BufferElement(T)) core.hresult.Error!void {
            var dummy: abi.BufferElement(T) = abi.defaultBuffer(T);
            const ptr: [*]const abi.BufferElement(T) = if (items.len == 0) @ptrCast(&dummy) else items.ptr;
            try core.hresult.ok(self.vtable.ReplaceAll(self, @intCast(items.len), ptr));
        }
    };
}

pub fn IVectorView(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported IVectorView element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_IVectorView_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.IVectorView`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            GetAt: *const fn (this: *const Self, index: u32, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT,
            get_Size: *const fn (this: *const Self, result: *u32) callconv(.winapi) core.HRESULT,
            IndexOf: *const fn (this: *const Self, value: abi.BufferElement(T), index: *u32, result: *core.BOOL) callconv(.winapi) core.HRESULT,
            GetMany: *const fn (this: *const Self, start_index: u32, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(T) {
            const iterable = try self.cast(IIterable(T));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn GetAt(self: *const Self, index: u32) core.hresult.Error!T {
            var value: abi.BufferElement(T) = abi.defaultBuffer(T);
            try core.hresult.ok(self.vtable.GetAt(self, index, &value));
            return abi.takeAbiValue(T, &value);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            var value: u32 = 0;
            try core.hresult.ok(self.vtable.get_Size(self, &value));
            return value;
        }

        pub fn IndexOf(self: *const Self, value: T, index: *u32) core.hresult.Error!bool {
            var found: core.BOOL = 0;
            try core.hresult.ok(self.vtable.IndexOf(self, abi.valueToAbiParam(T, value), index, &found));
            return core.boolFromWin32(found);
        }

        pub fn GetMany(self: *const Self, start_index: u32, items: []abi.BufferElement(T)) core.hresult.Error!u32 {
            var result: u32 = 0;
            var dummy: abi.BufferElement(T) = abi.defaultBuffer(T);
            const ptr: [*]abi.BufferElement(T) = if (items.len == 0) @ptrCast(&dummy) else items.ptr;
            try core.hresult.ok(self.vtable.GetMany(self, start_index, @intCast(items.len), ptr, &result));
            return result;
        }
    };
}

pub fn VectorChangedEventHandler(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported VectorChangedEventHandler element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_VectorChangedEventHandler_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.VectorChangedEventHandler`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IUnknown_Vtbl,
            Invoke: *const fn (this: *const Self, sender: *anyopaque, event: *IVectorChangedEventArgs) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }
    };
}

pub fn IObservableVector(comptime T: type) type {
    if (!abi.isSupportedValueType(T))
        @compileError("unsupported IObservableVector element type: " ++ @typeName(T));

    const signature = abi.signatureG1(IID_IObservableVector_template, T);
    const name = abi.nameG1("Windows.Foundation.Collections.IObservableVector`1", T);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            add_VectorChanged: *const fn (this: *const Self, handler: *anyopaque, result: *EventRegistrationToken) callconv(.winapi) core.HRESULT,
            remove_VectorChanged: *const fn (this: *const Self, token: EventRegistrationToken) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn VectorChanged(
            self: *const Self,
            allocator: std.mem.Allocator,
            invoke: @FieldType(VectorChangedEventHandler(T).Vtbl, "Invoke"),
            user_data: ?*anyopaque,
        ) abi.CollectionError!EventRegistrationToken {
            const D = core.Delegate(std.meta.Child(@TypeOf(invoke)), VectorChangedEventHandler(T).IID);
            const handler = try D.create(allocator, invoke, user_data);
            defer _ = D.release(handler);

            var token: EventRegistrationToken = undefined;
            try core.hresult.ok(self.vtable.add_VectorChanged(self, handler, &token));
            return token;
        }

        pub fn RemoveVectorChanged(self: *const Self, token: EventRegistrationToken) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.remove_VectorChanged(self, token));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(T) {
            const iterable = try self.cast(IIterable(T));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn GetAt(self: *const Self, index: u32) core.hresult.Error!T {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            return vector.GetAt(index);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            return vector.Size();
        }

        pub fn GetView(self: *const Self) core.hresult.Error!*IVectorView(T) {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            return vector.GetView();
        }

        pub fn IndexOf(self: *const Self, value: T, index: *u32) core.hresult.Error!bool {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            return vector.IndexOf(value, index);
        }

        pub fn SetAt(self: *const Self, index: u32, value: T) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.SetAt(index, value);
        }

        pub fn InsertAt(self: *const Self, index: u32, value: T) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.InsertAt(index, value);
        }

        pub fn RemoveAt(self: *const Self, index: u32) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.RemoveAt(index);
        }

        pub fn Append(self: *const Self, value: T) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.Append(value);
        }

        pub fn RemoveAtEnd(self: *const Self) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.RemoveAtEnd();
        }

        pub fn Clear(self: *const Self) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.Clear();
        }

        pub fn GetMany(self: *const Self, start_index: u32, items: []abi.BufferElement(T)) core.hresult.Error!u32 {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            return vector.GetMany(start_index, items);
        }

        pub fn ReplaceAll(self: *const Self, items: []const abi.BufferElement(T)) core.hresult.Error!void {
            const vector = try self.cast(IVector(T));
            defer _ = vector.Release();
            try vector.ReplaceAll(items);
        }
    };
}

pub fn IMap(comptime K: type, comptime V: type) type {
    if (!abi.isSupportedValueType(K) or !abi.isSupportedValueType(V))
        @compileError("unsupported IMap type arguments");

    const signature = abi.signatureG2(IID_IMap_template, K, V);
    const name = abi.nameG2("Windows.Foundation.Collections.IMap`2", K, V);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            Lookup: *const fn (this: *const Self, key: abi.BufferElement(K), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT,
            get_Size: *const fn (this: *const Self, result: *u32) callconv(.winapi) core.HRESULT,
            HasKey: *const fn (this: *const Self, key: abi.BufferElement(K), result: *core.BOOL) callconv(.winapi) core.HRESULT,
            GetView: *const fn (this: *const Self, result: **anyopaque) callconv(.winapi) core.HRESULT,
            Insert: *const fn (this: *const Self, key: abi.BufferElement(K), value: abi.BufferElement(V), result: *core.BOOL) callconv(.winapi) core.HRESULT,
            Remove: *const fn (this: *const Self, key: abi.BufferElement(K)) callconv(.winapi) core.HRESULT,
            Clear: *const fn (this: *const Self) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(*IKeyValuePair(K, V)) {
            const iterable = try self.cast(IIterable(*IKeyValuePair(K, V)));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn Lookup(self: *const Self, key: K) core.hresult.Error!V {
            var value: abi.BufferElement(V) = abi.defaultBuffer(V);
            try core.hresult.ok(self.vtable.Lookup(self, abi.valueToAbiParam(K, key), &value));
            return abi.takeAbiValue(V, &value);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            var value: u32 = 0;
            try core.hresult.ok(self.vtable.get_Size(self, &value));
            return value;
        }

        pub fn HasKey(self: *const Self, key: K) core.hresult.Error!bool {
            var found: core.BOOL = 0;
            try core.hresult.ok(self.vtable.HasKey(self, abi.valueToAbiParam(K, key), &found));
            return core.boolFromWin32(found);
        }

        pub fn GetView(self: *const Self) core.hresult.Error!*IMapView(K, V) {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.vtable.GetView(self, @ptrCast(&raw)));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn Insert(self: *const Self, key: K, value: V) core.hresult.Error!bool {
            var replaced: core.BOOL = 0;
            try core.hresult.ok(self.vtable.Insert(self, abi.valueToAbiParam(K, key), abi.valueToAbiParam(V, value), &replaced));
            return core.boolFromWin32(replaced);
        }

        pub fn Remove(self: *const Self, key: K) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.Remove(self, abi.valueToAbiParam(K, key)));
        }

        pub fn Clear(self: *const Self) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.Clear(self));
        }
    };
}

pub fn IMapView(comptime K: type, comptime V: type) type {
    if (!abi.isSupportedValueType(K) or !abi.isSupportedValueType(V))
        @compileError("unsupported IMapView type arguments");

    const signature = abi.signatureG2(IID_IMapView_template, K, V);
    const name = abi.nameG2("Windows.Foundation.Collections.IMapView`2", K, V);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            Lookup: *const fn (this: *const Self, key: abi.BufferElement(K), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT,
            get_Size: *const fn (this: *const Self, result: *u32) callconv(.winapi) core.HRESULT,
            HasKey: *const fn (this: *const Self, key: abi.BufferElement(K), result: *core.BOOL) callconv(.winapi) core.HRESULT,
            Split: *const fn (this: *const Self, first: **anyopaque, second: **anyopaque) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(*IKeyValuePair(K, V)) {
            const iterable = try self.cast(IIterable(*IKeyValuePair(K, V)));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn Lookup(self: *const Self, key: K) core.hresult.Error!V {
            var value: abi.BufferElement(V) = abi.defaultBuffer(V);
            try core.hresult.ok(self.vtable.Lookup(self, abi.valueToAbiParam(K, key), &value));
            return abi.takeAbiValue(V, &value);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            var value: u32 = 0;
            try core.hresult.ok(self.vtable.get_Size(self, &value));
            return value;
        }

        pub fn HasKey(self: *const Self, key: K) core.hresult.Error!bool {
            var found: core.BOOL = 0;
            try core.hresult.ok(self.vtable.HasKey(self, abi.valueToAbiParam(K, key), &found));
            return core.boolFromWin32(found);
        }

        pub fn Split(self: *const Self, first: *?*Self, second: *?*Self) core.hresult.Error!void {
            var raw_first: ?*anyopaque = null;
            var raw_second: ?*anyopaque = null;
            try core.hresult.ok(self.vtable.Split(self, @ptrCast(&raw_first), @ptrCast(&raw_second)));
            first.* = if (raw_first) |p| @ptrCast(@alignCast(p)) else null;
            second.* = if (raw_second) |p| @ptrCast(@alignCast(p)) else null;
        }
    };
}

pub fn IMapChangedEventArgs(comptime K: type) type {
    if (!abi.isSupportedValueType(K))
        @compileError("unsupported IMapChangedEventArgs key type: " ++ @typeName(K));

    const signature = abi.signatureG1(IID_IMapChangedEventArgs_template, K);
    const name = abi.nameG1("Windows.Foundation.Collections.IMapChangedEventArgs`1", K);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            get_CollectionChange: *const fn (this: *const Self, result: *CollectionChangeTy) callconv(.winapi) core.HRESULT,
            get_Key: *const fn (this: *const Self, result: *abi.BufferElement(K)) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn CollectionChange(self: *const Self) core.hresult.Error!CollectionChangeTy {
            var value: CollectionChangeTy = .Reset;
            try core.hresult.ok(self.vtable.get_CollectionChange(self, &value));
            return value;
        }

        pub fn Key(self: *const Self) core.hresult.Error!K {
            var value: abi.BufferElement(K) = abi.defaultBuffer(K);
            try core.hresult.ok(self.vtable.get_Key(self, &value));
            return abi.takeAbiValue(K, &value);
        }
    };
}

pub fn MapChangedEventHandler(comptime K: type, comptime V: type) type {
    if (!abi.isSupportedValueType(K) or !abi.isSupportedValueType(V))
        @compileError("unsupported MapChangedEventHandler type arguments");

    const signature = abi.signatureG2(IID_MapChangedEventHandler_template, K, V);
    const name = abi.nameG2("Windows.Foundation.Collections.MapChangedEventHandler`2", K, V);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IUnknown_Vtbl,
            Invoke: *const fn (this: *const Self, sender: *anyopaque, event: *anyopaque) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }
    };
}

pub fn IObservableMap(comptime K: type, comptime V: type) type {
    if (!abi.isSupportedValueType(K) or !abi.isSupportedValueType(V))
        @compileError("unsupported IObservableMap type arguments");

    const signature = abi.signatureG2(IID_IObservableMap_template, K, V);
    const name = abi.nameG2("Windows.Foundation.Collections.IObservableMap`2", K, V);

    return extern struct {
        const Self = @This();

        vtable: *const Vtbl,

        pub const Vtbl = extern struct {
            base: core.IInspectable_Vtbl,
            add_MapChanged: *const fn (this: *const Self, handler: *anyopaque, result: *EventRegistrationToken) callconv(.winapi) core.HRESULT,
            remove_MapChanged: *const fn (this: *const Self, token: EventRegistrationToken) callconv(.winapi) core.HRESULT,
        };

        pub const IID = abi.parameterizedIid(signature);
        pub const SIGNATURE = signature;
        pub const NAME = name;
        pub const NAME_W = core.utf16Lit(name);

        pub fn QueryInterface(self: *const Self, iid: *const core.GUID, out: *?*anyopaque) callconv(.winapi) core.HRESULT {
            return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, out);
        }

        pub fn AddRef(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
        }

        pub fn Release(self: *const Self) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        pub fn deinit(self: *const Self) void {
            _ = self.Release();
        }

        pub fn clone(self: *const Self) *Self {
            _ = self.AddRef();
            return @constCast(self);
        }

        pub fn cast(self: *const Self, comptime U: type) core.hresult.Error!*U {
            var raw: ?*anyopaque = null;
            try core.hresult.ok(self.QueryInterface(&U.IID, &raw));
            return @ptrCast(@alignCast(raw orelse return error.Pointer));
        }

        pub fn MapChanged(
            self: *const Self,
            allocator: std.mem.Allocator,
            invoke: @FieldType(MapChangedEventHandler(K, V).Vtbl, "Invoke"),
            user_data: ?*anyopaque,
        ) abi.CollectionError!EventRegistrationToken {
            const D = core.Delegate(std.meta.Child(@TypeOf(invoke)), MapChangedEventHandler(K, V).IID);
            const handler = try D.create(allocator, invoke, user_data);
            defer _ = D.release(handler);

            var token: EventRegistrationToken = undefined;
            try core.hresult.ok(self.vtable.add_MapChanged(self, handler, &token));
            return token;
        }

        pub fn RemoveMapChanged(self: *const Self, token: EventRegistrationToken) core.hresult.Error!void {
            try core.hresult.ok(self.vtable.remove_MapChanged(self, token));
        }

        pub fn First(self: *const Self) core.hresult.Error!*IIterator(*IKeyValuePair(K, V)) {
            const iterable = try self.cast(IIterable(*IKeyValuePair(K, V)));
            defer _ = iterable.Release();
            return iterable.First();
        }

        pub fn Lookup(self: *const Self, key: K) core.hresult.Error!V {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            return map.Lookup(key);
        }

        pub fn Size(self: *const Self) core.hresult.Error!u32 {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            return map.Size();
        }

        pub fn HasKey(self: *const Self, key: K) core.hresult.Error!bool {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            return map.HasKey(key);
        }

        pub fn GetView(self: *const Self) core.hresult.Error!*IMapView(K, V) {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            return map.GetView();
        }

        pub fn Insert(self: *const Self, key: K, value: V) core.hresult.Error!bool {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            return map.Insert(key, value);
        }

        pub fn Remove(self: *const Self, key: K) core.hresult.Error!void {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            try map.Remove(key);
        }

        pub fn Clear(self: *const Self) core.hresult.Error!void {
            const map = try self.cast(IMap(K, V));
            defer _ = map.Release();
            try map.Clear();
        }
    };
}
