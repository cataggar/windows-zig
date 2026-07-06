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

    pub fn add_SelectionChanged(self: *const ISelector, handler: *controls.SelectionChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_SelectionChanged(self, handler, result);
    }

    pub fn remove_SelectionChanged(self: *const ISelector, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_SelectionChanged(self, token);
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
