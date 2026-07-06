const std = @import("std");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const Color = extern struct {
    A: u8 = 0xff,
    R: u8 = 0,
    G: u8 = 0,
    B: u8 = 0,
};

pub const IBrush_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IBrush = extern struct {
    vtable: *const IBrush_Vtbl,
    pub const Vtbl = IBrush_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x2DE3CB83,
        .data2 = 0x1329,
        .data3 = 0x5679,
        .data4 = .{ 0x88, 0xF8, 0xC8, 0x22, 0xBC, 0x54, 0x42, 0xCB },
    };

    pub fn QueryInterface(self: *const IBrush, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IBrush) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IBrush) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IBrush, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const Brush = extern struct {
    vtable: *const IBrush_Vtbl,
};

pub const ISolidColorBrush_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Color: *const fn (this: *const ISolidColorBrush, result: *Color) callconv(.winapi) HRESULT,
    put_Color: *const fn (this: *const ISolidColorBrush, value: Color) callconv(.winapi) HRESULT,
};

pub const ISolidColorBrush = extern struct {
    vtable: *const ISolidColorBrush_Vtbl,
    pub const Vtbl = ISolidColorBrush_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xB3865C31,
        .data2 = 0x37C8,
        .data3 = 0x55C1,
        .data4 = .{ 0x8A, 0x72, 0xD4, 0x1C, 0x67, 0x64, 0x2E, 0x2A },
    };

    pub fn QueryInterface(self: *const ISolidColorBrush, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ISolidColorBrush) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ISolidColorBrush) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const ISolidColorBrush, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Color(self: *const ISolidColorBrush, value: Color) callconv(.winapi) HRESULT {
        return self.vtable.put_Color(self, value);
    }
};

pub const SolidColorBrush = extern struct {
    vtable: *const ISolidColorBrush_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Media.SolidColorBrush";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*SolidColorBrush {
        const raw = try win_core.activateInstance(ISolidColorBrush, &NAME_W);
        return @ptrCast(raw);
    }
};
