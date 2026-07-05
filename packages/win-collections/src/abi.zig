const std = @import("std");
const core = @import("win-core");

pub const CollectionError = core.hresult.Error || error{OutOfMemory};

pub const EventRegistrationToken = extern struct {
    Value: i64,
};

pub fn Entry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
    };
}

pub fn BufferElement(comptime T: type) type {
    if (isStringType(T)) return core.HSTRING;
    if (isInterfaceType(T)) return ?T;
    return T;
}

pub fn StoredType(comptime T: type) type {
    if (isStringType(T)) return core.Hstring;
    if (isInterfaceType(T)) return ?T;
    return T;
}

pub fn defaultBuffer(comptime T: type) BufferElement(T) {
    return std.mem.zeroes(BufferElement(T));
}

pub fn defaultStored(comptime T: type) StoredType(T) {
    return std.mem.zeroes(StoredType(T));
}

pub fn isStringType(comptime T: type) bool {
    return T == core.Hstring;
}

pub fn isObjectType(comptime T: type) bool {
    return T == ?*const anyopaque or T == ?*anyopaque;
}

pub fn isInterfaceType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const p = info.pointer;
    return p.size == .one and @hasDecl(p.child, "Vtbl") and @hasDecl(p.child, "IID");
}

fn canHaveDecls(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };
}

pub fn isSupportedValueType(comptime T: type) bool {
    if (isStringType(T) or isObjectType(T) or isInterfaceType(T)) return true;
    if (canHaveDecls(T) and @hasDecl(T, "SIGNATURE")) return true;
    return switch (@typeInfo(T)) {
        .bool => true,
        .int => true,
        .float => true,
        .@"enum" => true,
        else => false,
    };
}

pub fn typeName(comptime T: type) []const u8 {
    if (isStringType(T)) return "String";
    if (isObjectType(T)) return "Object";
    if (canHaveDecls(T) and @hasDecl(T, "NAME")) return T.NAME;

    if (isInterfaceType(T)) {
        const child = @typeInfo(T).pointer.child;
        if (@hasDecl(child, "NAME")) return child.NAME;
        @compileError("interface type parameter is missing NAME: " ++ @typeName(child));
    }

    return switch (T) {
        bool => "Boolean",
        i8 => "Int8",
        u8 => "UInt8",
        i16 => "Int16",
        u16 => "UInt16",
        i32 => "Int32",
        u32 => "UInt32",
        i64 => "Int64",
        u64 => "UInt64",
        f32 => "Single",
        f64 => "Double",
        else => switch (@typeInfo(T)) {
            .@"enum" => if (@hasDecl(T, "NAME")) T.NAME else @compileError("enum type parameter is missing NAME"),
            else => @compileError("unsupported type parameter for WinRT collections: " ++ @typeName(T)),
        },
    };
}

pub fn guidSignature(comptime guid: core.GUID) []const u8 {
    return std.fmt.comptimePrint(
        "{{{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}}}",
        .{
            guid.data1,    guid.data2,    guid.data3,
            guid.data4[0], guid.data4[1], guid.data4[2],
            guid.data4[3], guid.data4[4], guid.data4[5],
            guid.data4[6], guid.data4[7],
        },
    );
}

pub fn signatureOf(comptime T: type) []const u8 {
    if (isStringType(T)) return "string";
    if (isObjectType(T)) return "cinterface(IInspectable)";
    if (canHaveDecls(T) and @hasDecl(T, "SIGNATURE")) return T.SIGNATURE;

    if (isInterfaceType(T)) {
        const child = @typeInfo(T).pointer.child;
        if (@hasDecl(child, "SIGNATURE")) return child.SIGNATURE;
        return guidSignature(child.IID);
    }

    return switch (T) {
        bool => "b1",
        i8 => "i1",
        u8 => "u1",
        i16 => "i2",
        u16 => "u2",
        i32 => "i4",
        u32 => "u4",
        i64 => "i8",
        u64 => "u8",
        f32 => "f4",
        f64 => "f8",
        else => if (@hasDecl(T, "SIGNATURE")) T.SIGNATURE else @compileError("unsupported type parameter for WinRT collections: " ++ @typeName(T)),
    };
}

pub fn nameG1(comptime base: []const u8, comptime T: type) []const u8 {
    return std.fmt.comptimePrint("{s}<{s}>", .{ base, typeName(T) });
}

pub fn nameG2(comptime base: []const u8, comptime K: type, comptime V: type) []const u8 {
    return std.fmt.comptimePrint("{s}<{s}, {s}>", .{ base, typeName(K), typeName(V) });
}

pub fn signatureG1(comptime open_iid: core.GUID, comptime T: type) []const u8 {
    return std.fmt.comptimePrint("pinterface({s};{s})", .{
        guidSignature(open_iid),
        signatureOf(T),
    });
}

pub fn signatureG2(comptime open_iid: core.GUID, comptime K: type, comptime V: type) []const u8 {
    return std.fmt.comptimePrint("pinterface({s};{s};{s})", .{
        guidSignature(open_iid),
        signatureOf(K),
        signatureOf(V),
    });
}

pub fn parameterizedIid(comptime sig: []const u8) core.GUID {
    @setEvalBranchQuota(20_000);
    const namespace = [_]u8{
        0x11, 0xf4, 0x7a, 0xd5, 0x7b, 0x73, 0x42, 0xc0,
        0xab, 0xae, 0x87, 0x8b, 0x1e, 0x16, 0xad, 0xee,
    };
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(&namespace);
    hasher.update(sig);
    var out: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    hasher.final(&out);

    var b: [16]u8 = out[0..16].*;
    b[6] = (b[6] & 0x0f) | 0x50;
    b[8] = (b[8] & 0x3f) | 0x80;

    return .{
        .data1 = std.mem.readInt(u32, b[0..4], .big),
        .data2 = std.mem.readInt(u16, b[4..6], .big),
        .data3 = std.mem.readInt(u16, b[6..8], .big),
        .data4 = b[8..16].*,
    };
}

pub fn cloneInput(comptime T: type, value: T) CollectionError!StoredType(T) {
    if (comptime isStringType(T)) {
        return try value.clone();
    }
    if (comptime isObjectType(T)) {
        if (value) |p| {
            addRefAny(p);
        }
        return value;
    }
    if (comptime isInterfaceType(T)) {
        value.AddRef();
        return value;
    }
    return value;
}

pub fn cloneStored(comptime T: type, value: StoredType(T)) CollectionError!StoredType(T) {
    if (comptime isStringType(T)) {
        return try value.clone();
    }
    if (comptime isObjectType(T)) {
        if (value) |p| {
            addRefAny(p);
        }
        return value;
    }
    if (comptime isInterfaceType(T)) {
        if (value) |p| {
            p.AddRef();
        }
        return value;
    }
    return value;
}

pub fn releaseValue(comptime T: type, value: *T) void {
    if (comptime isStringType(T)) {
        value.deinit();
        return;
    }
    if (comptime isObjectType(T)) {
        if (value.*) |p| releaseAny(p);
        return;
    }
    if (comptime isInterfaceType(T)) {
        value.*.Release();
        return;
    }
}

pub fn releaseStored(comptime T: type, value: *StoredType(T)) void {
    if (comptime isStringType(T)) {
        value.deinit();
        value.* = .{};
        return;
    }
    if (comptime isObjectType(T)) {
        if (value.*) |p| releaseAny(p);
        value.* = null;
        return;
    }
    if (comptime isInterfaceType(T)) {
        if (value.*) |p| {
            _ = p.Release();
        }
        value.* = null;
        return;
    }
}

pub fn releaseBufferElement(comptime T: type, value: *BufferElement(T)) void {
    if (comptime isStringType(T)) {
        _ = core.combase.WindowsDeleteString(value.*);
        value.* = null;
        return;
    }
    if (comptime isObjectType(T)) {
        if (value.*) |p| releaseAny(p);
        value.* = null;
        return;
    }
    if (comptime isInterfaceType(T)) {
        if (value.*) |p| {
            _ = p.Release();
        }
        value.* = null;
        return;
    }
}

pub fn releaseBuffer(comptime T: type, values: []BufferElement(T)) void {
    for (values) |*value| releaseBufferElement(T, value);
}

pub fn equalsStored(comptime T: type, a: StoredType(T), b: StoredType(T)) bool {
    if (comptime isStringType(T)) return core.Hstring.eql(a, b);
    return std.meta.eql(a, b);
}

pub fn equalsStoredInput(comptime T: type, stored: StoredType(T), value: T) bool {
    if (comptime isStringType(T)) return core.Hstring.eql(stored, value);
    if (comptime isInterfaceType(T)) return stored == value;
    return std.meta.eql(stored, value);
}

pub fn fillAbiClone(comptime T: type, value: StoredType(T), out: *BufferElement(T)) CollectionError!void {
    if (@intFromPtr(out) == 0) return error.Pointer;
    if (comptime isStringType(T)) {
        const cloned = try value.clone();
        out.* = cloned.raw;
        return;
    }
    if (comptime isObjectType(T)) {
        if (value) |p| addRefAny(p);
        out.* = value;
        return;
    }
    if (comptime isInterfaceType(T)) {
        if (value) |p| _ = p.AddRef();
        out.* = value;
        return;
    }
    out.* = value;
}

pub fn takeAbiValue(comptime T: type, value: *BufferElement(T)) core.hresult.Error!T {
    if (comptime isStringType(T)) {
        const raw = value.*;
        value.* = null;
        return core.Hstring.fromRaw(raw);
    }
    if (comptime isObjectType(T)) {
        const raw = value.*;
        value.* = null;
        return raw;
    }
    if (comptime isInterfaceType(T)) {
        const raw = value.*;
        value.* = null;
        return raw orelse error.Pointer;
    }
    return value.*;
}

pub fn borrowedAbiValue(comptime T: type, value: BufferElement(T)) core.hresult.Error!T {
    if (comptime isStringType(T)) return core.Hstring.fromRaw(value);
    if (comptime isObjectType(T)) return value;
    if (comptime isInterfaceType(T)) return value orelse error.Pointer;
    return value;
}

pub fn valueToAbiParam(comptime T: type, value: T) BufferElement(T) {
    if (comptime isStringType(T)) return value.raw;
    if (comptime isObjectType(T) or isInterfaceType(T)) return value;
    return value;
}

pub fn storedToValue(comptime T: type, value: StoredType(T)) CollectionError!T {
    if (comptime isStringType(T)) return try value.clone();
    if (comptime isObjectType(T)) return value;
    if (comptime isInterfaceType(T)) return value orelse error.Pointer;
    return value;
}

pub fn toHRESULT(err: anyerror) core.HRESULT {
    return switch (err) {
        error.Aborted => core.hresult.E_ABORT,
        error.AccessDenied => core.hresult.E_ACCESSDENIED,
        error.Bounds => core.hresult.E_BOUNDS,
        error.Fail => core.hresult.E_FAIL,
        error.InvalidArg => core.hresult.E_INVALIDARG,
        error.NoInterface => core.hresult.E_NOINTERFACE,
        error.NotImplemented => core.hresult.E_NOTIMPL,
        error.OutOfMemory => core.hresult.E_OUTOFMEMORY,
        error.Pointer => core.hresult.E_POINTER,
        error.Unknown => core.hresult.last_hresult,
        else => core.hresult.E_FAIL,
    };
}

pub fn addRefAny(ptr: anytype) void {
    const raw: *anyopaque = @ptrCast(@constCast(ptr));
    const vtbl: *const core.IUnknown_Vtbl = @as(
        *const *const core.IUnknown_Vtbl,
        @ptrCast(@alignCast(raw)),
    ).*;
    _ = vtbl.AddRef(raw);
}

pub fn releaseAny(ptr: anytype) void {
    const raw: *anyopaque = @ptrCast(@constCast(ptr));
    const vtbl: *const core.IUnknown_Vtbl = @as(
        *const *const core.IUnknown_Vtbl,
        @ptrCast(@alignCast(raw)),
    ).*;
    _ = vtbl.Release(raw);
}
