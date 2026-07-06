const foundation = @import("Windows.Foundation");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const BOOL = win_core.BOOL;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const PointerPoint_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    _reserved_before_position: [1]*const anyopaque,
    get_Position: *const fn (this: *const PointerPoint, result: *foundation.Point) callconv(.winapi) HRESULT,
    _reserved_before_properties: [5]*const anyopaque,
    get_Properties: *const fn (this: *const PointerPoint, result: **PointerPointProperties) callconv(.winapi) HRESULT,
};

pub const PointerPoint = extern struct {
    vtable: *const PointerPoint_Vtbl,

    pub fn QueryInterface(self: *const PointerPoint, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const PointerPoint) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const PointerPoint) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_Position(self: *const PointerPoint, result: *foundation.Point) callconv(.winapi) HRESULT {
        return self.vtable.get_Position(self, result);
    }

    pub fn get_Properties(self: *const PointerPoint, result: **PointerPointProperties) callconv(.winapi) HRESULT {
        return self.vtable.get_Properties(self, result);
    }
};

pub const PointerPointProperties_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    _reserved_before_buttons: [10]*const anyopaque,
    get_IsLeftButtonPressed: *const fn (this: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT,
    get_IsRightButtonPressed: *const fn (this: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT,
    get_IsMiddleButtonPressed: *const fn (this: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT,
};

pub const PointerPointProperties = extern struct {
    vtable: *const PointerPointProperties_Vtbl,

    pub fn QueryInterface(self: *const PointerPointProperties, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const PointerPointProperties) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const PointerPointProperties) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_IsLeftButtonPressed(self: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT {
        return self.vtable.get_IsLeftButtonPressed(self, result);
    }

    pub fn get_IsRightButtonPressed(self: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT {
        return self.vtable.get_IsRightButtonPressed(self, result);
    }

    pub fn get_IsMiddleButtonPressed(self: *const PointerPointProperties, result: *BOOL) callconv(.winapi) HRESULT {
        return self.vtable.get_IsMiddleButtonPressed(self, result);
    }
};
