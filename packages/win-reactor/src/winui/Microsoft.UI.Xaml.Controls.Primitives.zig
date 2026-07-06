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
        .data1 = 0x65714269,
        .data2 = 0x2473,
        .data3 = 0x5327,
        .data4 = .{ 0xA6, 0x52, 0x0E, 0xA6, 0xBC, 0xE7, 0xF4, 0x03 },
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

pub const RangeBaseValueChangedEventHandler = opaque {};

pub const IRangeBase_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Minimum: *const fn (this: *const IRangeBase, result: *f64) callconv(.winapi) HRESULT,
    put_Minimum: *const fn (this: *const IRangeBase, value: f64) callconv(.winapi) HRESULT,
    get_Maximum: *const fn (this: *const IRangeBase, result: *f64) callconv(.winapi) HRESULT,
    put_Maximum: *const fn (this: *const IRangeBase, value: f64) callconv(.winapi) HRESULT,
    get_SmallChange: *const fn (this: *const IRangeBase, result: *f64) callconv(.winapi) HRESULT,
    put_SmallChange: *const fn (this: *const IRangeBase, value: f64) callconv(.winapi) HRESULT,
    get_LargeChange: *const fn (this: *const IRangeBase, result: *f64) callconv(.winapi) HRESULT,
    put_LargeChange: *const fn (this: *const IRangeBase, value: f64) callconv(.winapi) HRESULT,
    get_Value: *const fn (this: *const IRangeBase, result: *f64) callconv(.winapi) HRESULT,
    put_Value: *const fn (this: *const IRangeBase, value: f64) callconv(.winapi) HRESULT,
    add_ValueChanged: *const fn (this: *const IRangeBase, handler: *RangeBaseValueChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_ValueChanged: *const fn (this: *const IRangeBase, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IRangeBase = extern struct {
    vtable: *const IRangeBase_Vtbl,
    pub const Vtbl = IRangeBase_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x540D6D61,
        .data2 = 0x8FAC,
        .data3 = 0x5D5C,
        .data4 = .{ 0xB5, 0xB0, 0xE1, 0x72, 0xA7, 0xDD, 0xE1, 0x03 },
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

    pub fn cast(self: *const IRangeBase, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Minimum(self: *const IRangeBase, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.put_Minimum(self, value);
    }

    pub fn put_Maximum(self: *const IRangeBase, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.put_Maximum(self, value);
    }

    pub fn put_Value(self: *const IRangeBase, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.put_Value(self, value);
    }

    pub fn add_ValueChanged(self: *const IRangeBase, handler: *RangeBaseValueChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_ValueChanged(self, handler, result);
    }

    pub fn remove_ValueChanged(self: *const IRangeBase, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_ValueChanged(self, token);
    }
};

pub const IRangeBaseValueChangedEventArgs_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_OldValue: *const fn (this: *const IRangeBaseValueChangedEventArgs, result: *f64) callconv(.winapi) HRESULT,
    get_NewValue: *const fn (this: *const IRangeBaseValueChangedEventArgs, result: *f64) callconv(.winapi) HRESULT,
};

pub const IRangeBaseValueChangedEventArgs = extern struct {
    vtable: *const IRangeBaseValueChangedEventArgs_Vtbl,
    pub const Vtbl = IRangeBaseValueChangedEventArgs_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xB0181692,
        .data2 = 0x9578,
        .data3 = 0x51C7,
        .data4 = .{ 0x9D, 0x1C, 0xAD, 0xFC, 0xF8, 0x94, 0x5A, 0xA9 },
    };

    pub fn QueryInterface(self: *const IRangeBaseValueChangedEventArgs, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IRangeBaseValueChangedEventArgs) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IRangeBaseValueChangedEventArgs) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_NewValue(self: *const IRangeBaseValueChangedEventArgs, result: *f64) callconv(.winapi) HRESULT {
        return self.vtable.get_NewValue(self, result);
    }
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

pub const ISelector = extern struct {
    vtable: *const ISelector_Vtbl,
    pub const Vtbl = ISelector_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x8F7E2159,
        .data2 = 0xE61D,
        .data3 = 0x576F,
        .data4 = .{ 0x84, 0x76, 0xF8, 0x3F, 0xDE, 0x3D, 0x68, 0x9E },
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

    pub fn get_SelectedIndex(self: *const ISelector, result: *i32) callconv(.winapi) HRESULT {
        return self.vtable.get_SelectedIndex(self, result);
    }

    pub fn put_SelectedIndex(self: *const ISelector, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.put_SelectedIndex(self, value);
    }

    pub fn add_SelectionChanged(self: *const ISelector, handler: *controls.SelectionChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_SelectionChanged(self, handler, result);
    }

    pub fn remove_SelectionChanged(self: *const ISelector, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_SelectionChanged(self, token);
    }
};

pub const IToggleButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_IsChecked: *const fn (this: *const IToggleButton, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_IsChecked: *const fn (this: *const IToggleButton, value: *const anyopaque) callconv(.winapi) HRESULT,
    get_IsThreeState: *const fn (this: *const IToggleButton, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsThreeState: *const fn (this: *const IToggleButton, value: BOOL) callconv(.winapi) HRESULT,
    add_Checked: *const fn (this: *const IToggleButton, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Checked: *const fn (this: *const IToggleButton, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    add_Unchecked: *const fn (this: *const IToggleButton, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Unchecked: *const fn (this: *const IToggleButton, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    add_Indeterminate: *const fn (this: *const IToggleButton, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Indeterminate: *const fn (this: *const IToggleButton, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IToggleButton = extern struct {
    vtable: *const IToggleButton_Vtbl,
    pub const Vtbl = IToggleButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x686FBAA4,
        .data2 = 0xC866,
        .data3 = 0x568B,
        .data4 = .{ 0x8F, 0x75, 0x48, 0x1D, 0x8D, 0x54, 0x52, 0x91 },
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

    pub fn cast(self: *const IToggleButton, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_IsChecked(self: *const IToggleButton, value: *const anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_IsChecked(self, value);
    }

    pub fn add_Checked(self: *const IToggleButton, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Checked(self, handler, result);
    }

    pub fn remove_Checked(self: *const IToggleButton, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Checked(self, token);
    }

    pub fn add_Unchecked(self: *const IToggleButton, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Unchecked(self, handler, result);
    }

    pub fn remove_Unchecked(self: *const IToggleButton, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Unchecked(self, token);
    }
};

pub const IFlyoutBase_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Placement: *const anyopaque,
    put_Placement: *const anyopaque,
    get_Target: *const anyopaque,
    get_AllowFocusOnInteraction: *const anyopaque,
    put_AllowFocusOnInteraction: *const anyopaque,
    get_LightDismissOverlayMode: *const anyopaque,
    put_LightDismissOverlayMode: *const anyopaque,
    get_AllowFocusWhenDisabled: *const anyopaque,
    put_AllowFocusWhenDisabled: *const anyopaque,
    get_ShowMode: *const anyopaque,
    put_ShowMode: *const anyopaque,
    get_InputDevicePrefersPrimaryCommands: *const anyopaque,
    get_AreOpenCloseAnimationsEnabled: *const anyopaque,
    put_AreOpenCloseAnimationsEnabled: *const anyopaque,
    get_ShouldConstrainToRootBounds: *const anyopaque,
    put_ShouldConstrainToRootBounds: *const anyopaque,
    get_IsConstrainedToRootBounds: *const anyopaque,
    get_ElementSoundMode: *const anyopaque,
    put_ElementSoundMode: *const anyopaque,
    get_OverlayInputPassThroughElement: *const anyopaque,
    put_OverlayInputPassThroughElement: *const anyopaque,
    get_IsOpen: *const anyopaque,
    get_XamlRoot: *const anyopaque,
    put_XamlRoot: *const anyopaque,
    add_Opened: *const anyopaque,
    remove_Opened: *const anyopaque,
    add_Closed: *const anyopaque,
    remove_Closed: *const anyopaque,
    add_Opening: *const anyopaque,
    remove_Opening: *const anyopaque,
    add_Closing: *const anyopaque,
    remove_Closing: *const anyopaque,
    ShowAt: *const fn (this: *const IFlyoutBase, target: *xaml.FrameworkElement) callconv(.winapi) HRESULT,
    ShowAt_2: *const anyopaque,
    Hide: *const fn (this: *const IFlyoutBase) callconv(.winapi) HRESULT,
};

pub const IFlyoutBase = extern struct {
    vtable: *const IFlyoutBase_Vtbl,
    pub const Vtbl = IFlyoutBase_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xBB6603BF,
        .data2 = 0x744D,
        .data3 = 0x5C31,
        .data4 = .{ 0xA8, 0x7D, 0x74, 0x43, 0x94, 0x63, 0x4D, 0x77 },
    };

    pub fn QueryInterface(self: *const IFlyoutBase, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IFlyoutBase) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IFlyoutBase) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IFlyoutBase, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn ShowAt(self: *const IFlyoutBase, target: *xaml.FrameworkElement) callconv(.winapi) HRESULT {
        return self.vtable.ShowAt(self, target);
    }

    pub fn Hide(self: *const IFlyoutBase) callconv(.winapi) HRESULT {
        return self.vtable.Hide(self);
    }
};
