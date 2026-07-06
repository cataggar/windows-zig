const std = @import("std");
const win_core = @import("win-core");
const foundation = @import("Windows.Foundation");
const xaml = @import("Microsoft.UI.Xaml");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const HSTRING = win_core.HSTRING;
pub const BOOL = win_core.BOOL;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const ClickMode = enum(i32) {
    Release = 0,
    Press = 1,
    Hover = 2,
    _,
};

pub const Orientation = enum(i32) {
    Vertical = 0,
    Horizontal = 1,
    _,
};

pub const BackgroundSizing = i32;

pub const TextChangedEventHandler = opaque {};

pub const IButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
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
};

pub const IButtonFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IButtonFactory,
        outer: ?*const anyopaque,
        inner: ?*?*const anyopaque,
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

    pub fn CreateInstance(self: *const IButtonFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **Button) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Button = extern struct {
    vtable: *const IButton_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Button";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const ITextBlock_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    put_Text: *const fn (this: *const ITextBlock, value: HSTRING) callconv(.winapi) HRESULT,
    put_TextWrapping: *const fn (this: *const ITextBlock, value: xaml.TextWrapping) callconv(.winapi) HRESULT,
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
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_Text(self, h.raw);
    }
};

pub const TextBlock = extern struct {
    vtable: *const ITextBlock_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.TextBlock";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*TextBlock {
        const raw = try win_core.activateInstance(ITextBlock, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const IContentControl_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Content: *const fn (this: *const IContentControl, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_Content: *const fn (this: *const IContentControl, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_ContentTemplate: *const fn (this: *const IContentControl, result: **xaml.DataTemplate) callconv(.winapi) HRESULT,
    put_ContentTemplate: *const fn (this: *const IContentControl, p0: *xaml.DataTemplate) callconv(.winapi) HRESULT,
    get_ContentTemplateSelector: *const fn (this: *const IContentControl, result: **anyopaque) callconv(.winapi) HRESULT,
    put_ContentTemplateSelector: *const fn (this: *const IContentControl, p0: *anyopaque) callconv(.winapi) HRESULT,
    get_ContentTransitions: *const fn (this: *const IContentControl, result: **anyopaque) callconv(.winapi) HRESULT,
    put_ContentTransitions: *const fn (this: *const IContentControl, p0: *anyopaque) callconv(.winapi) HRESULT,
    get_ContentTemplateRoot: *const fn (this: *const IContentControl, result: **xaml.UIElement) callconv(.winapi) HRESULT,
};

pub const IContentControl = extern struct {
    vtable: *const IContentControl_Vtbl,
    pub const Vtbl = IContentControl_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x07E81761,
        .data2 = 0x11B2,
        .data3 = 0x52AE,
        .data4 = .{ 0x8F, 0x8B, 0x4D, 0x53, 0xD2, 0xB5, 0x90, 0x0A },
    };

    pub fn QueryInterface(self: *const IContentControl, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IContentControl) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IContentControl) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IContentControl, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Content(self: *const IContentControl, value: ?*const anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_Content(self, value);
    }
};

pub const IStackPanel_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_AreScrollSnapPointsRegular: *const fn (this: *const IStackPanel, result: *BOOL) callconv(.winapi) HRESULT,
    put_AreScrollSnapPointsRegular: *const fn (this: *const IStackPanel, p0: BOOL) callconv(.winapi) HRESULT,
    get_Orientation: *const fn (this: *const IStackPanel, result: *Orientation) callconv(.winapi) HRESULT,
    put_Orientation: *const fn (this: *const IStackPanel, p0: Orientation) callconv(.winapi) HRESULT,
    get_BackgroundSizing: *const fn (this: *const IStackPanel, result: *BackgroundSizing) callconv(.winapi) HRESULT,
    put_BackgroundSizing: *const fn (this: *const IStackPanel, p0: BackgroundSizing) callconv(.winapi) HRESULT,
    get_BorderBrush: *const fn (this: *const IStackPanel, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_BorderBrush: *const fn (this: *const IStackPanel, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_BorderThickness: *const fn (this: *const IStackPanel, result: *xaml.Thickness) callconv(.winapi) HRESULT,
    put_BorderThickness: *const fn (this: *const IStackPanel, p0: xaml.Thickness) callconv(.winapi) HRESULT,
    get_CornerRadius: *const fn (this: *const IStackPanel, result: *xaml.CornerRadius) callconv(.winapi) HRESULT,
    put_CornerRadius: *const fn (this: *const IStackPanel, p0: xaml.CornerRadius) callconv(.winapi) HRESULT,
    get_Padding: *const fn (this: *const IStackPanel, result: *xaml.Thickness) callconv(.winapi) HRESULT,
    put_Padding: *const fn (this: *const IStackPanel, p0: xaml.Thickness) callconv(.winapi) HRESULT,
    get_Spacing: *const fn (this: *const IStackPanel, result: *f64) callconv(.winapi) HRESULT,
    put_Spacing: *const fn (this: *const IStackPanel, p0: f64) callconv(.winapi) HRESULT,
};

pub const IStackPanel = extern struct {
    vtable: *const IStackPanel_Vtbl,
    pub const Vtbl = IStackPanel_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x493AB00B,
        .data2 = 0x3A6A,
        .data3 = 0x5E4A,
        .data4 = .{ 0x94, 0x52, 0x40, 0x7C, 0xD5, 0x19, 0x74, 0x06 },
    };

    pub fn QueryInterface(self: *const IStackPanel, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IStackPanel) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IStackPanel) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IStackPanel, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Orientation(self: *const IStackPanel, value: Orientation) callconv(.winapi) HRESULT {
        return self.vtable.put_Orientation(self, value);
    }

    pub fn put_Spacing(self: *const IStackPanel, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.put_Spacing(self, value);
    }
};

pub const IStackPanelFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IStackPanelFactory,
        p0: ?*const anyopaque,
        p1: ?*?*const anyopaque,
        result: **StackPanel,
    ) callconv(.winapi) HRESULT,
};

pub const IStackPanelFactory = extern struct {
    vtable: *const IStackPanelFactory_Vtbl,
    pub const Vtbl = IStackPanelFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x64C1D388,
        .data2 = 0x47A2,
        .data3 = 0x5A74,
        .data4 = .{ 0xA7, 0x5B, 0x55, 0x9D, 0x15, 0x1E, 0xE5, 0xAC },
    };

    pub fn CreateInstance(self: *const IStackPanelFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **StackPanel) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const StackPanel = extern struct {
    vtable: *const IStackPanel_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.StackPanel";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const ITextBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Text: *const fn (this: *const ITextBox, result: *HSTRING) callconv(.winapi) HRESULT,
    put_Text: *const fn (this: *const ITextBox, p0: HSTRING) callconv(.winapi) HRESULT,
    get_SelectedText: *const fn (this: *const ITextBox, result: *HSTRING) callconv(.winapi) HRESULT,
    put_SelectedText: *const fn (this: *const ITextBox, p0: HSTRING) callconv(.winapi) HRESULT,
    get_SelectionLength: *const fn (this: *const ITextBox, result: *i32) callconv(.winapi) HRESULT,
    put_SelectionLength: *const fn (this: *const ITextBox, p0: i32) callconv(.winapi) HRESULT,
    get_SelectionStart: *const fn (this: *const ITextBox, result: *i32) callconv(.winapi) HRESULT,
    put_SelectionStart: *const fn (this: *const ITextBox, p0: i32) callconv(.winapi) HRESULT,
    get_MaxLength: *const fn (this: *const ITextBox, result: *i32) callconv(.winapi) HRESULT,
    put_MaxLength: *const fn (this: *const ITextBox, p0: i32) callconv(.winapi) HRESULT,
    get_IsReadOnly: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsReadOnly: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_AcceptsReturn: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_AcceptsReturn: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_TextAlignment: *const fn (this: *const ITextBox, result: *xaml.TextAlignment) callconv(.winapi) HRESULT,
    put_TextAlignment: *const fn (this: *const ITextBox, p0: xaml.TextAlignment) callconv(.winapi) HRESULT,
    get_TextWrapping: *const fn (this: *const ITextBox, result: *xaml.TextWrapping) callconv(.winapi) HRESULT,
    put_TextWrapping: *const fn (this: *const ITextBox, p0: xaml.TextWrapping) callconv(.winapi) HRESULT,
    get_IsSpellCheckEnabled: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsSpellCheckEnabled: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_IsTextPredictionEnabled: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsTextPredictionEnabled: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_InputScope: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_InputScope: *const fn (this: *const ITextBox, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_Header: *const fn (this: *const ITextBox, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_Header: *const fn (this: *const ITextBox, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_HeaderTemplate: *const fn (this: *const ITextBox, result: **xaml.DataTemplate) callconv(.winapi) HRESULT,
    put_HeaderTemplate: *const fn (this: *const ITextBox, p0: *xaml.DataTemplate) callconv(.winapi) HRESULT,
    get_PlaceholderText: *const fn (this: *const ITextBox, result: *HSTRING) callconv(.winapi) HRESULT,
    put_PlaceholderText: *const fn (this: *const ITextBox, p0: HSTRING) callconv(.winapi) HRESULT,
    get_SelectionHighlightColor: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_SelectionHighlightColor: *const fn (this: *const ITextBox, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_PreventKeyboardDisplayOnProgrammaticFocus: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_PreventKeyboardDisplayOnProgrammaticFocus: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_IsColorFontEnabled: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsColorFontEnabled: *const fn (this: *const ITextBox, p0: BOOL) callconv(.winapi) HRESULT,
    get_SelectionHighlightColorWhenNotFocused: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_SelectionHighlightColorWhenNotFocused: *const fn (this: *const ITextBox, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_HorizontalTextAlignment: *const fn (this: *const ITextBox, result: *xaml.TextAlignment) callconv(.winapi) HRESULT,
    put_HorizontalTextAlignment: *const fn (this: *const ITextBox, p0: xaml.TextAlignment) callconv(.winapi) HRESULT,
    get_CharacterCasing: *const fn (this: *const ITextBox, result: *i32) callconv(.winapi) HRESULT,
    put_CharacterCasing: *const fn (this: *const ITextBox, p0: i32) callconv(.winapi) HRESULT,
    get_PlaceholderForeground: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_PlaceholderForeground: *const fn (this: *const ITextBox, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_CanPasteClipboardContent: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    get_CanUndo: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    get_CanRedo: *const fn (this: *const ITextBox, result: *BOOL) callconv(.winapi) HRESULT,
    get_SelectionFlyout: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_SelectionFlyout: *const fn (this: *const ITextBox, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_ProofingMenuFlyout: *const fn (this: *const ITextBox, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Description: *const fn (this: *const ITextBox, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_Description: *const fn (this: *const ITextBox, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
    add_TextChanged: *const fn (this: *const ITextBox, p0: *TextChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_TextChanged: *const fn (this: *const ITextBox, p0: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const ITextBox = extern struct {
    vtable: *const ITextBox_Vtbl,
    pub const Vtbl = ITextBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x873AF7C2,
        .data2 = 0xAB89,
        .data3 = 0x5D76,
        .data4 = .{ 0x8D, 0xBE, 0x3D, 0x63, 0x25, 0x66, 0x9D, 0xF5 },
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

    pub fn cast(self: *const ITextBox, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_TextFromUtf16(self: *const ITextBox, value: []const u16) HRESULT {
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_Text(self, h.raw);
    }

    pub fn add_TextChanged(self: *const ITextBox, handler: *TextChangedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_TextChanged(self, handler, result);
    }

    pub fn remove_TextChanged(self: *const ITextBox, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_TextChanged(self, token);
    }
};

pub const ITextBoxFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const ITextBoxFactory,
        p0: ?*const anyopaque,
        p1: ?*?*const anyopaque,
        result: **TextBox,
    ) callconv(.winapi) HRESULT,
};

pub const ITextBoxFactory = extern struct {
    vtable: *const ITextBoxFactory_Vtbl,
    pub const Vtbl = ITextBoxFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xE1D8B82E,
        .data2 = 0xBC60,
        .data3 = 0x5D27,
        .data4 = .{ 0xB6, 0x46, 0x5C, 0xA4, 0xC4, 0xA6, 0x94, 0x32 },
    };

    pub fn CreateInstance(self: *const ITextBoxFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **TextBox) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const TextBox = extern struct {
    vtable: *const ITextBox_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.TextBox";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IPanel_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Children: *const fn (this: *const IPanel, result: **IUIElementCollection) callconv(.winapi) HRESULT,
    get_Background: *const fn (this: *const IPanel, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_Background: *const fn (this: *const IPanel, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_IsItemsHost: *const fn (this: *const IPanel, result: *BOOL) callconv(.winapi) HRESULT,
    get_ChildrenTransitions: *const fn (this: *const IPanel, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_ChildrenTransitions: *const fn (this: *const IPanel, p0: ?*anyopaque) callconv(.winapi) HRESULT,
    get_BackgroundTransition: *const fn (this: *const IPanel, result: **xaml.BrushTransition) callconv(.winapi) HRESULT,
    put_BackgroundTransition: *const fn (this: *const IPanel, p0: *xaml.BrushTransition) callconv(.winapi) HRESULT,
};

pub const IPanel = extern struct {
    vtable: *const IPanel_Vtbl,
    pub const Vtbl = IPanel_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x27A1B418,
        .data2 = 0x56F3,
        .data3 = 0x525E,
        .data4 = .{ 0xB8, 0x83, 0xCE, 0xFE, 0xD9, 0x05, 0xEE, 0xD3 },
    };

    pub fn QueryInterface(self: *const IPanel, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IPanel) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IPanel) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IPanel, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn get_Children(self: *const IPanel, result: **IUIElementCollection) callconv(.winapi) HRESULT {
        return self.vtable.get_Children(self, result);
    }
};

pub const IUIElementCollection_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetAt: *const fn (this: *const IUIElementCollection, p0: u32, result: **xaml.UIElement) callconv(.winapi) HRESULT,
    get_Size: *const fn (this: *const IUIElementCollection, result: *u32) callconv(.winapi) HRESULT,
    GetView: *const fn (this: *const IUIElementCollection, result: **anyopaque) callconv(.winapi) HRESULT,
    IndexOf: *const fn (this: *const IUIElementCollection, p0: *xaml.UIElement, p1: *u32, result: *BOOL) callconv(.winapi) HRESULT,
    SetAt: *const fn (this: *const IUIElementCollection, p0: u32, p1: *xaml.UIElement) callconv(.winapi) HRESULT,
    InsertAt: *const fn (this: *const IUIElementCollection, p0: u32, p1: *xaml.UIElement) callconv(.winapi) HRESULT,
    RemoveAt: *const fn (this: *const IUIElementCollection, p0: u32) callconv(.winapi) HRESULT,
    Append: *const fn (this: *const IUIElementCollection, p0: *xaml.UIElement) callconv(.winapi) HRESULT,
    RemoveAtEnd: *const fn (this: *const IUIElementCollection) callconv(.winapi) HRESULT,
    Clear: *const fn (this: *const IUIElementCollection) callconv(.winapi) HRESULT,
    GetMany: *const fn (this: *const IUIElementCollection, p0: u32, p1_size: u32, p1_ptr: [*]*xaml.UIElement, result: *u32) callconv(.winapi) HRESULT,
    ReplaceAll: *const fn (this: *const IUIElementCollection, p0_size: u32, p0_ptr: [*]const *xaml.UIElement) callconv(.winapi) HRESULT,
    Move: *const fn (this: *const IUIElementCollection, p0: u32, p1: u32) callconv(.winapi) HRESULT,
};

pub const IUIElementCollection = extern struct {
    vtable: *const IUIElementCollection_Vtbl,
    pub const Vtbl = IUIElementCollection_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x23050CB1,
        .data2 = 0xDB88,
        .data3 = 0x54ED,
        .data4 = .{ 0x90, 0x83, 0x5E, 0xCF, 0xB1, 0x25, 0x12, 0xFD },
    };

    pub fn QueryInterface(self: *const IUIElementCollection, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IUIElementCollection) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IUIElementCollection) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn InsertAt(self: *const IUIElementCollection, index: u32, value: *xaml.UIElement) callconv(.winapi) HRESULT {
        return self.vtable.InsertAt(self, index, value);
    }

    pub fn RemoveAt(self: *const IUIElementCollection, index: u32) callconv(.winapi) HRESULT {
        return self.vtable.RemoveAt(self, index);
    }

    pub fn Append(self: *const IUIElementCollection, value: *xaml.UIElement) callconv(.winapi) HRESULT {
        return self.vtable.Append(self, value);
    }

    pub fn Move(self: *const IUIElementCollection, from: u32, to: u32) callconv(.winapi) HRESULT {
        return self.vtable.Move(self, from, to);
    }
};

pub const IItemsControl_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_ItemsSource: *const fn (this: *const IItemsControl, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_ItemsSource: *const fn (this: *const IItemsControl, value: ?*const anyopaque) callconv(.winapi) HRESULT,
};

pub const IItemsControl = extern struct {
    vtable: *const IItemsControl_Vtbl,
    pub const Vtbl = IItemsControl_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xBF1CCB54,
        .data2 = 0x83E2,
        .data3 = 0x5B98,
        .data4 = .{ 0xAC, 0xBC, 0x73, 0x6F, 0x87, 0x6C, 0x3D, 0x35 },
    };

    pub fn QueryInterface(self: *const IItemsControl, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IItemsControl) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IItemsControl) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IItemsControl, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_ItemsSource(self: *const IItemsControl, value: ?*const anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_ItemsSource(self, value);
    }
};

pub const ICheckBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const ICheckBox = extern struct {
    vtable: *const ICheckBox_Vtbl,
    pub const Vtbl = ICheckBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC5830000,
        .data2 = 0x4C9D,
        .data3 = 0x5FDD,
        .data4 = .{ 0x93, 0x46, 0x67, 0x4C, 0x71, 0xCD, 0x80, 0xC5 },
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

pub const ICheckBoxFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const ICheckBoxFactory,
        outer: ?*const anyopaque,
        inner: ?*?*const anyopaque,
        result: **CheckBox,
    ) callconv(.winapi) HRESULT,
};

pub const ICheckBoxFactory = extern struct {
    vtable: *const ICheckBoxFactory_Vtbl,
    pub const Vtbl = ICheckBoxFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xF43FF58D,
        .data2 = 0x31D5,
        .data3 = 0x5835,
        .data4 = .{ 0xAF, 0x7B, 0x37, 0x5B, 0xC6, 0xA9, 0xBC, 0xF3 },
    };

    pub fn CreateInstance(self: *const ICheckBoxFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **CheckBox) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const CheckBox = extern struct {
    vtable: *const ICheckBox_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.CheckBox";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IComboBox_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IComboBox = extern struct {
    vtable: *const IComboBox_Vtbl,
    pub const Vtbl = IComboBox_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC77DA58B,
        .data2 = 0x4FD7,
        .data3 = 0x51E0,
        .data4 = .{ 0xA4, 0x31, 0xF8, 0x46, 0x58, 0xA8, 0x3E, 0x9E },
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

pub const IComboBoxFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IComboBoxFactory,
        outer: ?*const anyopaque,
        inner: ?*?*const anyopaque,
        result: **ComboBox,
    ) callconv(.winapi) HRESULT,
};

pub const IComboBoxFactory = extern struct {
    vtable: *const IComboBoxFactory_Vtbl,
    pub const Vtbl = IComboBoxFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x71C1014B,
        .data2 = 0xACDF,
        .data3 = 0x5C03,
        .data4 = .{ 0xB5, 0xED, 0x02, 0x87, 0x1C, 0xAA, 0xEB, 0x6B },
    };

    pub fn CreateInstance(self: *const IComboBoxFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **ComboBox) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const ComboBox = extern struct {
    vtable: *const IComboBox_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ComboBox";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const ISlider_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const ISlider = extern struct {
    vtable: *const ISlider_Vtbl,
    pub const Vtbl = ISlider_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xF7418ECF,
        .data2 = 0x7C35,
        .data3 = 0x5216,
        .data4 = .{ 0x8B, 0xF1, 0xD8, 0x2D, 0x47, 0xCC, 0xE5, 0xDF },
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

pub const ISliderFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const ISliderFactory,
        outer: ?*const anyopaque,
        inner: ?*?*const anyopaque,
        result: **Slider,
    ) callconv(.winapi) HRESULT,
};

pub const ISliderFactory = extern struct {
    vtable: *const ISliderFactory_Vtbl,
    pub const Vtbl = ISliderFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x06604D71,
        .data2 = 0x34CA,
        .data3 = 0x5F39,
        .data4 = .{ 0x96, 0x56, 0x29, 0xD8, 0x1D, 0x3C, 0x11, 0x0C },
    };

    pub fn CreateInstance(self: *const ISliderFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **Slider) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Slider = extern struct {
    vtable: *const ISlider_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Slider";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IRadioButton_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IRadioButton = extern struct {
    vtable: *const IRadioButton_Vtbl,
    pub const Vtbl = IRadioButton_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x38F30CEE,
        .data2 = 0xE75A,
        .data3 = 0x5BA1,
        .data4 = .{ 0xAE, 0x64, 0x44, 0x74, 0xA3, 0xAB, 0xEA, 0xC7 },
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

pub const IRadioButtonFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IRadioButtonFactory,
        outer: ?*const anyopaque,
        inner: ?*?*const anyopaque,
        result: **RadioButton,
    ) callconv(.winapi) HRESULT,
};

pub const IRadioButtonFactory = extern struct {
    vtable: *const IRadioButtonFactory_Vtbl,
    pub const Vtbl = IRadioButtonFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x5772C79A,
        .data2 = 0xB3EB,
        .data3 = 0x5719,
        .data4 = .{ 0x80, 0x05, 0x2A, 0x51, 0x34, 0x29, 0x49, 0x5A },
    };

    pub fn CreateInstance(self: *const IRadioButtonFactory, outer: ?*const anyopaque, inner: ?*?*const anyopaque, result: **RadioButton) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const RadioButton = extern struct {
    vtable: *const IRadioButton_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.RadioButton";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IToggleSwitch_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_IsOn: *const fn (this: *const IToggleSwitch, result: *BOOL) callconv(.winapi) HRESULT,
    put_IsOn: *const fn (this: *const IToggleSwitch, value: BOOL) callconv(.winapi) HRESULT,
    get_Header: *const fn (this: *const IToggleSwitch, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_Header: *const fn (this: *const IToggleSwitch, value: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_HeaderTemplate: *const fn (this: *const IToggleSwitch, result: **xaml.DataTemplate) callconv(.winapi) HRESULT,
    put_HeaderTemplate: *const fn (this: *const IToggleSwitch, value: *xaml.DataTemplate) callconv(.winapi) HRESULT,
    get_OnContent: *const fn (this: *const IToggleSwitch, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_OnContent: *const fn (this: *const IToggleSwitch, value: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_OnContentTemplate: *const fn (this: *const IToggleSwitch, result: **xaml.DataTemplate) callconv(.winapi) HRESULT,
    put_OnContentTemplate: *const fn (this: *const IToggleSwitch, value: *xaml.DataTemplate) callconv(.winapi) HRESULT,
    get_OffContent: *const fn (this: *const IToggleSwitch, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_OffContent: *const fn (this: *const IToggleSwitch, value: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_OffContentTemplate: *const fn (this: *const IToggleSwitch, result: **xaml.DataTemplate) callconv(.winapi) HRESULT,
    put_OffContentTemplate: *const fn (this: *const IToggleSwitch, value: *xaml.DataTemplate) callconv(.winapi) HRESULT,
    get_TemplateSettings: *const fn (this: *const IToggleSwitch, result: *?*anyopaque) callconv(.winapi) HRESULT,
    add_Toggled: *const fn (this: *const IToggleSwitch, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_Toggled: *const fn (this: *const IToggleSwitch, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT,
};

pub const IToggleSwitch = extern struct {
    vtable: *const IToggleSwitch_Vtbl,
    pub const Vtbl = IToggleSwitch_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x1B17EEB1,
        .data2 = 0x74BF,
        .data3 = 0x5A83,
        .data4 = .{ 0x81, 0x61, 0xA8, 0x6F, 0x0F, 0xDC, 0xDF, 0x24 },
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

    pub fn put_IsOn(self: *const IToggleSwitch, value: BOOL) callconv(.winapi) HRESULT {
        return self.vtable.put_IsOn(self, value);
    }

    pub fn add_Toggled(self: *const IToggleSwitch, handler: *xaml.RoutedEventHandler, result: *foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.add_Toggled(self, handler, result);
    }

    pub fn remove_Toggled(self: *const IToggleSwitch, token: foundation.EventRegistrationToken) callconv(.winapi) HRESULT {
        return self.vtable.remove_Toggled(self, token);
    }
};

pub const ToggleSwitch = extern struct {
    vtable: *const IToggleSwitch_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ToggleSwitch";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*ToggleSwitch {
        const raw = try win_core.activateInstance(IToggleSwitch, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const IXamlControlsResources_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_UseCompactResources: *const fn (this: *const IXamlControlsResources, result: *BOOL) callconv(.winapi) HRESULT,
    put_UseCompactResources: *const fn (this: *const IXamlControlsResources, value: BOOL) callconv(.winapi) HRESULT,
};

pub const IXamlControlsResources = extern struct {
    vtable: *const IXamlControlsResources_Vtbl,
    pub const Vtbl = IXamlControlsResources_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x918CA043,
        .data2 = 0xF42C,
        .data3 = 0x5805,
        .data4 = .{ 0x86, 0x1B, 0x62, 0xD6, 0xD1, 0xD0, 0xC1, 0x62 },
    };

    pub fn QueryInterface(self: *const IXamlControlsResources, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IXamlControlsResources) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IXamlControlsResources) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }
};

pub const XamlControlsResources = extern struct {
    vtable: *const IXamlControlsResources_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.XamlControlsResources";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*XamlControlsResources {
        const raw = try win_core.activateInstance(IXamlControlsResources, &NAME_W);
        return @ptrCast(raw);
    }
};
