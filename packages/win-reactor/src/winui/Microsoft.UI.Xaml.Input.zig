const ui_input = @import("Microsoft.UI.Input");
const windows_system = @import("Windows.System");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const BOOL = win_core.BOOL;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const PointerEventHandler = opaque {};

pub const Pointer_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const Pointer = extern struct {
    vtable: *const Pointer_Vtbl,

    pub fn QueryInterface(self: *const Pointer, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const Pointer) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const Pointer) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }
};

pub const PointerRoutedEventArgs_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Pointer: *const fn (this: *const PointerRoutedEventArgs, result: **Pointer) callconv(.winapi) HRESULT,
    get_KeyModifiers: *const fn (this: *const PointerRoutedEventArgs, result: *windows_system.VirtualKeyModifiers) callconv(.winapi) HRESULT,
    get_Handled: *const fn (this: *const PointerRoutedEventArgs, result: *BOOL) callconv(.winapi) HRESULT,
    put_Handled: *const fn (this: *const PointerRoutedEventArgs, value: BOOL) callconv(.winapi) HRESULT,
    get_IsGenerated: *const fn (this: *const PointerRoutedEventArgs, result: *BOOL) callconv(.winapi) HRESULT,
    GetCurrentPoint: *const fn (this: *const PointerRoutedEventArgs, relative_to: ?*anyopaque, result: **ui_input.PointerPoint) callconv(.winapi) HRESULT,
    GetIntermediatePoints: *const fn (this: *const PointerRoutedEventArgs, relative_to: ?*anyopaque, result: **anyopaque) callconv(.winapi) HRESULT,
};

pub const PointerRoutedEventArgs = extern struct {
    vtable: *const PointerRoutedEventArgs_Vtbl,

    pub fn QueryInterface(self: *const PointerRoutedEventArgs, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const PointerRoutedEventArgs) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const PointerRoutedEventArgs) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_Pointer(self: *const PointerRoutedEventArgs, result: **Pointer) callconv(.winapi) HRESULT {
        return self.vtable.get_Pointer(self, result);
    }

    pub fn GetCurrentPoint(self: *const PointerRoutedEventArgs, relative_to: ?*anyopaque, result: **ui_input.PointerPoint) callconv(.winapi) HRESULT {
        return self.vtable.GetCurrentPoint(self, relative_to, result);
    }
};
