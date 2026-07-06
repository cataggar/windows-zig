const foundation = @import("Windows.Foundation");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
pub const TextChangedEventHandler = opaque {};
pub const RoutedEventHandler = opaque {};

pub const Button = extern struct {
    vtable: *const IButton_Vtbl,
};

pub const TextBox = extern struct {
    vtable: *const ITextBox_Vtbl,
};

pub const CheckBox = extern struct {
    vtable: *const ICheckBox_Vtbl,
};

pub const ComboBox = extern struct {
    vtable: *const IComboBox_Vtbl,
};

pub const Slider = extern struct {
    vtable: *const ISlider_Vtbl,
};

pub const ToggleSwitch = extern struct {
    vtable: *const IToggleSwitch_Vtbl,
};

pub const RadioButton = extern struct {
    vtable: *const IRadioButton_Vtbl,
};

pub const IButton = extern struct {
    vtable: *const IButton_Vtbl,
    pub const Vtbl = IButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x216c183d,
        .data2 = 0xd07a,
        .data3 = 0x5aa5,
        .data4 = .{ 0xb8, 0xa4, 0x03, 0x00, 0xa2, 0x68, 0x3e, 0x87 },
    };

    pub fn QueryInterface(self: *const IButton, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IButton) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IButton) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IButton, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const ITextBox = extern struct {
    vtable: *const ITextBox_Vtbl,
    pub const Vtbl = ITextBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xf6e707ca,
        .data2 = 0xe6a0,
        .data3 = 0x5d8b,
        .data4 = .{ 0xa0, 0x35, 0x34, 0x8f, 0xb7, 0x41, 0x34, 0xc0 },
    };

    pub fn QueryInterface(self: *const ITextBox, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ITextBox) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ITextBox) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn add_TextChanged(self: *const ITextBox, p0: *TextChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_TextChanged(self, p0, result);
    }

    pub fn remove_TextChanged(self: *const ITextBox, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_TextChanged(self, p0);
    }
};

pub const ICheckBox = extern struct {
    vtable: *const ICheckBox_Vtbl,
    pub const Vtbl = ICheckBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xc5830000,
        .data2 = 0x4c9d,
        .data3 = 0x5fdd,
        .data4 = .{ 0x93, 0x46, 0x67, 0x4c, 0x71, 0xcd, 0x80, 0xc5 },
    };

    pub fn QueryInterface(self: *const ICheckBox, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ICheckBox) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ICheckBox) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const ICheckBox, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const IComboBox = extern struct {
    vtable: *const IComboBox_Vtbl,
    pub const Vtbl = IComboBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xc77da58b,
        .data2 = 0x4fd7,
        .data3 = 0x51e0,
        .data4 = .{ 0xa4, 0x31, 0xf8, 0x46, 0x58, 0xa8, 0x3e, 0x9e },
    };

    pub fn QueryInterface(self: *const IComboBox, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IComboBox) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IComboBox) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IComboBox, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const ISlider = extern struct {
    vtable: *const ISlider_Vtbl,
    pub const Vtbl = ISlider_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xf7418ecf,
        .data2 = 0x7c35,
        .data3 = 0x5216,
        .data4 = .{ 0x8b, 0xf1, 0xd8, 0x2d, 0x47, 0xcc, 0xe5, 0xdf },
    };

    pub fn QueryInterface(self: *const ISlider, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ISlider) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ISlider) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const ISlider, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const IToggleSwitch = extern struct {
    vtable: *const IToggleSwitch_Vtbl,
    pub const Vtbl = IToggleSwitch_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x1b17eeb1,
        .data2 = 0x74bf,
        .data3 = 0x5a83,
        .data4 = .{ 0x81, 0x61, 0xa8, 0x6f, 0x0f, 0xdc, 0xdf, 0x24 },
    };

    pub fn QueryInterface(self: *const IToggleSwitch, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IToggleSwitch) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IToggleSwitch) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn add_Toggled(self: *const IToggleSwitch, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Toggled(self, p0, result);
    }

    pub fn remove_Toggled(self: *const IToggleSwitch, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Toggled(self, p0);
    }
};

pub const IRadioButton = extern struct {
    vtable: *const IRadioButton_Vtbl,
    pub const Vtbl = IRadioButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x38f30cee,
        .data2 = 0xe75a,
        .data3 = 0x5ba1,
        .data4 = .{ 0xae, 0x64, 0x44, 0x74, 0xa3, 0xab, 0xea, 0xc7 },
    };

    pub fn QueryInterface(self: *const IRadioButton, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IRadioButton) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IRadioButton) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IRadioButton, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const IButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const ITextBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    add_TextChanged: *const fn (this: *const ITextBox, p0: *TextChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_TextChanged: *const fn (this: *const ITextBox, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const ICheckBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IComboBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const ISlider_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IToggleSwitch_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    add_Toggled: *const fn (this: *const IToggleSwitch, p0: *RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Toggled: *const fn (this: *const IToggleSwitch, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IRadioButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};
