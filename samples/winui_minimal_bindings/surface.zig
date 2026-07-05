//! Minimal slice of the emitted WinUI bindings needed by issue #3's
//! compile canary.
//!
//! Every signature here is copied from the checked-in namespace snapshots:
//!   * `packages/win/src/generated/Microsoft.UI.Xaml.zig`
//!   * `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
//!
//! The full namespace files currently do not import cleanly because of
//! unrelated emitter gaps elsewhere in those large namespaces. Keeping this
//! slice local to the sample lets us confirm the four target types are
//! emitted with usable, non-opaque signatures without hand-editing the
//! generated snapshots themselves.

const core = @import("win").core;

pub const HRESULT = core.HRESULT;
pub const HSTRING = core.HSTRING;
pub const GUID = core.GUID;
pub const BOOL = core.BOOL;
pub const IInspectable_Vtbl = core.IInspectable_Vtbl;

pub const ApplicationTheme = enum(i32) {
    Light = 0,
    Dark = 1,
    _,
};

pub const TextWrapping = enum(i32) {
    NoWrap = 1,
    Wrap = 2,
    WrapWholeWords = 3,
    _,
};

pub const ResourceDictionary = extern struct {
    vtable: *const anyopaque,
};

pub const FlyoutBase = extern struct {
    vtable: *const anyopaque,
};

pub const IUIElement_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IUIElement = extern struct {
    vtable: *const IUIElement_Vtbl,
    pub const Vtbl = IUIElement_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC3C01020,
        .data2 = 0x320C,
        .data3 = 0x5CF6,
        .data4 = .{ 0x9D, 0x24, 0xD3, 0x96, 0xBB, 0xFA, 0x4D, 0x8B },
    };

    pub fn QueryInterface(self: *const IUIElement, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IUIElement) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IUIElement) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IUIElement, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const UIElement = extern struct {
    vtable: *const IUIElement_Vtbl,
};

pub const IApplication_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Resources: *const fn (this: *const IApplication, result: **ResourceDictionary) callconv(.winapi) HRESULT,
    put_Resources: *const fn (this: *const IApplication, value: *ResourceDictionary) callconv(.winapi) HRESULT,
    get_DebugSettings: *const fn (this: *const IApplication, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_RequestedTheme: *const fn (this: *const IApplication, result: *ApplicationTheme) callconv(.winapi) HRESULT,
    put_RequestedTheme: *const fn (this: *const IApplication, value: ApplicationTheme) callconv(.winapi) HRESULT,
};

pub const IApplication = extern struct {
    vtable: *const IApplication_Vtbl,
    pub const Vtbl = IApplication_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x06A8F4E7,
        .data2 = 0x1146,
        .data3 = 0x55AF,
        .data4 = .{ 0x82, 0x0D, 0xEB, 0xD5, 0x56, 0x43, 0xB0, 0x21 },
    };

    pub fn QueryInterface(self: *const IApplication, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IApplication) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IApplication) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IApplication, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn get_Resources(self: *const IApplication, result: **ResourceDictionary) callconv(.winapi) HRESULT {
        return self.vtable.get_Resources(self, result);
    }

    pub fn put_RequestedTheme(self: *const IApplication, value: ApplicationTheme) callconv(.winapi) HRESULT {
        return self.vtable.put_RequestedTheme(self, value);
    }
};

pub const IApplicationFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IApplicationFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Application,
    ) callconv(.winapi) HRESULT,
};

pub const IApplicationFactory = extern struct {
    vtable: *const IApplicationFactory_Vtbl,
    pub const Vtbl = IApplicationFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x9FD96657,
        .data2 = 0x5294,
        .data3 = 0x5A65,
        .data4 = .{ 0xA1, 0xDB, 0x4F, 0xEA, 0x14, 0x35, 0x97, 0xDA },
    };

    pub fn CreateInstance(self: *const IApplicationFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Application) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Application = extern struct {
    vtable: *const IApplication_Vtbl,
    pub const NAME_W: [29]u16 = .{ 77, 105, 99, 114, 111, 115, 111, 102, 116, 46, 85, 73, 46, 88, 97, 109, 108, 46, 65, 112, 112, 108, 105, 99, 97, 116, 105, 111, 110 };
};

pub const IWindow_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Bounds: *const fn (this: *const IWindow, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Visible: *const fn (this: *const IWindow, result: *BOOL) callconv(.winapi) HRESULT,
    get_Content: *const fn (this: *const IWindow, result: **UIElement) callconv(.winapi) HRESULT,
    put_Content: *const fn (this: *const IWindow, value: *UIElement) callconv(.winapi) HRESULT,
    get_CoreWindow: *const fn (this: *const IWindow, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Compositor: *const fn (this: *const IWindow, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Dispatcher: *const fn (this: *const IWindow, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_DispatcherQueue: *const fn (this: *const IWindow, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Title: *const fn (this: *const IWindow, result: *HSTRING) callconv(.winapi) HRESULT,
    put_Title: *const fn (this: *const IWindow, value: HSTRING) callconv(.winapi) HRESULT,
    get_ExtendsContentIntoTitleBar: *const fn (this: *const IWindow, result: *BOOL) callconv(.winapi) HRESULT,
    put_ExtendsContentIntoTitleBar: *const fn (this: *const IWindow, value: BOOL) callconv(.winapi) HRESULT,
    add_Activated: *const fn (this: *const IWindow, handler: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    remove_Activated: *const fn (this: *const IWindow, token: ?*const anyopaque) callconv(.winapi) HRESULT,
    add_Closed: *const fn (this: *const IWindow, handler: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    remove_Closed: *const fn (this: *const IWindow, token: ?*const anyopaque) callconv(.winapi) HRESULT,
    add_SizeChanged: *const fn (this: *const IWindow, handler: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    remove_SizeChanged: *const fn (this: *const IWindow, token: ?*const anyopaque) callconv(.winapi) HRESULT,
    add_VisibilityChanged: *const fn (this: *const IWindow, handler: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    remove_VisibilityChanged: *const fn (this: *const IWindow, token: ?*const anyopaque) callconv(.winapi) HRESULT,
    Activate: *const fn (this: *const IWindow) callconv(.winapi) HRESULT,
    Close: *const fn (this: *const IWindow) callconv(.winapi) HRESULT,
    SetTitleBar: *const fn (this: *const IWindow, value: *UIElement) callconv(.winapi) HRESULT,
};

pub const IWindow = extern struct {
    vtable: *const IWindow_Vtbl,
    pub const Vtbl = IWindow_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x61F0EC79,
        .data2 = 0x5D52,
        .data3 = 0x56B5,
        .data4 = .{ 0x86, 0xFB, 0x40, 0xFA, 0x4A, 0xF2, 0x88, 0xB0 },
    };

    pub fn QueryInterface(self: *const IWindow, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IWindow) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IWindow) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IWindow, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Title(self: *const IWindow, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_Title(self, value);
    }

    pub fn put_TitleFromUtf16(self: *const IWindow, value: []const u16) HRESULT {
        var h = core.Hstring.create(value) catch return core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_Title(self, h.raw);
    }

    pub fn put_Content(self: *const IWindow, value: *UIElement) callconv(.winapi) HRESULT {
        return self.vtable.put_Content(self, value);
    }

    pub fn SetTitleBar(self: *const IWindow, value: *UIElement) callconv(.winapi) HRESULT {
        return self.vtable.SetTitleBar(self, value);
    }
};

pub const IWindowFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IWindowFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Window,
    ) callconv(.winapi) HRESULT,
};

pub const IWindowFactory = extern struct {
    vtable: *const IWindowFactory_Vtbl,
    pub const Vtbl = IWindowFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xF0441536,
        .data2 = 0xAFEF,
        .data3 = 0x5222,
        .data4 = .{ 0x91, 0x8F, 0x32, 0x4A, 0x9B, 0x2D, 0xEC, 0x75 },
    };

    pub fn CreateInstance(self: *const IWindowFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Window) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Window = extern struct {
    vtable: *const IWindow_Vtbl,
    pub const NAME_W: [24]u16 = .{ 77, 105, 99, 114, 111, 115, 111, 102, 116, 46, 85, 73, 46, 88, 97, 109, 108, 46, 87, 105, 110, 100, 111, 119 };
};

pub const IButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Flyout: *const fn (this: *const IButton, result: **FlyoutBase) callconv(.winapi) HRESULT,
    put_Flyout: *const fn (this: *const IButton, value: *FlyoutBase) callconv(.winapi) HRESULT,
};

pub const IButton = extern struct {
    vtable: *const IButton_Vtbl,
    pub const Vtbl = IButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x216C183D,
        .data2 = 0xD07A,
        .data3 = 0x5AA5,
        .data4 = .{ 0xB8, 0xA4, 0x03, 0x00, 0xA2, 0x68, 0x3E, 0x87 },
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

    pub fn get_Flyout(self: *const IButton, result: **FlyoutBase) callconv(.winapi) HRESULT {
        return self.vtable.get_Flyout(self, result);
    }
};

pub const IButtonFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IButtonFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Button,
    ) callconv(.winapi) HRESULT,
};

pub const IButtonFactory = extern struct {
    vtable: *const IButtonFactory_Vtbl,
    pub const Vtbl = IButtonFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xFE393422,
        .data2 = 0xD91C,
        .data3 = 0x57B1,
        .data4 = .{ 0x9A, 0x9C, 0x2C, 0x7E, 0x3F, 0x41, 0xF7, 0x7C },
    };

    pub fn CreateInstance(self: *const IButtonFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Button) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Button = extern struct {
    vtable: *const IButton_Vtbl,
    pub const NAME_W: [33]u16 = .{ 77, 105, 99, 114, 111, 115, 111, 102, 116, 46, 85, 73, 46, 88, 97, 109, 108, 46, 67, 111, 110, 116, 114, 111, 108, 115, 46, 66, 117, 116, 116, 111, 110 };
};

pub const ITextBlock_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    put_Text: *const fn (this: *const ITextBlock, value: HSTRING) callconv(.winapi) HRESULT,
    put_TextWrapping: *const fn (this: *const ITextBlock, value: TextWrapping) callconv(.winapi) HRESULT,
};

pub const ITextBlock = extern struct {
    vtable: *const ITextBlock_Vtbl,
    pub const Vtbl = ITextBlock_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x1AC8D84F,
        .data2 = 0x392C,
        .data3 = 0x5C7E,
        .data4 = .{ 0x83, 0xF5, 0xA5, 0x3E, 0x3B, 0xF0, 0xAB, 0xB0 },
    };

    pub fn QueryInterface(self: *const ITextBlock, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ITextBlock) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ITextBlock) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const ITextBlock, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Text(self: *const ITextBlock, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_Text(self, value);
    }

    pub fn put_TextFromUtf16(self: *const ITextBlock, value: []const u16) HRESULT {
        var h = core.Hstring.create(value) catch return core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_Text(self, h.raw);
    }

    pub fn put_TextWrapping(self: *const ITextBlock, value: TextWrapping) callconv(.winapi) HRESULT {
        return self.vtable.put_TextWrapping(self, value);
    }
};

pub const TextBlock = extern struct {
    vtable: *const ITextBlock_Vtbl,
    pub const NAME_W: [36]u16 = .{ 77, 105, 99, 114, 111, 115, 111, 102, 116, 46, 85, 73, 46, 88, 97, 109, 108, 46, 67, 111, 110, 116, 114, 111, 108, 115, 46, 84, 101, 120, 116, 66, 108, 111, 99, 107 };
};
