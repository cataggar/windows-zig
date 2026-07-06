const foundation = @import("Windows.Foundation");
const controls = @import("Microsoft.UI.Xaml.Controls");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
pub const RoutedEventHandler = opaque {};
pub const RangeBaseValueChangedEventHandler = opaque {};

pub const IRangeBase = extern struct {
    vtable: *const IRangeBase_Vtbl,
    pub const Vtbl = IRangeBase_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x540d6d61,
        .data2 = 0x8fac,
        .data3 = 0x5d5c,
        .data4 = .{ 0xb5, 0xb0, 0xe1, 0x72, 0xa7, 0xdd, 0xe1, 0x03 },
    };

    pub fn QueryInterface(self: *const IRangeBase, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IRangeBase) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IRangeBase) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn add_ValueChanged(self: *const IRangeBase, p0: *RangeBaseValueChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_ValueChanged(self, p0, result);
    }

    pub fn remove_ValueChanged(self: *const IRangeBase, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_ValueChanged(self, p0);
    }
};

pub const ISelector = extern struct {
    vtable: *const ISelector_Vtbl,
    pub const Vtbl = ISelector_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x97472aec,
        .data2 = 0x39ab,
        .data3 = 0x5f28,
        .data4 = .{ 0xb9, 0x8f, 0x4b, 0x7f, 0xd0, 0xd7, 0x43, 0x85 },
    };

    pub fn QueryInterface(self: *const ISelector, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ISelector) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ISelector) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn add_SelectionChanged(self: *const ISelector, p0: *controls.SelectionChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_SelectionChanged(self, p0, result);
    }

    pub fn remove_SelectionChanged(self: *const ISelector, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_SelectionChanged(self, p0);
    }
};

pub const IToggleButton = extern struct {
    vtable: *const IToggleButton_Vtbl,
    pub const Vtbl = IToggleButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x686fbaa4,
        .data2 = 0xc866,
        .data3 = 0x568b,
        .data4 = .{ 0x8f, 0x75, 0x48, 0x1d, 0x8d, 0x54, 0x52, 0x91 },
    };

    pub fn QueryInterface(self: *const IToggleButton, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IToggleButton) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IToggleButton) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn add_Checked(self: *const IToggleButton, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Checked(self, p0, result);
    }

    pub fn remove_Checked(self: *const IToggleButton, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Checked(self, p0);
    }

    pub fn add_Unchecked(self: *const IToggleButton, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Unchecked(self, p0, result);
    }

    pub fn remove_Unchecked(self: *const IToggleButton, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Unchecked(self, p0);
    }
};

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

pub const IRangeBase_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    add_ValueChanged: *const fn (this: *const IRangeBase, p0: *RangeBaseValueChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_ValueChanged: *const fn (this: *const IRangeBase, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const ISelector_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_SelectedIndex: *const fn (this: *const ISelector, result: *i32) callconv(.winapi) HRESULT,
    put_SelectedIndex: *const fn (this: *const ISelector, p0: i32) callconv(.winapi) HRESULT,
    get_SelectedItem: *const fn (this: *const ISelector, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_SelectedItem: *const fn (this: *const ISelector, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_SelectedValue: *const fn (this: *const ISelector, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_SelectedValue: *const fn (this: *const ISelector, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_SelectedValuePath: *const fn (this: *const ISelector, result: *win_core.HSTRING) callconv(.winapi) HRESULT,
    put_SelectedValuePath: *const fn (this: *const ISelector, p0: win_core.HSTRING) callconv(.winapi) HRESULT,
    get_IsSynchronizedWithCurrentItem: *const fn (this: *const ISelector, result: **anyopaque) callconv(.winapi) HRESULT,
    put_IsSynchronizedWithCurrentItem: *const fn (this: *const ISelector, p0: *anyopaque) callconv(.winapi) HRESULT,
    add_SelectionChanged: *const fn (this: *const ISelector, p0: *controls.SelectionChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_SelectionChanged: *const fn (this: *const ISelector, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IToggleButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    add_Checked: *const fn (this: *const IToggleButton, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Checked: *const fn (this: *const IToggleButton, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    add_Unchecked: *const fn (this: *const IToggleButton, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Unchecked: *const fn (this: *const IToggleButton, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};
