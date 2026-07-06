const foundation = @import("Windows.Foundation");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
pub const SelectionChangedEventHandler = opaque {};
pub const TextChangedEventHandler = opaque {};

pub const Button = extern struct {
    vtable: *const IButton_Vtbl,
};

pub const TextBox = extern struct {
    vtable: *const ITextBox_Vtbl,
};

pub const ListView = extern struct {
    vtable: *const IListView_Vtbl,
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

pub const IListView = extern struct {
    vtable: *const IListView_Vtbl,
    pub const Vtbl = IListView_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xf6015db1,
        .data2 = 0xdf63,
        .data3 = 0x52fd,
        .data4 = .{ 0xa1, 0x64, 0x0d, 0xf4, 0x47, 0x15, 0xee, 0x0a },
    };

    pub fn QueryInterface(self: *const IListView, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IListView) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IListView) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IListView, comptime T: type) ?*const T {
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

pub const IListView_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};
