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
        p1: *?*const anyopaque,
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

    pub fn CreateInstance(self: *const IStackPanelFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **StackPanel) callconv(.winapi) HRESULT {
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
        p1: *?*const anyopaque,
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

    pub fn CreateInstance(self: *const ITextBoxFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **TextBox) callconv(.winapi) HRESULT {
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
