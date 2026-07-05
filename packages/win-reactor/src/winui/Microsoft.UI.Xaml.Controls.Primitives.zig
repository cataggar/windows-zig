const foundation = @import("Windows.Foundation");
const win_core = @import("win-core");
const xaml = @import("Microsoft.UI.Xaml");
const controls = @import("Microsoft.UI.Xaml.Controls");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const BOOL = win_core.BOOL;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const IButtonBase_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_ClickMode: *const fn (this: *const IButtonBase, result: *controls.ClickMode) callconv(.winapi) HRESULT,
    put_ClickMode: *const fn (this: *const IButtonBase, p0: controls.ClickMode) callconv(.winapi) HRESULT,
    get_IsPointerOver: *const fn (this: *const IButtonBase, result: *BOOL) callconv(.winapi) HRESULT,
    get_IsPressed: *const fn (this: *const IButtonBase, result: *BOOL) callconv(.winapi) HRESULT,
    get_Command: *const fn (this: *const IButtonBase, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_Command: *const fn (this: *const IButtonBase, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_CommandParameter: *const fn (this: *const IButtonBase, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_CommandParameter: *const fn (this: *const IButtonBase, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    add_Click: *const fn (this: *const IButtonBase, p0: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Click: *const fn (this: *const IButtonBase, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IButtonBase = extern struct {
    vtable: *const IButtonBase_Vtbl,
    pub const Vtbl = IButtonBase_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x3F7D7A33,
        .data2 = 0x79F4,
        .data3 = 0x5E58,
        .data4 = .{ 0x8F, 0x3F, 0x4E, 0x6A, 0x10, 0x3D, 0xD2, 0xE2 },
    };

    pub fn QueryInterface(self: *const IButtonBase, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IButtonBase) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IButtonBase) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IButtonBase, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn add_Click(self: *const IButtonBase, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Click(self, handler, result);
    }

    pub fn remove_Click(self: *const IButtonBase, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Click(self, token);
    }
};
