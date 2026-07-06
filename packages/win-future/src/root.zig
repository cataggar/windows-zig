//! `win-future` — blocking WinRT async helpers and combinators.
//!
//! Layers `IAsyncAction` / `IAsyncOperation<T>` wait helpers,
//! `WithProgress` support, and blocking `join` / `when` composition on
//! top of `win-core`'s delegate/runtime primitives. Native Zig async is
//! intentionally deferred until `std.Io` stabilises.

const std = @import("std");
const win_core = @import("win-core");
const winmd = @import("winmd");
const builtin = @import("builtin");

pub const core = win_core;

const GUID = win_core.GUID;
const HRESULT = win_core.HRESULT;
const HSTRING = win_core.HSTRING;
const IUnknown_Vtbl = win_core.IUnknown_Vtbl;
const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
const hresult = win_core.hresult;

pub const Async = struct {
    pub const Error = hresult.Error || error{ OutOfMemory, Aborted };

    pub const AsyncStatus = win_core.Async.AsyncStatus;
    pub const WinrtHResult = win_core.Async.WinrtHResult;
    pub const IAsyncInfo_Vtbl = win_core.Async.IAsyncInfo_Vtbl;
    pub const IID_IAsyncInfo = win_core.Async.IID_IAsyncInfo;

    const IID_AsyncActionCompletedHandler = GUID.parse("A4ED5C81-76C9-40BD-8BE6-B1D90FB20AE7");
    const IID_AsyncOperationCompletedHandler_Open = GUID.parse("FCDCF02C-E5D8-4478-915A-4D90B74B83A5");
    const IID_AsyncActionWithProgressCompletedHandler_Open = GUID.parse("9C029F91-CC84-44FD-AC26-0A6C4E555281");
    const IID_AsyncActionProgressHandler_Open = GUID.parse("6D844858-0CFF-4590-AE89-95A5A5C8B4B8");
    const IID_AsyncOperationWithProgressCompletedHandler_Open = GUID.parse("E85DF41D-6AA7-46E3-A8E2-F009D840C627");
    const IID_AsyncOperationProgressHandler_Open = GUID.parse("55690902-0AAB-421A-8778-F8CE5026D758");
    const CompletedInvokeFn =
        fn (this: *anyopaque, async_info: *anyopaque, status: AsyncStatus) callconv(.winapi) HRESULT;

    const HANDLE = *anyopaque;
    const INFINITE: u32 = 0xFFFFFFFF;
    const WAIT_OBJECT_0: u32 = 0;

    extern "kernel32" fn CreateEventW(
        lpEventAttributes: ?*anyopaque,
        bManualReset: win_core.BOOL,
        bInitialState: win_core.BOOL,
        lpName: ?[*:0]const u16,
    ) callconv(.winapi) ?HANDLE;

    extern "kernel32" fn SetEvent(hEvent: HANDLE) callconv(.winapi) win_core.BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) win_core.BOOL;

    pub fn ProgressCallback(comptime P: type) type {
        return *const fn (context: ?*anyopaque, value: P) void;
    }

    pub fn wait(allocator: std.mem.Allocator, action_ptr: anytype) Error!void {
        return win_core.Async.wait(allocator, opaquePtr(action_ptr));
    }

    pub fn waitResult(
        comptime T: type,
        allocator: std.mem.Allocator,
        operation_ptr: anytype,
    ) Error!T {
        const ptr = opaquePtr(operation_ptr);
        const Vtbl = win_core.Async.IAsyncOperation_Vtbl(T);
        const vtbl: *const Vtbl = @as(
            *const *const Vtbl,
            @ptrCast(@alignCast(ptr)),
        ).*;

        try blockUntilDone(
            allocator,
            ptr,
            vtbl.put_Completed,
            vtbl.base.base.QueryInterface,
            asyncOperationCompletedHandlerIid(T),
        );

        var result: T = undefined;
        try hresult.ok(vtbl.GetResults(ptr, &result));
        return result;
    }

    pub fn waitWithProgress(
        comptime P: type,
        allocator: std.mem.Allocator,
        action_ptr: anytype,
        progress: ?ProgressCallback(P),
        context: ?*anyopaque,
    ) Error!void {
        const ptr = opaquePtr(action_ptr);
        const Vtbl = IAsyncActionWithProgress_Vtbl(P);
        const vtbl: *const Vtbl = @as(
            *const *const Vtbl,
            @ptrCast(@alignCast(ptr)),
        ).*;

        try blockUntilDoneWithProgress(
            P,
            allocator,
            ptr,
            vtbl.put_Progress,
            vtbl.put_Completed,
            vtbl.base.base.QueryInterface,
            asyncActionProgressHandlerIid(P),
            asyncActionWithProgressCompletedHandlerIid(P),
            progress,
            context,
        );

        try hresult.ok(vtbl.GetResults(ptr));
    }

    pub fn waitResultWithProgress(
        comptime T: type,
        comptime P: type,
        allocator: std.mem.Allocator,
        operation_ptr: anytype,
        progress: ?ProgressCallback(P),
        context: ?*anyopaque,
    ) Error!T {
        const ptr = opaquePtr(operation_ptr);
        const Vtbl = IAsyncOperationWithProgress_Vtbl(T, P);
        const vtbl: *const Vtbl = @as(
            *const *const Vtbl,
            @ptrCast(@alignCast(ptr)),
        ).*;

        try blockUntilDoneWithProgress(
            P,
            allocator,
            ptr,
            vtbl.put_Progress,
            vtbl.put_Completed,
            vtbl.base.base.QueryInterface,
            asyncOperationProgressHandlerIid(T, P),
            asyncOperationWithProgressCompletedHandlerIid(T, P),
            progress,
            context,
        );

        var result: T = undefined;
        try hresult.ok(vtbl.GetResults(ptr, &result));
        return result;
    }

    pub fn action(ptr: anytype) ActionHandle {
        return .{ .ptr = opaquePtr(ptr) };
    }

    pub fn operation(comptime T: type, ptr: anytype) OperationHandle(T) {
        return .{ .ptr = opaquePtr(ptr) };
    }

    pub fn actionWithProgress(
        comptime P: type,
        ptr: anytype,
        progress: ?ProgressCallback(P),
        context: ?*anyopaque,
    ) ActionWithProgressHandle(P) {
        return .{
            .ptr = opaquePtr(ptr),
            .progress = progress,
            .context = context,
        };
    }

    pub fn operationWithProgress(
        comptime T: type,
        comptime P: type,
        ptr: anytype,
        progress: ?ProgressCallback(P),
        context: ?*anyopaque,
    ) OperationWithProgressHandle(T, P) {
        return .{
            .ptr = opaquePtr(ptr),
            .progress = progress,
            .context = context,
        };
    }

    pub fn JoinResult(comptime AsyncTuple: type) type {
        ensureTupleOfDescriptors(AsyncTuple);
        const fields = std.meta.fields(AsyncTuple);
        var result_types: [fields.len]type = undefined;
        inline for (fields, 0..) |field, index| {
            result_types[index] = field.type.Result;
        }
        return std.meta.Tuple(&result_types);
    }

    pub fn join(
        allocator: std.mem.Allocator,
        async_values: anytype,
    ) Error!JoinResult(@TypeOf(async_values)) {
        const AsyncTuple = @TypeOf(async_values);
        const ResultTuple = JoinResult(AsyncTuple);
        var result: ResultTuple = undefined;

        inline for (std.meta.fields(AsyncTuple)) |field| {
            @field(result, field.name) = try @field(async_values, field.name).wait(allocator);
        }

        return result;
    }

    pub fn when(
        allocator: std.mem.Allocator,
        async_values: anytype,
        context: anytype,
        callback: *const fn (@TypeOf(context), JoinResult(@TypeOf(async_values))) void,
    ) Error!void {
        callback(context, try join(allocator, async_values));
    }

    const ActionHandle = struct {
        pub const Result = void;

        ptr: *anyopaque,

        pub fn wait(self: @This(), allocator: std.mem.Allocator) Error!void {
            return Async.wait(allocator, self.ptr);
        }
    };

    fn OperationHandle(comptime T: type) type {
        return struct {
            pub const Result = T;

            ptr: *anyopaque,

            pub fn wait(self: @This(), allocator: std.mem.Allocator) Error!T {
                return Async.waitResult(T, allocator, self.ptr);
            }
        };
    }

    fn ActionWithProgressHandle(comptime P: type) type {
        return struct {
            pub const Result = void;

            ptr: *anyopaque,
            progress: ?ProgressCallback(P),
            context: ?*anyopaque,

            pub fn wait(self: @This(), allocator: std.mem.Allocator) Error!void {
                return Async.waitWithProgress(P, allocator, self.ptr, self.progress, self.context);
            }
        };
    }

    fn OperationWithProgressHandle(comptime T: type, comptime P: type) type {
        return struct {
            pub const Result = T;

            ptr: *anyopaque,
            progress: ?ProgressCallback(P),
            context: ?*anyopaque,

            pub fn wait(self: @This(), allocator: std.mem.Allocator) Error!T {
                return Async.waitResultWithProgress(
                    T,
                    P,
                    allocator,
                    self.ptr,
                    self.progress,
                    self.context,
                );
            }
        };
    }

    fn ProgressInvokeFn(comptime P: type) type {
        return fn (this: *anyopaque, async_info: *anyopaque, value: P) callconv(.winapi) HRESULT;
    }

    fn ProgressState(comptime P: type) type {
        return struct {
            callback: ?ProgressCallback(P),
            context: ?*anyopaque,
        };
    }

    fn CompletedThunk(comptime iid: GUID) type {
        return struct {
            fn invoke(this: *anyopaque, _: *anyopaque, _: AsyncStatus) callconv(.winapi) HRESULT {
                const D = win_core.Delegate(CompletedInvokeFn, iid);
                const event_handle: HANDLE = @ptrCast(D.userData(this) orelse return hresult.E_FAIL);
                _ = SetEvent(event_handle);
                return hresult.S_OK;
            }
        };
    }

    fn ProgressThunk(comptime P: type, comptime iid: GUID) type {
        return struct {
            fn invoke(this: *anyopaque, _: *anyopaque, value: P) callconv(.winapi) HRESULT {
                const D = win_core.Delegate(ProgressInvokeFn(P), iid);
                const raw = D.userData(this) orelse return hresult.E_FAIL;
                const state: *const ProgressState(P) = @ptrCast(@alignCast(raw));
                if (state.callback) |callback| {
                    callback(state.context, value);
                }
                return hresult.S_OK;
            }
        };
    }

    const metadata = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk winmd.parse(@embedFile("Windows.winmd")) catch |err| {
            @compileError("failed to parse Windows.winmd: " ++ @errorName(err));
        };
    };

    const winui_xaml_metadata = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk winmd.parse(@embedFile("Microsoft.UI.Xaml.winmd")) catch |err| {
            @compileError("failed to parse Microsoft.UI.Xaml.winmd: " ++ @errorName(err));
        };
    };

    const TypeDefRef = struct {
        file: *const winmd.File,
        row: u32,
    };

    fn asyncOperationCompletedHandlerIid(comptime T: type) GUID {
        return parameterizedIid(std.fmt.comptimePrint(
            "pinterface({{{s}}};{s})",
            .{ guidHex(IID_AsyncOperationCompletedHandler_Open), runtimeSignature(T) },
        ));
    }

    fn asyncActionWithProgressCompletedHandlerIid(comptime P: type) GUID {
        return parameterizedIid(std.fmt.comptimePrint(
            "pinterface({{{s}}};{s})",
            .{ guidHex(IID_AsyncActionWithProgressCompletedHandler_Open), runtimeSignature(P) },
        ));
    }

    fn asyncActionProgressHandlerIid(comptime P: type) GUID {
        return parameterizedIid(std.fmt.comptimePrint(
            "pinterface({{{s}}};{s})",
            .{ guidHex(IID_AsyncActionProgressHandler_Open), runtimeSignature(P) },
        ));
    }

    fn asyncOperationWithProgressCompletedHandlerIid(comptime T: type, comptime P: type) GUID {
        return parameterizedIid(std.fmt.comptimePrint(
            "pinterface({{{s}}};{s};{s})",
            .{
                guidHex(IID_AsyncOperationWithProgressCompletedHandler_Open),
                runtimeSignature(T),
                runtimeSignature(P),
            },
        ));
    }

    fn asyncOperationProgressHandlerIid(comptime T: type, comptime P: type) GUID {
        return parameterizedIid(std.fmt.comptimePrint(
            "pinterface({{{s}}};{s};{s})",
            .{
                guidHex(IID_AsyncOperationProgressHandler_Open),
                runtimeSignature(T),
                runtimeSignature(P),
            },
        ));
    }

    fn parameterizedIid(comptime sig: []const u8) GUID {
        const namespace = [_]u8{
            0x11, 0xf4, 0x7a, 0xd5, 0x7b, 0x73, 0x42, 0xc0,
            0xab, 0xae, 0x87, 0x8b, 0x1e, 0x16, 0xad, 0xee,
        };

        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(&namespace);
        hasher.update(sig);

        var out: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
        hasher.final(&out);

        var bytes: [16]u8 = out[0..16].*;
        bytes[6] = (bytes[6] & 0x0f) | 0x50;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;

        return .{
            .data1 = std.mem.readInt(u32, bytes[0..4], .big),
            .data2 = std.mem.readInt(u16, bytes[4..6], .big),
            .data3 = std.mem.readInt(u16, bytes[6..8], .big),
            .data4 = bytes[8..16].*,
        };
    }

    fn runtimeSignature(comptime T: type) []const u8 {
        if (T == void) return "cinterface(IInspectable)";
        if (T == bool or T == win_core.BOOL) return "b1";
        if (T == i8) return "i1";
        if (T == u8) return "u1";
        if (T == i16) return "i2";
        if (T == u16) return "u2";
        if (T == i32) return "i4";
        if (T == u32) return "u4";
        if (T == i64) return "i8";
        if (T == u64) return "u8";
        if (T == f32) return "f4";
        if (T == f64) return "f8";
        if (T == isize) return "is";
        if (T == usize) return "us";
        if (T == win_core.HSTRING) return "string";

        switch (@typeInfo(T)) {
            .@"enum" => {
                return valueSignature(typeNameFromFullName(@typeName(T)));
            },
            .pointer => |pointer| {
                if (pointer.size != .one) {
                    @compileError("win-future only supports single-item pointers in async signatures");
                }
                return runtimeSignatureForPointee(pointer.child);
            },
            else => @compileError("unsupported async signature type: " ++ @typeName(T)),
        }
    }

    fn runtimeSignatureForPointee(comptime Pointee: type) []const u8 {
        if (@hasDecl(Pointee, "IID")) {
            return std.fmt.comptimePrint("{{{s}}}", .{guidHex(Pointee.IID)});
        }
        if (@hasDecl(Pointee, "NAME")) {
            return runtimeClassSignature(Pointee.NAME);
        }
        @compileError("unsupported projected WinRT type in async signature: " ++ @typeName(Pointee));
    }

    fn runtimeClassSignature(comptime full_name: []const u8) []const u8 {
        const type_name = typeNameFromFullName(full_name);
        return classSignature(type_name);
    }

    fn classSignature(comptime type_name: winmd.TypeName) []const u8 {
        const type_def = findTypeDef(type_name.namespace, type_name.name) orelse
            @compileError("type not found in embedded winmd metadata: " ++ type_name.namespace ++ "." ++ type_name.name);
        const flags = type_def.file.cell(.type_def, type_def.row, 0);
        const is_interface = (flags & winmd.TYPE_ATTR_INTERFACE) != 0;

        var is_delegate = false;
        if (!is_interface) {
            const extends_tok = type_def.file.cell(.type_def, type_def.row, 3);
            if (extends_tok != 0) {
                const base = winmd.resolveTypeDefOrRefName(type_def.file, extends_tok) catch
                    @compileError("failed to resolve base type for " ++ type_name.namespace ++ "." ++ type_name.name);
                if (std.mem.eql(u8, base.namespace, "System") and std.mem.eql(u8, base.name, "MulticastDelegate")) {
                    is_delegate = true;
                }
            }
        }

        if (is_interface) {
            const guid = readTypeDefGuid(type_def.file, type_def.row);
            if (type_name.generics.len == 0) {
                return std.fmt.comptimePrint("{{{s}}}", .{guidHex(guid)});
            }
            comptime var sig = std.fmt.comptimePrint("pinterface({{{s}}}", .{guidHex(guid)});
            inline for (type_name.generics) |generic_arg| {
                sig = sig ++ ";" ++ runtimeSignatureForTy(generic_arg);
            }
            return sig ++ ")";
        }

        if (is_delegate) {
            const guid = readTypeDefGuid(type_def.file, type_def.row);
            if (type_name.generics.len == 0) {
                return std.fmt.comptimePrint("delegate({{{s}}})", .{guidHex(guid)});
            }
            comptime var sig = std.fmt.comptimePrint("pinterface({{{s}}}", .{guidHex(guid)});
            inline for (type_name.generics) |generic_arg| {
                sig = sig ++ ";" ++ runtimeSignatureForTy(generic_arg);
            }
            return sig ++ ")";
        }

        const default_iface = defaultInterfaceTypeName(type_def.file, type_def.row) orelse
            @compileError("runtime class has no default interface: " ++ type_name.namespace ++ "." ++ type_name.name);
        return std.fmt.comptimePrint(
            "rc({s}.{s};{s})",
            .{ type_name.namespace, type_name.name, classSignature(default_iface) },
        );
    }

    fn runtimeSignatureForTy(comptime ty: winmd.Ty) []const u8 {
        return switch (ty) {
            .bool => "b1",
            .char => "c2",
            .i8 => "i1",
            .u8 => "u1",
            .i16 => "i2",
            .u16 => "u2",
            .i32 => "i4",
            .u32 => "u4",
            .i64 => "i8",
            .u64 => "u8",
            .f32 => "f4",
            .f64 => "f8",
            .isize => "is",
            .usize => "us",
            .string => "string",
            .object => "cinterface(IInspectable)",
            .value_name => |type_name| valueSignature(type_name),
            .class_name => |type_name| classSignature(type_name),
            else => @compileError("unsupported metadata type in runtime signature"),
        };
    }

    fn valueSignature(comptime type_name: winmd.TypeName) []const u8 {
        if (std.mem.eql(u8, type_name.namespace, "System") and std.mem.eql(u8, type_name.name, "Guid")) {
            return "g16";
        }

        const type_def = findTypeDef(type_name.namespace, type_name.name) orelse
            @compileError("value type not found in embedded winmd metadata: " ++ type_name.namespace ++ "." ++ type_name.name);
        const extends_tok = type_def.file.cell(.type_def, type_def.row, 3);
        if (extends_tok == 0) {
            @compileError("value type has no base type in embedded winmd metadata: " ++ type_name.namespace ++ "." ++ type_name.name);
        }
        const base = winmd.resolveTypeDefOrRefName(type_def.file, extends_tok) catch
            @compileError("failed to resolve base type for " ++ type_name.namespace ++ "." ++ type_name.name);
        if (std.mem.eql(u8, base.namespace, "System") and std.mem.eql(u8, base.name, "Enum")) {
            return enumSignature(type_def.file, type_name, type_def.row);
        }
        @compileError("unsupported WinRT value type in async signature: " ++ type_name.namespace ++ "." ++ type_name.name);
    }

    fn enumSignature(file: *const winmd.File, comptime type_name: winmd.TypeName, comptime row: u32) []const u8 {
        const fields = file.list(.type_def, row, 4, .field);
        comptime var field_row = fields.start;
        inline while (field_row < fields.end) : (field_row += 1) {
            if (!std.mem.eql(u8, file.str(.field, field_row, 1), "value__")) continue;
            return std.fmt.comptimePrint(
                "enum({s}.{s};{s})",
                .{
                    type_name.namespace,
                    type_name.name,
                    primitiveFieldSignature(file.blob(.field, field_row, 2)),
                },
            );
        }
        @compileError("enum value type is missing value__ field: " ++ type_name.namespace ++ "." ++ type_name.name);
    }

    fn primitiveFieldSignature(comptime blob: []const u8) []const u8 {
        if (blob.len != 2 or blob[0] != 0x06) {
            @compileError("expected primitive field signature blob");
        }

        return switch (blob[1]) {
            0x02 => "b1",
            0x03 => "c2",
            0x04 => "i1",
            0x05 => "u1",
            0x06 => "i2",
            0x07 => "u2",
            0x08 => "i4",
            0x09 => "u4",
            0x0A => "i8",
            0x0B => "u8",
            0x18 => "is",
            0x19 => "us",
            else => @compileError("unsupported primitive field signature element type"),
        };
    }

    fn typeNameFromFullName(comptime full_name: []const u8) winmd.TypeName {
        const split = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse
            @compileError("expected namespace-qualified WinRT type name");
        return .{
            .namespace = full_name[0..split],
            .name = full_name[split + 1 ..],
        };
    }

    fn findTypeDef(comptime namespace: []const u8, comptime name: []const u8) ?TypeDefRef {
        if (findTypeDefRowIn(&metadata, namespace, name)) |row| {
            return .{ .file = &metadata, .row = row };
        }
        if (findTypeDefRowIn(&winui_xaml_metadata, namespace, name)) |row| {
            return .{ .file = &winui_xaml_metadata, .row = row };
        }
        return null;
    }

    fn findTypeDefRowIn(file: *const winmd.File, comptime namespace: []const u8, comptime name: []const u8) ?u32 {
        @setEvalBranchQuota(2_000_000);
        const rows = file.rowCount(.type_def);
        comptime var row: u32 = 0;
        inline while (row < rows) : (row += 1) {
            if (std.mem.eql(u8, file.str(.type_def, row, 2), namespace) and
                std.mem.eql(u8, file.str(.type_def, row, 1), name))
            {
                return row;
            }
        }
        return null;
    }

    fn readTypeDefGuid(file: *const winmd.File, comptime type_def_row: u32) GUID {
        const attr_row = winmd.findAttribute(file, .type_def, type_def_row, "GuidAttribute") orelse
            @compileError("missing GuidAttribute in Windows.winmd");
        const blob = file.blob(.attribute, attr_row, 2);
        if (blob.len < 18) @compileError("unexpected GuidAttribute blob");
        if (blob[0] != 0x01 or blob[1] != 0x00) @compileError("bad GuidAttribute prolog");

        return .{
            .data1 = std.mem.readInt(u32, blob[2..6], .little),
            .data2 = std.mem.readInt(u16, blob[6..8], .little),
            .data3 = std.mem.readInt(u16, blob[8..10], .little),
            .data4 = blob[10..18].*,
        };
    }

    fn defaultInterfaceTypeName(file: *const winmd.File, comptime class_row: u32) ?winmd.TypeName {
        const impls = file.equalRange(.interface_impl, 0, class_row + 1);
        comptime var row = impls.start;
        inline while (row < impls.end) : (row += 1) {
            if (!winmd.hasAttribute(file, .interface_impl, row, "DefaultAttribute")) continue;
            const iface_token = file.cell(.interface_impl, row, 1);
            return winmd.resolveTypeDefOrRefName(file, iface_token) catch
                @compileError("failed to resolve default interface token");
        }
        return null;
    }

    fn guidHex(comptime guid: GUID) []const u8 {
        return std.fmt.comptimePrint(
            "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
            .{
                guid.data1,    guid.data2,    guid.data3,
                guid.data4[0], guid.data4[1], guid.data4[2],
                guid.data4[3], guid.data4[4], guid.data4[5],
                guid.data4[6], guid.data4[7],
            },
        );
    }

    fn IAsyncActionWithProgress_Vtbl(comptime P: type) type {
        _ = P;
        return extern struct {
            base: IInspectable_Vtbl,
            put_Progress: *const fn (this: *anyopaque, handler: ?*anyopaque) callconv(.winapi) HRESULT,
            get_Progress: *const fn (this: *anyopaque, result: **anyopaque) callconv(.winapi) HRESULT,
            put_Completed: *const fn (this: *anyopaque, handler: *anyopaque) callconv(.winapi) HRESULT,
            get_Completed: *const fn (this: *anyopaque, result: **anyopaque) callconv(.winapi) HRESULT,
            GetResults: *const fn (this: *anyopaque) callconv(.winapi) HRESULT,
        };
    }

    fn IAsyncOperationWithProgress_Vtbl(comptime T: type, comptime P: type) type {
        _ = P;
        return extern struct {
            base: IInspectable_Vtbl,
            put_Progress: *const fn (this: *anyopaque, handler: ?*anyopaque) callconv(.winapi) HRESULT,
            get_Progress: *const fn (this: *anyopaque, result: **anyopaque) callconv(.winapi) HRESULT,
            put_Completed: *const fn (this: *anyopaque, handler: *anyopaque) callconv(.winapi) HRESULT,
            get_Completed: *const fn (this: *anyopaque, result: **anyopaque) callconv(.winapi) HRESULT,
            GetResults: *const fn (this: *anyopaque, result: *T) callconv(.winapi) HRESULT,
        };
    }

    fn blockUntilDone(
        allocator: std.mem.Allocator,
        async_value: *anyopaque,
        put_completed_fn: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT,
        qi_fn: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        comptime completed_handler_iid: GUID,
    ) Error!void {
        const event = CreateEventW(null, 1, 0, null) orelse
            return hresult.toError(hresult.E_FAIL);
        defer _ = CloseHandle(event);

        const CompletedDelegate = win_core.Delegate(CompletedInvokeFn, completed_handler_iid);
        const completion_handler = try CompletedDelegate.create(
            allocator,
            &CompletedThunk(completed_handler_iid).invoke,
            @ptrCast(event),
        );
        const completion_hr = put_completed_fn(async_value, completion_handler);
        _ = CompletedDelegate.release(completion_handler);
        if (hresult.failed(completion_hr)) return hresult.toError(completion_hr);

        try waitAndCheckStatus(async_value, qi_fn, event);
    }

    fn blockUntilDoneWithProgress(
        comptime P: type,
        allocator: std.mem.Allocator,
        async_value: *anyopaque,
        put_progress_fn: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        put_completed_fn: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT,
        qi_fn: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        comptime progress_handler_iid: GUID,
        comptime completed_handler_iid: GUID,
        progress: ?ProgressCallback(P),
        context: ?*anyopaque,
    ) Error!void {
        const event = CreateEventW(null, 1, 0, null) orelse
            return hresult.toError(hresult.E_FAIL);
        defer _ = CloseHandle(event);

        var progress_state = ProgressState(P){
            .callback = progress,
            .context = context,
        };
        var progress_registered = false;

        if (progress != null) {
            const ProgressDelegate = win_core.Delegate(ProgressInvokeFn(P), progress_handler_iid);
            const progress_handler = try ProgressDelegate.create(
                allocator,
                &ProgressThunk(P, progress_handler_iid).invoke,
                @ptrCast(&progress_state),
            );
            const progress_hr = put_progress_fn(async_value, progress_handler);
            _ = ProgressDelegate.release(progress_handler);
            if (hresult.failed(progress_hr)) return hresult.toError(progress_hr);
            progress_registered = true;
        }

        const CompletedDelegate = win_core.Delegate(CompletedInvokeFn, completed_handler_iid);
        const completion_handler = try CompletedDelegate.create(
            allocator,
            &CompletedThunk(completed_handler_iid).invoke,
            @ptrCast(event),
        );
        const completion_hr = put_completed_fn(async_value, completion_handler);
        _ = CompletedDelegate.release(completion_handler);
        if (hresult.failed(completion_hr)) {
            if (progress_registered) {
                _ = put_progress_fn(async_value, null);
            }
            return hresult.toError(completion_hr);
        }

        try waitAndCheckStatus(async_value, qi_fn, event);
    }

    fn waitAndCheckStatus(
        async_value: *anyopaque,
        qi_fn: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        event: HANDLE,
    ) Error!void {
        const wait_result = WaitForSingleObject(event, INFINITE);
        if (wait_result != WAIT_OBJECT_0) return hresult.toError(hresult.E_FAIL);

        var async_info: ?*anyopaque = null;
        try hresult.ok(qi_fn(async_value, &IID_IAsyncInfo, &async_info));
        const info_ptr = async_info orelse return hresult.toError(hresult.E_POINTER);
        const info_vtbl: *const IAsyncInfo_Vtbl = @as(
            *const *const IAsyncInfo_Vtbl,
            @ptrCast(@alignCast(info_ptr)),
        ).*;
        defer _ = info_vtbl.base.base.Release(info_ptr);

        var status: AsyncStatus = .Started;
        try hresult.ok(info_vtbl.get_Status(info_ptr, &status));

        switch (status) {
            .Completed => return,
            .Canceled => return error.Aborted,
            .Error => {
                var error_code: WinrtHResult = .{ .Value = 0 };
                _ = info_vtbl.get_ErrorCode(info_ptr, &error_code);
                return hresult.toError(error_code.Value);
            },
            else => return hresult.toError(hresult.E_FAIL),
        }
    }

    fn ensureTupleOfDescriptors(comptime AsyncTuple: type) void {
        const info = @typeInfo(AsyncTuple);
        if (info != .@"struct" or !info.@"struct".is_tuple) {
            @compileError("Async.join/when expect a tuple of Async.action/operation handles.");
        }
        inline for (std.meta.fields(AsyncTuple)) |field| {
            if (!@hasDecl(field.type, "Result") or !@hasDecl(field.type, "wait")) {
                @compileError("Async.join/when only accept values produced by Async.action/operation helpers.");
            }
        }
    }

    fn opaquePtr(ptr: anytype) *anyopaque {
        const T = @TypeOf(ptr);
        if (@typeInfo(T) != .pointer) {
            @compileError("expected a non-null interface pointer");
        }
        return @ptrCast(@constCast(ptr));
    }
};

fn mockInspNoop3(_: *anyopaque, _: *u32, _: *?[*]GUID) callconv(.winapi) HRESULT {
    return hresult.E_NOTIMPL;
}

fn mockInspClassName(_: *anyopaque, _: *HSTRING) callconv(.winapi) HRESULT {
    return hresult.E_NOTIMPL;
}

fn mockInspTrustLevel(_: *anyopaque, _: *i32) callconv(.winapi) HRESULT {
    return hresult.E_NOTIMPL;
}

fn handlerVtbl(handler_ptr: *anyopaque) *const IUnknown_Vtbl {
    return @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(handler_ptr))).*;
}

fn addHandlerRef(handler_ptr: *anyopaque) void {
    _ = handlerVtbl(handler_ptr).AddRef(handler_ptr);
}

fn releaseHandlerRef(handler_ptr: *anyopaque) void {
    _ = handlerVtbl(handler_ptr).Release(handler_ptr);
}

fn invokeCompletedHandler(comptime iid: GUID, handler_ptr: *anyopaque, sender: *anyopaque) void {
    const vtbl = @as(
        *const win_core.Delegate(Async.CompletedInvokeFn, iid)._Vtbl,
        @ptrCast(@alignCast(handlerVtbl(handler_ptr))),
    );
    _ = vtbl.Invoke(handler_ptr, sender, .Completed);
}

fn invokeProgressHandler(comptime P: type, comptime iid: GUID, handler_ptr: *anyopaque, sender: *anyopaque, value: P) void {
    const vtbl = @as(
        *const win_core.Delegate(Async.ProgressInvokeFn(P), iid)._Vtbl,
        @ptrCast(@alignCast(handlerVtbl(handler_ptr))),
    );
    _ = vtbl.Invoke(handler_ptr, sender, value);
}

const SimpleAsyncOperationI32 = struct {
    vtbl_ptr: *const win_core.Async.IAsyncOperation_Vtbl(i32) = &op_vtbl,
    info_vtbl_ptr: *const Async.IAsyncInfo_Vtbl = &info_vtbl,
    refcount: u32 = 1,
    result_value: i32,

    const op_vtbl = win_core.Async.IAsyncOperation_Vtbl(i32){
        .base = .{
            .base = .{
                .QueryInterface = qi,
                .AddRef = addRef,
                .Release = release,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .put_Completed = putCompleted,
        .get_Completed = getCompleted,
        .GetResults = getResults,
    };

    const info_vtbl = Async.IAsyncInfo_Vtbl{
        .base = .{
            .base = .{
                .QueryInterface = infoQI,
                .AddRef = infoAddRef,
                .Release = infoRelease,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .get_Id = getId,
        .get_Status = getStatus,
        .get_ErrorCode = getErrorCode,
        .Cancel = noop,
        .Close = noop,
    };

    fn init(result_value: i32) SimpleAsyncOperationI32 {
        return .{ .result_value = result_value };
    }

    fn fromInfoFace(this: *anyopaque) *SimpleAsyncOperationI32 {
        const ptr: [*]u8 = @ptrCast(this);
        return @ptrCast(@alignCast(ptr - @offsetOf(SimpleAsyncOperationI32, "info_vtbl_ptr")));
    }

    fn qi(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationI32 = @ptrCast(@alignCast(this));
        if (std.meta.eql(riid.*, Async.IID_IAsyncInfo)) {
            self.refcount += 1;
            out.* = @ptrCast(&self.info_vtbl_ptr);
            return hresult.S_OK;
        }
        if (std.meta.eql(riid.*, win_core.IID_IUnknown)) {
            self.refcount += 1;
            out.* = this;
            return hresult.S_OK;
        }
        out.* = null;
        return hresult.E_NOINTERFACE;
    }

    fn addRef(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncOperationI32 = @ptrCast(@alignCast(this));
        self.refcount += 1;
        return self.refcount;
    }

    fn release(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncOperationI32 = @ptrCast(@alignCast(this));
        if (self.refcount > 0) self.refcount -= 1;
        return self.refcount;
    }

    fn infoQI(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        return qi(@ptrCast(fromInfoFace(this)), riid, out);
    }

    fn infoAddRef(this: *anyopaque) callconv(.winapi) u32 {
        return addRef(@ptrCast(fromInfoFace(this)));
    }

    fn infoRelease(this: *anyopaque) callconv(.winapi) u32 {
        return release(@ptrCast(fromInfoFace(this)));
    }

    fn putCompleted(this: *anyopaque, handler_ptr: *anyopaque) callconv(.winapi) HRESULT {
        addHandlerRef(handler_ptr);
        invokeCompletedHandler(Async.asyncOperationCompletedHandlerIid(i32), handler_ptr, this);
        releaseHandlerRef(handler_ptr);
        return hresult.S_OK;
    }

    fn getCompleted(_: *anyopaque, _: **anyopaque) callconv(.winapi) HRESULT {
        return hresult.E_NOTIMPL;
    }

    fn getResults(this: *anyopaque, result: *i32) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationI32 = @ptrCast(@alignCast(this));
        result.* = self.result_value;
        return hresult.S_OK;
    }

    fn getId(_: *anyopaque, result: *u32) callconv(.winapi) HRESULT {
        result.* = 1;
        return hresult.S_OK;
    }

    fn getStatus(_: *anyopaque, result: *Async.AsyncStatus) callconv(.winapi) HRESULT {
        result.* = .Completed;
        return hresult.S_OK;
    }

    fn getErrorCode(_: *anyopaque, result: *Async.WinrtHResult) callconv(.winapi) HRESULT {
        result.* = .{ .Value = 0 };
        return hresult.S_OK;
    }

    fn noop(_: *anyopaque) callconv(.winapi) HRESULT {
        return hresult.S_OK;
    }
};

const SimpleAsyncActionWithProgressI32 = struct {
    vtbl_ptr: *const Async.IAsyncActionWithProgress_Vtbl(i32) = &action_vtbl,
    info_vtbl_ptr: *const Async.IAsyncInfo_Vtbl = &info_vtbl,
    refcount: u32 = 1,
    progress_value: i32,
    progress_handler: ?*anyopaque = null,
    completed_handler: ?*anyopaque = null,
    fired: bool = false,

    const action_vtbl = Async.IAsyncActionWithProgress_Vtbl(i32){
        .base = .{
            .base = .{
                .QueryInterface = qi,
                .AddRef = addRef,
                .Release = release,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .put_Progress = putProgress,
        .get_Progress = getProgress,
        .put_Completed = putCompleted,
        .get_Completed = getCompleted,
        .GetResults = getResults,
    };

    const info_vtbl = Async.IAsyncInfo_Vtbl{
        .base = .{
            .base = .{
                .QueryInterface = infoQI,
                .AddRef = infoAddRef,
                .Release = infoRelease,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .get_Id = getId,
        .get_Status = getStatus,
        .get_ErrorCode = getErrorCode,
        .Cancel = noop,
        .Close = noop,
    };

    fn init(progress_value: i32) SimpleAsyncActionWithProgressI32 {
        return .{ .progress_value = progress_value };
    }

    fn fromInfoFace(this: *anyopaque) *SimpleAsyncActionWithProgressI32 {
        const ptr: [*]u8 = @ptrCast(this);
        return @ptrCast(@alignCast(ptr - @offsetOf(SimpleAsyncActionWithProgressI32, "info_vtbl_ptr")));
    }

    fn qi(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncActionWithProgressI32 = @ptrCast(@alignCast(this));
        if (std.meta.eql(riid.*, Async.IID_IAsyncInfo)) {
            self.refcount += 1;
            out.* = @ptrCast(&self.info_vtbl_ptr);
            return hresult.S_OK;
        }
        if (std.meta.eql(riid.*, win_core.IID_IUnknown)) {
            self.refcount += 1;
            out.* = this;
            return hresult.S_OK;
        }
        out.* = null;
        return hresult.E_NOINTERFACE;
    }

    fn addRef(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncActionWithProgressI32 = @ptrCast(@alignCast(this));
        self.refcount += 1;
        return self.refcount;
    }

    fn release(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncActionWithProgressI32 = @ptrCast(@alignCast(this));
        if (self.refcount > 0) self.refcount -= 1;
        return self.refcount;
    }

    fn infoQI(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        return qi(@ptrCast(fromInfoFace(this)), riid, out);
    }

    fn infoAddRef(this: *anyopaque) callconv(.winapi) u32 {
        return addRef(@ptrCast(fromInfoFace(this)));
    }

    fn infoRelease(this: *anyopaque) callconv(.winapi) u32 {
        return release(@ptrCast(fromInfoFace(this)));
    }

    fn putProgress(this: *anyopaque, handler_ptr: ?*anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncActionWithProgressI32 = @ptrCast(@alignCast(this));
        if (handler_ptr == null) {
            if (self.progress_handler) |handler| releaseHandlerRef(handler);
            self.progress_handler = null;
            return hresult.S_OK;
        }
        addHandlerRef(handler_ptr.?);
        self.progress_handler = handler_ptr.?;
        self.maybeFire(this);
        return hresult.S_OK;
    }

    fn getProgress(_: *anyopaque, _: **anyopaque) callconv(.winapi) HRESULT {
        return hresult.E_NOTIMPL;
    }

    fn putCompleted(this: *anyopaque, handler_ptr: *anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncActionWithProgressI32 = @ptrCast(@alignCast(this));
        addHandlerRef(handler_ptr);
        self.completed_handler = handler_ptr;
        self.maybeFire(this);
        return hresult.S_OK;
    }

    fn getCompleted(_: *anyopaque, _: **anyopaque) callconv(.winapi) HRESULT {
        return hresult.E_NOTIMPL;
    }

    fn getResults(_: *anyopaque) callconv(.winapi) HRESULT {
        return hresult.S_OK;
    }

    fn getId(_: *anyopaque, result: *u32) callconv(.winapi) HRESULT {
        result.* = 2;
        return hresult.S_OK;
    }

    fn getStatus(_: *anyopaque, result: *Async.AsyncStatus) callconv(.winapi) HRESULT {
        result.* = .Completed;
        return hresult.S_OK;
    }

    fn getErrorCode(_: *anyopaque, result: *Async.WinrtHResult) callconv(.winapi) HRESULT {
        result.* = .{ .Value = 0 };
        return hresult.S_OK;
    }

    fn noop(_: *anyopaque) callconv(.winapi) HRESULT {
        return hresult.S_OK;
    }

    fn maybeFire(self: *SimpleAsyncActionWithProgressI32, sender: *anyopaque) void {
        if (self.fired or self.completed_handler == null) return;
        self.fired = true;

        if (self.progress_handler) |handler| {
            invokeProgressHandler(i32, Async.asyncActionProgressHandlerIid(i32), handler, sender, self.progress_value);
        }
        invokeCompletedHandler(Async.asyncActionWithProgressCompletedHandlerIid(i32), self.completed_handler.?, sender);

        if (self.progress_handler) |handler| {
            releaseHandlerRef(handler);
            self.progress_handler = null;
        }
        releaseHandlerRef(self.completed_handler.?);
        self.completed_handler = null;
    }
};

const SimpleAsyncOperationWithProgressI32 = struct {
    vtbl_ptr: *const Async.IAsyncOperationWithProgress_Vtbl(i32, i32) = &op_vtbl,
    info_vtbl_ptr: *const Async.IAsyncInfo_Vtbl = &info_vtbl,
    refcount: u32 = 1,
    result_value: i32,
    progress_value: i32,
    progress_handler: ?*anyopaque = null,
    completed_handler: ?*anyopaque = null,
    fired: bool = false,

    const op_vtbl = Async.IAsyncOperationWithProgress_Vtbl(i32, i32){
        .base = .{
            .base = .{
                .QueryInterface = qi,
                .AddRef = addRef,
                .Release = release,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .put_Progress = putProgress,
        .get_Progress = getProgress,
        .put_Completed = putCompleted,
        .get_Completed = getCompleted,
        .GetResults = getResults,
    };

    const info_vtbl = Async.IAsyncInfo_Vtbl{
        .base = .{
            .base = .{
                .QueryInterface = infoQI,
                .AddRef = infoAddRef,
                .Release = infoRelease,
            },
            .GetIids = mockInspNoop3,
            .GetRuntimeClassName = mockInspClassName,
            .GetTrustLevel = mockInspTrustLevel,
        },
        .get_Id = getId,
        .get_Status = getStatus,
        .get_ErrorCode = getErrorCode,
        .Cancel = noop,
        .Close = noop,
    };

    fn init(result_value: i32, progress_value: i32) SimpleAsyncOperationWithProgressI32 {
        return .{
            .result_value = result_value,
            .progress_value = progress_value,
        };
    }

    fn fromInfoFace(this: *anyopaque) *SimpleAsyncOperationWithProgressI32 {
        const ptr: [*]u8 = @ptrCast(this);
        return @ptrCast(@alignCast(ptr - @offsetOf(SimpleAsyncOperationWithProgressI32, "info_vtbl_ptr")));
    }

    fn qi(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        if (std.meta.eql(riid.*, Async.IID_IAsyncInfo)) {
            self.refcount += 1;
            out.* = @ptrCast(&self.info_vtbl_ptr);
            return hresult.S_OK;
        }
        if (std.meta.eql(riid.*, win_core.IID_IUnknown)) {
            self.refcount += 1;
            out.* = this;
            return hresult.S_OK;
        }
        out.* = null;
        return hresult.E_NOINTERFACE;
    }

    fn addRef(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        self.refcount += 1;
        return self.refcount;
    }

    fn release(this: *anyopaque) callconv(.winapi) u32 {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        if (self.refcount > 0) self.refcount -= 1;
        return self.refcount;
    }

    fn infoQI(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
        return qi(@ptrCast(fromInfoFace(this)), riid, out);
    }

    fn infoAddRef(this: *anyopaque) callconv(.winapi) u32 {
        return addRef(@ptrCast(fromInfoFace(this)));
    }

    fn infoRelease(this: *anyopaque) callconv(.winapi) u32 {
        return release(@ptrCast(fromInfoFace(this)));
    }

    fn putProgress(this: *anyopaque, handler_ptr: ?*anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        if (handler_ptr == null) {
            if (self.progress_handler) |handler| releaseHandlerRef(handler);
            self.progress_handler = null;
            return hresult.S_OK;
        }
        addHandlerRef(handler_ptr.?);
        self.progress_handler = handler_ptr.?;
        self.maybeFire(this);
        return hresult.S_OK;
    }

    fn getProgress(_: *anyopaque, _: **anyopaque) callconv(.winapi) HRESULT {
        return hresult.E_NOTIMPL;
    }

    fn putCompleted(this: *anyopaque, handler_ptr: *anyopaque) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        addHandlerRef(handler_ptr);
        self.completed_handler = handler_ptr;
        self.maybeFire(this);
        return hresult.S_OK;
    }

    fn getCompleted(_: *anyopaque, _: **anyopaque) callconv(.winapi) HRESULT {
        return hresult.E_NOTIMPL;
    }

    fn getResults(this: *anyopaque, result: *i32) callconv(.winapi) HRESULT {
        const self: *SimpleAsyncOperationWithProgressI32 = @ptrCast(@alignCast(this));
        result.* = self.result_value;
        return hresult.S_OK;
    }

    fn getId(_: *anyopaque, result: *u32) callconv(.winapi) HRESULT {
        result.* = 3;
        return hresult.S_OK;
    }

    fn getStatus(_: *anyopaque, result: *Async.AsyncStatus) callconv(.winapi) HRESULT {
        result.* = .Completed;
        return hresult.S_OK;
    }

    fn getErrorCode(_: *anyopaque, result: *Async.WinrtHResult) callconv(.winapi) HRESULT {
        result.* = .{ .Value = 0 };
        return hresult.S_OK;
    }

    fn noop(_: *anyopaque) callconv(.winapi) HRESULT {
        return hresult.S_OK;
    }

    fn maybeFire(self: *SimpleAsyncOperationWithProgressI32, sender: *anyopaque) void {
        if (self.fired or self.completed_handler == null) return;
        self.fired = true;

        if (self.progress_handler) |handler| {
            invokeProgressHandler(
                i32,
                Async.asyncOperationProgressHandlerIid(i32, i32),
                handler,
                sender,
                self.progress_value,
            );
        }
        invokeCompletedHandler(
            Async.asyncOperationWithProgressCompletedHandlerIid(i32, i32),
            self.completed_handler.?,
            sender,
        );

        if (self.progress_handler) |handler| {
            releaseHandlerRef(handler);
            self.progress_handler = null;
        }
        releaseHandlerRef(self.completed_handler.?);
        self.completed_handler = null;
    }
};

test "Async.waitWithProgress forwards action progress" {
    if (builtin.target.os.tag != .windows) return error.SkipZigTest;

    const State = struct {
        fired: u32 = 0,
        last: i32 = 0,
    };

    var state: State = .{};
    var action = SimpleAsyncActionWithProgressI32.init(7);

    const onProgress = struct {
        fn run(context: ?*anyopaque, value: i32) void {
            const s: *State = @ptrCast(@alignCast(context.?));
            s.fired += 1;
            s.last = value;
        }
    }.run;

    try Async.waitWithProgress(
        i32,
        std.testing.allocator,
        &action,
        &onProgress,
        @ptrCast(&state),
    );
    try std.testing.expectEqual(@as(u32, 1), state.fired);
    try std.testing.expectEqual(@as(i32, 7), state.last);
}

test "Async.waitResultWithProgress returns value and progress" {
    if (builtin.target.os.tag != .windows) return error.SkipZigTest;

    const State = struct {
        fired: u32 = 0,
        last: i32 = 0,
    };

    var state: State = .{};
    var operation = SimpleAsyncOperationWithProgressI32.init(42, 11);

    const onProgress = struct {
        fn run(context: ?*anyopaque, value: i32) void {
            const s: *State = @ptrCast(@alignCast(context.?));
            s.fired += 1;
            s.last = value;
        }
    }.run;

    const result = try Async.waitResultWithProgress(
        i32,
        i32,
        std.testing.allocator,
        &operation,
        &onProgress,
        @ptrCast(&state),
    );
    try std.testing.expectEqual(@as(i32, 42), result);
    try std.testing.expectEqual(@as(u32, 1), state.fired);
    try std.testing.expectEqual(@as(i32, 11), state.last);
}

test "Async.join returns tupled results" {
    if (builtin.target.os.tag != .windows) return error.SkipZigTest;

    var left = SimpleAsyncOperationI32.init(20);
    var right = SimpleAsyncOperationI32.init(22);

    const results = try Async.join(std.testing.allocator, .{
        Async.operation(i32, &left),
        Async.operation(i32, &right),
    });

    try std.testing.expectEqual(@as(i32, 20), results.@"0");
    try std.testing.expectEqual(@as(i32, 22), results.@"1");
}

test "Async.when invokes callback with joined results" {
    if (builtin.target.os.tag != .windows) return error.SkipZigTest;

    const State = struct {
        fired: u32 = 0,
        sum: i32 = 0,
    };

    var state: State = .{};
    var left = SimpleAsyncOperationI32.init(19);
    var right = SimpleAsyncOperationI32.init(23);

    const operations = .{
        Async.operation(i32, &left),
        Async.operation(i32, &right),
    };
    const Joined = Async.JoinResult(@TypeOf(operations));

    const Callback = struct {
        fn run(s: *State, results: Joined) void {
            s.fired += 1;
            s.sum = results.@"0" + results.@"1";
        }
    };

    try Async.when(std.testing.allocator, operations, &state, Callback.run);
    try std.testing.expectEqual(@as(u32, 1), state.fired);
    try std.testing.expectEqual(@as(i32, 42), state.sum);
}
