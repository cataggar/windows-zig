const foundation = @import("Windows.Foundation");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
pub const RoutedEventHandler = opaque {};

pub const IButtonBase = extern struct {
    vtable: *const IButtonBase_Vtbl,
    pub const Vtbl = IButtonBase_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x3f7d7a33,
        .data2 = 0x79f4,
        .data3 = 0x5e58,
        .data4 = .{ 0x8f, 0x3f, 0x4e, 0x6a, 0x10, 0x3d, 0xd2, 0xe2 },
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

    pub fn add_Click(self: *const IButtonBase, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Click(self, p0, result);
    }

    pub fn remove_Click(self: *const IButtonBase, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Click(self, p0);
    }
};

pub const IButtonBase_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    add_Click: *const fn (this: *const IButtonBase, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Click: *const fn (this: *const IButtonBase, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};
