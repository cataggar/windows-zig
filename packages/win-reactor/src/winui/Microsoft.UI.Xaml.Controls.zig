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

pub const ICanvas_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const ICanvas = extern struct {
    vtable: *const ICanvas_Vtbl,
    pub const Vtbl = ICanvas_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x457BA139,
        .data2 = 0x1146,
        .data3 = 0x51D2,
        .data4 = .{ 0x80, 0x7E, 0xD9, 0xD6, 0x5C, 0x92, 0x70, 0x60 },
    };

    pub fn QueryInterface(self: *const ICanvas, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ICanvas) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ICanvas) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const ICanvas, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const ICanvasFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const ICanvasFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Canvas,
    ) callconv(.winapi) HRESULT,
};

pub const ICanvasFactory = extern struct {
    vtable: *const ICanvasFactory_Vtbl,
    pub const Vtbl = ICanvasFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x374C5050,
        .data2 = 0x3481,
        .data3 = 0x5557,
        .data4 = .{ 0x99, 0x48, 0x80, 0x4C, 0x0B, 0x8E, 0xEA, 0x89 },
    };

    pub fn CreateInstance(self: *const ICanvasFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Canvas) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const ICanvasStatics_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_LeftProperty: *const fn (this: *const ICanvasStatics, result: **xaml.DependencyProperty) callconv(.winapi) HRESULT,
    GetLeft: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, result: *f64) callconv(.winapi) HRESULT,
    SetLeft: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, value: f64) callconv(.winapi) HRESULT,
    get_TopProperty: *const fn (this: *const ICanvasStatics, result: **xaml.DependencyProperty) callconv(.winapi) HRESULT,
    GetTop: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, result: *f64) callconv(.winapi) HRESULT,
    SetTop: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, value: f64) callconv(.winapi) HRESULT,
    get_ZIndexProperty: *const fn (this: *const ICanvasStatics, result: **xaml.DependencyProperty) callconv(.winapi) HRESULT,
    GetZIndex: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, result: *i32) callconv(.winapi) HRESULT,
    SetZIndex: *const fn (this: *const ICanvasStatics, element: *xaml.UIElement, value: i32) callconv(.winapi) HRESULT,
};

pub const ICanvasStatics = extern struct {
    vtable: *const ICanvasStatics_Vtbl,
    pub const Vtbl = ICanvasStatics_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC00D5E0F,
        .data2 = 0x77E3,
        .data3 = 0x5C59,
        .data4 = .{ 0x8F, 0xCD, 0x86, 0x76, 0x1F, 0x0C, 0x66, 0x07 },
    };

    pub fn QueryInterface(self: *const ICanvasStatics, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const ICanvasStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const ICanvasStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn SetLeft(self: *const ICanvasStatics, element: *xaml.UIElement, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.SetLeft(self, element, value);
    }

    pub fn SetTop(self: *const ICanvasStatics, element: *xaml.UIElement, value: f64) callconv(.winapi) HRESULT {
        return self.vtable.SetTop(self, element, value);
    }

    pub fn SetZIndex(self: *const ICanvasStatics, element: *xaml.UIElement, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.SetZIndex(self, element, value);
    }
};

pub const Canvas = extern struct {
    vtable: *const ICanvas_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Canvas";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
    pub const Statics = ICanvasStatics;

    pub fn statics() !win_core.Com(Statics.Vtbl) {
        return win_core.activationFactory(Statics.Vtbl, &Statics.IID, &NAME_W);
    }
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

    pub fn get_TextOwned(self: *const ITextBox) !win_core.Hstring {
        var text: HSTRING = null;
        try win_core.hresult.ok(self.vtable.get_Text(self, &text));
        return .fromRaw(text);
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

    pub fn Clear(self: *const IUIElementCollection) callconv(.winapi) HRESULT {
        return self.vtable.Clear(self);
    }

    pub fn Move(self: *const IUIElementCollection, from: u32, to: u32) callconv(.winapi) HRESULT {
        return self.vtable.Move(self, from, to);
    }
};

pub const IBorder_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_BorderBrush: *const fn (this: *const IBorder, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_BorderBrush: *const fn (this: *const IBorder, value: ?*anyopaque) callconv(.winapi) HRESULT,
    get_BorderThickness: *const fn (this: *const IBorder, result: *xaml.Thickness) callconv(.winapi) HRESULT,
    put_BorderThickness: *const fn (this: *const IBorder, value: xaml.Thickness) callconv(.winapi) HRESULT,
    get_Background: *const fn (this: *const IBorder, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_Background: *const fn (this: *const IBorder, value: ?*anyopaque) callconv(.winapi) HRESULT,
    get_BackgroundSizing: *const fn (this: *const IBorder, result: *BackgroundSizing) callconv(.winapi) HRESULT,
    put_BackgroundSizing: *const fn (this: *const IBorder, value: BackgroundSizing) callconv(.winapi) HRESULT,
    get_CornerRadius: *const fn (this: *const IBorder, result: *xaml.CornerRadius) callconv(.winapi) HRESULT,
    put_CornerRadius: *const fn (this: *const IBorder, value: xaml.CornerRadius) callconv(.winapi) HRESULT,
    get_Padding: *const fn (this: *const IBorder, result: *xaml.Thickness) callconv(.winapi) HRESULT,
    put_Padding: *const fn (this: *const IBorder, value: xaml.Thickness) callconv(.winapi) HRESULT,
    get_Child: *const fn (this: *const IBorder, result: *?*xaml.UIElement) callconv(.winapi) HRESULT,
    put_Child: *const fn (this: *const IBorder, value: ?*xaml.UIElement) callconv(.winapi) HRESULT,
};

pub const IBorder = extern struct {
    vtable: *const IBorder_Vtbl,
    pub const Vtbl = IBorder_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x1CA13B47,
        .data2 = 0xFF5C,
        .data3 = 0x5ABC,
        .data4 = .{ 0xA4, 0x11, 0xA1, 0x77, 0xDF, 0x94, 0x82, 0xA9 },
    };

    pub fn QueryInterface(self: *const IBorder, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IBorder) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IBorder) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IBorder, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_BorderThickness(self: *const IBorder, value: xaml.Thickness) callconv(.winapi) HRESULT {
        return self.vtable.put_BorderThickness(self, value);
    }

    pub fn put_Background(self: *const IBorder, value: ?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_Background(self, value);
    }

    pub fn put_CornerRadius(self: *const IBorder, value: xaml.CornerRadius) callconv(.winapi) HRESULT {
        return self.vtable.put_CornerRadius(self, value);
    }

    pub fn put_Child(self: *const IBorder, value: ?*xaml.UIElement) callconv(.winapi) HRESULT {
        return self.vtable.put_Child(self, value);
    }
};

pub const Border = extern struct {
    vtable: *const IBorder_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Border";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*Border {
        const raw = try win_core.activateInstance(IBorder, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const IGrid_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_RowDefinitions: *const fn (this: *const IGrid, result: **RowDefinitionCollection) callconv(.winapi) HRESULT,
    get_ColumnDefinitions: *const fn (this: *const IGrid, result: **ColumnDefinitionCollection) callconv(.winapi) HRESULT,
};

pub const IGrid = extern struct {
    vtable: *const IGrid_Vtbl,
    pub const Vtbl = IGrid_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC4496219,
        .data2 = 0x9014,
        .data3 = 0x58A1,
        .data4 = .{ 0xB4, 0xAD, 0xC5, 0x04, 0x49, 0x13, 0xA5, 0xBB },
    };

    pub fn QueryInterface(self: *const IGrid, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IGrid) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IGrid) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IGrid, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn get_RowDefinitions(self: *const IGrid, result: **RowDefinitionCollection) callconv(.winapi) HRESULT {
        return self.vtable.get_RowDefinitions(self, result);
    }

    pub fn get_ColumnDefinitions(self: *const IGrid, result: **ColumnDefinitionCollection) callconv(.winapi) HRESULT {
        return self.vtable.get_ColumnDefinitions(self, result);
    }
};

pub const IGridFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IGridFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Grid,
    ) callconv(.winapi) HRESULT,
};

pub const IGridFactory = extern struct {
    vtable: *const IGridFactory_Vtbl,
    pub const Vtbl = IGridFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xB16BF561,
        .data2 = 0xFC6C,
        .data3 = 0x57C6,
        .data4 = .{ 0x8E, 0xBC, 0x0B, 0x06, 0xCE, 0x45, 0x13, 0xAA },
    };

    pub fn QueryInterface(self: *const IGridFactory, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IGridFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IGridFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn CreateInstance(self: *const IGridFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Grid) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const IGridStatics_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_BackgroundSizingProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_BorderBrushProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_BorderThicknessProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_CornerRadiusProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_PaddingProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_RowSpacingProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_ColumnSpacingProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_RowProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetRow: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, result: *i32) callconv(.winapi) HRESULT,
    SetRow: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT,
    get_ColumnProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetColumn: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, result: *i32) callconv(.winapi) HRESULT,
    SetColumn: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT,
    get_RowSpanProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetRowSpan: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, result: *i32) callconv(.winapi) HRESULT,
    SetRowSpan: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT,
    get_ColumnSpanProperty: *const fn (this: *const IGridStatics, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetColumnSpan: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, result: *i32) callconv(.winapi) HRESULT,
    SetColumnSpan: *const fn (this: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT,
};

pub const IGridStatics = extern struct {
    vtable: *const IGridStatics_Vtbl,
    pub const Vtbl = IGridStatics_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xEF9CF81D,
        .data2 = 0xA431,
        .data3 = 0x50F4,
        .data4 = .{ 0xAB, 0xF5, 0x30, 0x23, 0xFE, 0x44, 0x77, 0x04 },
    };

    pub fn QueryInterface(self: *const IGridStatics, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IGridStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IGridStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn SetRow(self: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.SetRow(self, element_ptr, value);
    }

    pub fn SetColumn(self: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.SetColumn(self, element_ptr, value);
    }

    pub fn SetRowSpan(self: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.SetRowSpan(self, element_ptr, value);
    }

    pub fn SetColumnSpan(self: *const IGridStatics, element_ptr: *xaml.FrameworkElement, value: i32) callconv(.winapi) HRESULT {
        return self.vtable.SetColumnSpan(self, element_ptr, value);
    }
};

pub const Grid = extern struct {
    vtable: *const IGrid_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Grid";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub const Statics = IGridStatics;
    pub fn statics() !win_core.Com(Statics.Vtbl) {
        return win_core.activationFactory(Statics.Vtbl, &Statics.IID, &NAME_W);
    }
};

pub const IColumnDefinition_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Width: *const fn (this: *const IColumnDefinition, result: *xaml.GridLength) callconv(.winapi) HRESULT,
    put_Width: *const fn (this: *const IColumnDefinition, value: xaml.GridLength) callconv(.winapi) HRESULT,
};

pub const IColumnDefinition = extern struct {
    vtable: *const IColumnDefinition_Vtbl,
    pub const Vtbl = IColumnDefinition_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x454CEA14,
        .data2 = 0x87EC,
        .data3 = 0x5890,
        .data4 = .{ 0xBB, 0x62, 0xF1, 0xD8, 0x2A, 0x94, 0x75, 0x8E },
    };

    pub fn QueryInterface(self: *const IColumnDefinition, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IColumnDefinition) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IColumnDefinition) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn put_Width(self: *const IColumnDefinition, value: xaml.GridLength) callconv(.winapi) HRESULT {
        return self.vtable.put_Width(self, value);
    }
};

pub const ColumnDefinition = extern struct {
    vtable: *const IColumnDefinition_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ColumnDefinition";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*ColumnDefinition {
        const raw = try win_core.activateInstance(IColumnDefinition, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const IRowDefinition_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Height: *const fn (this: *const IRowDefinition, result: *xaml.GridLength) callconv(.winapi) HRESULT,
    put_Height: *const fn (this: *const IRowDefinition, value: xaml.GridLength) callconv(.winapi) HRESULT,
};

pub const IRowDefinition = extern struct {
    vtable: *const IRowDefinition_Vtbl,
    pub const Vtbl = IRowDefinition_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xFE870F2F,
        .data2 = 0x89EF,
        .data3 = 0x5DAC,
        .data4 = .{ 0x9F, 0x33, 0x96, 0x8D, 0x0D, 0xC5, 0x77, 0xC3 },
    };

    pub fn QueryInterface(self: *const IRowDefinition, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IRowDefinition) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IRowDefinition) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn put_Height(self: *const IRowDefinition, value: xaml.GridLength) callconv(.winapi) HRESULT {
        return self.vtable.put_Height(self, value);
    }
};

pub const RowDefinition = extern struct {
    vtable: *const IRowDefinition_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.RowDefinition";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*RowDefinition {
        const raw = try win_core.activateInstance(IRowDefinition, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const IColumnDefinitionVector_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetAt: *const fn (this: *const IColumnDefinitionVector, index: u32, result: **ColumnDefinition) callconv(.winapi) HRESULT,
    get_Size: *const fn (this: *const IColumnDefinitionVector, result: *u32) callconv(.winapi) HRESULT,
    GetView: *const fn (this: *const IColumnDefinitionVector, result: *?*anyopaque) callconv(.winapi) HRESULT,
    IndexOf: *const fn (this: *const IColumnDefinitionVector, value: *ColumnDefinition, index: *u32, found: *BOOL) callconv(.winapi) HRESULT,
    SetAt: *const fn (this: *const IColumnDefinitionVector, index: u32, value: *ColumnDefinition) callconv(.winapi) HRESULT,
    InsertAt: *const fn (this: *const IColumnDefinitionVector, index: u32, value: *ColumnDefinition) callconv(.winapi) HRESULT,
    RemoveAt: *const fn (this: *const IColumnDefinitionVector, index: u32) callconv(.winapi) HRESULT,
    Append: *const fn (this: *const IColumnDefinitionVector, value: *ColumnDefinition) callconv(.winapi) HRESULT,
    RemoveAtEnd: *const fn (this: *const IColumnDefinitionVector) callconv(.winapi) HRESULT,
    Clear: *const fn (this: *const IColumnDefinitionVector) callconv(.winapi) HRESULT,
    GetMany: *const fn (this: *const IColumnDefinitionVector, start: u32, items_len: u32, items_ptr: [*]*ColumnDefinition, written: *u32) callconv(.winapi) HRESULT,
    ReplaceAll: *const fn (this: *const IColumnDefinitionVector, items_len: u32, items_ptr: [*]const *ColumnDefinition) callconv(.winapi) HRESULT,
};

pub const IColumnDefinitionVector = extern struct {
    vtable: *const IColumnDefinitionVector_Vtbl,

    pub fn get_Size(self: *const IColumnDefinitionVector, result: *u32) callconv(.winapi) HRESULT {
        return self.vtable.get_Size(self, result);
    }

    pub fn Append(self: *const IColumnDefinitionVector, value: *ColumnDefinition) callconv(.winapi) HRESULT {
        return self.vtable.Append(self, value);
    }

    pub fn RemoveAtEnd(self: *const IColumnDefinitionVector) callconv(.winapi) HRESULT {
        return self.vtable.RemoveAtEnd(self);
    }
};

pub const ColumnDefinitionCollection = extern struct {
    vtable: *const anyopaque,
};

pub const IRowDefinitionVector_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetAt: *const fn (this: *const IRowDefinitionVector, index: u32, result: **RowDefinition) callconv(.winapi) HRESULT,
    get_Size: *const fn (this: *const IRowDefinitionVector, result: *u32) callconv(.winapi) HRESULT,
    GetView: *const fn (this: *const IRowDefinitionVector, result: *?*anyopaque) callconv(.winapi) HRESULT,
    IndexOf: *const fn (this: *const IRowDefinitionVector, value: *RowDefinition, index: *u32, found: *BOOL) callconv(.winapi) HRESULT,
    SetAt: *const fn (this: *const IRowDefinitionVector, index: u32, value: *RowDefinition) callconv(.winapi) HRESULT,
    InsertAt: *const fn (this: *const IRowDefinitionVector, index: u32, value: *RowDefinition) callconv(.winapi) HRESULT,
    RemoveAt: *const fn (this: *const IRowDefinitionVector, index: u32) callconv(.winapi) HRESULT,
    Append: *const fn (this: *const IRowDefinitionVector, value: *RowDefinition) callconv(.winapi) HRESULT,
    RemoveAtEnd: *const fn (this: *const IRowDefinitionVector) callconv(.winapi) HRESULT,
    Clear: *const fn (this: *const IRowDefinitionVector) callconv(.winapi) HRESULT,
    GetMany: *const fn (this: *const IRowDefinitionVector, start: u32, items_len: u32, items_ptr: [*]*RowDefinition, written: *u32) callconv(.winapi) HRESULT,
    ReplaceAll: *const fn (this: *const IRowDefinitionVector, items_len: u32, items_ptr: [*]const *RowDefinition) callconv(.winapi) HRESULT,
};

pub const IRowDefinitionVector = extern struct {
    vtable: *const IRowDefinitionVector_Vtbl,

    pub fn get_Size(self: *const IRowDefinitionVector, result: *u32) callconv(.winapi) HRESULT {
        return self.vtable.get_Size(self, result);
    }

    pub fn Append(self: *const IRowDefinitionVector, value: *RowDefinition) callconv(.winapi) HRESULT {
        return self.vtable.Append(self, value);
    }

    pub fn RemoveAtEnd(self: *const IRowDefinitionVector) callconv(.winapi) HRESULT {
        return self.vtable.RemoveAtEnd(self);
    }
};

pub const RowDefinitionCollection = extern struct {
    vtable: *const anyopaque,
};

pub const IScrollViewer_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IScrollViewer = extern struct {
    vtable: *const IScrollViewer_Vtbl,
    pub const Vtbl = IScrollViewer_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x1DC28C2E,
        .data2 = 0x996C,
        .data3 = 0x5394,
        .data4 = .{ 0x89, 0xC3, 0x4D, 0xC6, 0x56, 0xB4, 0xAD, 0x46 },
    };

    pub fn QueryInterface(self: *const IScrollViewer, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IScrollViewer) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IScrollViewer) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IScrollViewer, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const ScrollViewer = extern struct {
    vtable: *const IScrollViewer_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ScrollViewer";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;

    pub fn activate() !*ScrollViewer {
        const raw = try win_core.activateInstance(IScrollViewer, &NAME_W);
        return @ptrCast(raw);
    }
};

pub const SelectionChangedEventHandler = opaque {};

pub const IListView_Vtbl = extern struct {
    base: IInspectable_Vtbl,
};

pub const IListView = extern struct {
    vtable: *const IListView_Vtbl,
    pub const Vtbl = IListView_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xF6015DB1,
        .data2 = 0xDF63,
        .data3 = 0x52FD,
        .data4 = .{ 0xA1, 0x64, 0x0D, 0xF4, 0x47, 0x15, 0xEE, 0x0A },
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

pub const ListView = extern struct {
    vtable: *const IListView_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ListView";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IItemsControl_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_ItemsSource: *const fn (this: *const IItemsControl, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_ItemsSource: *const fn (this: *const IItemsControl, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
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

    pub fn get_IsOn(self: *const IToggleSwitch, result: *BOOL) callconv(.winapi) HRESULT {
        return self.vtable.get_IsOn(self, result);
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

pub const IItemsRepeater_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_ItemsSource: *const fn (this: *const IItemsRepeater, result: *?*const anyopaque) callconv(.winapi) HRESULT,
    put_ItemsSource: *const fn (this: *const IItemsRepeater, p0: ?*const anyopaque) callconv(.winapi) HRESULT,
};

pub const IItemsRepeater = extern struct {
    vtable: *const IItemsRepeater_Vtbl,
    pub const Vtbl = IItemsRepeater_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x9DABAC84,
        .data2 = 0xFE81,
        .data3 = 0x53D1,
        .data4 = .{ 0xA0, 0x41, 0x7A, 0x3B, 0xEF, 0xEA, 0x50, 0x5F },
    };

    pub fn QueryInterface(self: *const IItemsRepeater, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IItemsRepeater) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IItemsRepeater) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IItemsRepeater, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_ItemsSource(self: *const IItemsRepeater, value: ?*const anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_ItemsSource(self, value);
    }
};

pub const ItemsRepeater = extern struct {
    vtable: *const IItemsRepeater_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ItemsRepeater";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IItemsRepeaterFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IItemsRepeaterFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **ItemsRepeater,
    ) callconv(.winapi) HRESULT,
};

pub const IItemsRepeaterFactory = extern struct {
    vtable: *const IItemsRepeaterFactory_Vtbl,
    pub const Vtbl = IItemsRepeaterFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xC3C1F244,
        .data2 = 0x67A8,
        .data3 = 0x568F,
        .data4 = .{ 0xA6, 0xF7, 0x5D, 0xA8, 0xB0, 0xEA, 0xDD, 0x49 },
    };

    pub fn QueryInterface(self: *const IItemsRepeaterFactory, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IItemsRepeaterFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IItemsRepeaterFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IItemsRepeaterFactory, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn CreateInstance(self: *const IItemsRepeaterFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **ItemsRepeater) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const IListViewFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IListViewFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **ListView,
    ) callconv(.winapi) HRESULT,
};

pub const IListViewFactory = extern struct {
    vtable: *const IListViewFactory_Vtbl,
    pub const Vtbl = IListViewFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x03EBEFB8,
        .data2 = 0xF64A,
        .data3 = 0x5BF9,
        .data4 = .{ 0x95, 0x70, 0xCB, 0x09, 0xEE, 0xEA, 0x23, 0x35 },
    };

    pub fn QueryInterface(self: *const IListViewFactory, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IListViewFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IListViewFactory) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IListViewFactory, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn CreateInstance(self: *const IListViewFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **ListView) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const ContentDialogResult = enum(i32) {
    None = 0,
    Primary = 1,
    Secondary = 2,
    _,
};

pub const IContentDialog_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Title: *const anyopaque,
    put_Title: *const fn (this: *const IContentDialog, value: ?*const anyopaque) callconv(.winapi) HRESULT,
    get_TitleTemplate: *const anyopaque,
    put_TitleTemplate: *const anyopaque,
    get_FullSizeDesired: *const anyopaque,
    put_FullSizeDesired: *const anyopaque,
    get_PrimaryButtonText: *const anyopaque,
    put_PrimaryButtonText: *const fn (this: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT,
    get_SecondaryButtonText: *const anyopaque,
    put_SecondaryButtonText: *const fn (this: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT,
    get_CloseButtonText: *const anyopaque,
    put_CloseButtonText: *const fn (this: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT,
    get_PrimaryButtonCommand: *const anyopaque,
    put_PrimaryButtonCommand: *const anyopaque,
    get_SecondaryButtonCommand: *const anyopaque,
    put_SecondaryButtonCommand: *const anyopaque,
    get_CloseButtonCommand: *const anyopaque,
    put_CloseButtonCommand: *const anyopaque,
    get_PrimaryButtonCommandParameter: *const anyopaque,
    put_PrimaryButtonCommandParameter: *const anyopaque,
    get_SecondaryButtonCommandParameter: *const anyopaque,
    put_SecondaryButtonCommandParameter: *const anyopaque,
    get_CloseButtonCommandParameter: *const anyopaque,
    put_CloseButtonCommandParameter: *const anyopaque,
    get_IsPrimaryButtonEnabled: *const anyopaque,
    put_IsPrimaryButtonEnabled: *const anyopaque,
    get_IsSecondaryButtonEnabled: *const anyopaque,
    put_IsSecondaryButtonEnabled: *const anyopaque,
    get_PrimaryButtonStyle: *const anyopaque,
    put_PrimaryButtonStyle: *const anyopaque,
    get_SecondaryButtonStyle: *const anyopaque,
    put_SecondaryButtonStyle: *const anyopaque,
    get_CloseButtonStyle: *const anyopaque,
    put_CloseButtonStyle: *const anyopaque,
    get_DefaultButton: *const anyopaque,
    put_DefaultButton: *const anyopaque,
    add_Closing: *const anyopaque,
    remove_Closing: *const anyopaque,
    add_Closed: *const anyopaque,
    remove_Closed: *const anyopaque,
    add_Opened: *const anyopaque,
    remove_Opened: *const anyopaque,
    add_PrimaryButtonClick: *const anyopaque,
    remove_PrimaryButtonClick: *const anyopaque,
    add_SecondaryButtonClick: *const anyopaque,
    remove_SecondaryButtonClick: *const anyopaque,
    add_CloseButtonClick: *const anyopaque,
    remove_CloseButtonClick: *const anyopaque,
    Hide: *const fn (this: *const IContentDialog) callconv(.winapi) HRESULT,
    ShowAsync: *const fn (this: *const IContentDialog, result: **anyopaque) callconv(.winapi) HRESULT,
    ShowAsync_2: *const anyopaque,
};

pub const IContentDialog = extern struct {
    vtable: *const IContentDialog_Vtbl,
    pub const Vtbl = IContentDialog_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xAC2145A3,
        .data2 = 0x4A32,
        .data3 = 0x5305,
        .data4 = .{ 0xA8, 0x1D, 0x47, 0x50, 0x95, 0x15, 0xBF, 0xCE },
    };

    pub fn QueryInterface(self: *const IContentDialog, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IContentDialog) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IContentDialog) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IContentDialog, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Title(self: *const IContentDialog, value: ?*const anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.put_Title(self, value);
    }

    pub fn put_PrimaryButtonText(self: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_PrimaryButtonText(self, value);
    }

    pub fn put_PrimaryButtonTextFromUtf16(self: *const IContentDialog, value: []const u16) HRESULT {
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_PrimaryButtonText(self, h.raw);
    }

    pub fn put_SecondaryButtonText(self: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_SecondaryButtonText(self, value);
    }

    pub fn put_SecondaryButtonTextFromUtf16(self: *const IContentDialog, value: []const u16) HRESULT {
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_SecondaryButtonText(self, h.raw);
    }

    pub fn put_CloseButtonText(self: *const IContentDialog, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_CloseButtonText(self, value);
    }

    pub fn put_CloseButtonTextFromUtf16(self: *const IContentDialog, value: []const u16) HRESULT {
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_CloseButtonText(self, h.raw);
    }

    pub fn Hide(self: *const IContentDialog) callconv(.winapi) HRESULT {
        return self.vtable.Hide(self);
    }

    pub fn ShowAsync(self: *const IContentDialog, result: **anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.ShowAsync(self, result);
    }
};

pub const IContentDialogFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IContentDialogFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **ContentDialog,
    ) callconv(.winapi) HRESULT,
};

pub const IContentDialogFactory = extern struct {
    vtable: *const IContentDialogFactory_Vtbl,
    pub const Vtbl = IContentDialogFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xA05B3AD7,
        .data2 = 0xC60E,
        .data3 = 0x545A,
        .data4 = .{ 0x9E, 0xE4, 0xF0, 0x98, 0x22, 0x0E, 0xD8, 0x16 },
    };

    pub fn CreateInstance(self: *const IContentDialogFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **ContentDialog) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const ContentDialog = extern struct {
    vtable: *const IContentDialog_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.ContentDialog";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IFlyout_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Content: *const anyopaque,
    put_Content: *const fn (this: *const IFlyout, value: ?*xaml.UIElement) callconv(.winapi) HRESULT,
    get_FlyoutPresenterStyle: *const anyopaque,
    put_FlyoutPresenterStyle: *const anyopaque,
};

pub const IFlyout = extern struct {
    vtable: *const IFlyout_Vtbl,
    pub const Vtbl = IFlyout_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xD4A1EB7D,
        .data2 = 0x59B8,
        .data3 = 0x5DF9,
        .data4 = .{ 0x87, 0xC3, 0xBD, 0x5E, 0x38, 0x56, 0x92, 0x3F },
    };

    pub fn QueryInterface(self: *const IFlyout, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IFlyout) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IFlyout) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const IFlyout, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn put_Content(self: *const IFlyout, value: ?*xaml.UIElement) callconv(.winapi) HRESULT {
        return self.vtable.put_Content(self, value);
    }
};

pub const IFlyoutFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IFlyoutFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **Flyout,
    ) callconv(.winapi) HRESULT,
};

pub const IFlyoutFactory = extern struct {
    vtable: *const IFlyoutFactory_Vtbl,
    pub const Vtbl = IFlyoutFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xFD19002E,
        .data2 = 0x66B3,
        .data3 = 0x5656,
        .data4 = .{ 0xB4, 0x9C, 0xB2, 0xAC, 0xA1, 0x1E, 0x96, 0x02 },
    };

    pub fn CreateInstance(self: *const IFlyoutFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **Flyout) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const Flyout = extern struct {
    vtable: *const IFlyout_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.Flyout";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IMenuBar_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Items: *const fn (this: *const IMenuBar, result: **anyopaque) callconv(.winapi) HRESULT,
};

pub const IMenuBar = extern struct {
    vtable: *const IMenuBar_Vtbl,
    pub const Vtbl = IMenuBar_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xBA97F337,
        .data2 = 0x8F1E,
        .data3 = 0x5141,
        .data4 = .{ 0xB5, 0x3F, 0xE7, 0x7A, 0x8B, 0xA3, 0xEB, 0xBD },
    };

    pub fn QueryInterface(self: *const IMenuBar, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IMenuBar) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IMenuBar) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_Items(self: *const IMenuBar, result: **anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.get_Items(self, result);
    }
};

pub const IMenuBarFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IMenuBarFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **MenuBar,
    ) callconv(.winapi) HRESULT,
};

pub const IMenuBarFactory = extern struct {
    vtable: *const IMenuBarFactory_Vtbl,
    pub const Vtbl = IMenuBarFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x76AA8759,
        .data2 = 0x04EE,
        .data3 = 0x5A4C,
        .data4 = .{ 0xB9, 0x8C, 0xD0, 0x37, 0x42, 0xD4, 0x7C, 0xDB },
    };

    pub fn CreateInstance(self: *const IMenuBarFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **MenuBar) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const MenuBar = extern struct {
    vtable: *const IMenuBar_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.MenuBar";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const IMenuBarItem_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Title: *const anyopaque,
    put_Title: *const fn (this: *const IMenuBarItem, value: HSTRING) callconv(.winapi) HRESULT,
    get_Items: *const fn (this: *const IMenuBarItem, result: **anyopaque) callconv(.winapi) HRESULT,
};

pub const IMenuBarItem = extern struct {
    vtable: *const IMenuBarItem_Vtbl,
    pub const Vtbl = IMenuBarItem_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xA7900980,
        .data2 = 0x51CC,
        .data3 = 0x531D,
        .data4 = .{ 0x97, 0xC5, 0x35, 0x6B, 0x13, 0x57, 0x33, 0x98 },
    };

    pub fn QueryInterface(self: *const IMenuBarItem, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IMenuBarItem) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IMenuBarItem) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn put_Title(self: *const IMenuBarItem, value: HSTRING) callconv(.winapi) HRESULT {
        return self.vtable.put_Title(self, value);
    }

    pub fn put_TitleFromUtf16(self: *const IMenuBarItem, value: []const u16) HRESULT {
        var h = win_core.Hstring.create(value) catch return win_core.hresult.E_OUTOFMEMORY;
        defer h.deinit();
        return self.vtable.put_Title(self, h.raw);
    }

    pub fn get_Items(self: *const IMenuBarItem, result: **anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.get_Items(self, result);
    }
};

pub const IMenuBarItemFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const IMenuBarItemFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **MenuBarItem,
    ) callconv(.winapi) HRESULT,
};

pub const IMenuBarItemFactory = extern struct {
    vtable: *const IMenuBarItemFactory_Vtbl,
    pub const Vtbl = IMenuBarItemFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x87D02172,
        .data2 = 0x83CB,
        .data3 = 0x5459,
        .data4 = .{ 0x94, 0x0F, 0x17, 0x3F, 0x75, 0x01, 0xB3, 0x00 },
    };

    pub fn CreateInstance(self: *const IMenuBarItemFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **MenuBarItem) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const MenuBarItem = extern struct {
    vtable: *const IMenuBarItem_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.MenuBarItem";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const INavigationView_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_IsPaneOpen: *const anyopaque,
    put_IsPaneOpen: *const anyopaque,
    get_CompactModeThresholdWidth: *const anyopaque,
    put_CompactModeThresholdWidth: *const anyopaque,
    get_ExpandedModeThresholdWidth: *const anyopaque,
    put_ExpandedModeThresholdWidth: *const anyopaque,
    get_FooterMenuItems: *const anyopaque,
    get_FooterMenuItemsSource: *const anyopaque,
    put_FooterMenuItemsSource: *const anyopaque,
    get_PaneFooter: *const anyopaque,
    put_PaneFooter: *const anyopaque,
    get_Header: *const anyopaque,
    put_Header: *const anyopaque,
    get_HeaderTemplate: *const anyopaque,
    put_HeaderTemplate: *const anyopaque,
    get_DisplayMode: *const anyopaque,
    get_IsSettingsVisible: *const anyopaque,
    put_IsSettingsVisible: *const anyopaque,
    get_IsPaneToggleButtonVisible: *const anyopaque,
    put_IsPaneToggleButtonVisible: *const anyopaque,
    get_AlwaysShowHeader: *const anyopaque,
    put_AlwaysShowHeader: *const anyopaque,
    get_CompactPaneLength: *const anyopaque,
    put_CompactPaneLength: *const anyopaque,
    get_OpenPaneLength: *const anyopaque,
    put_OpenPaneLength: *const anyopaque,
    get_PaneToggleButtonStyle: *const anyopaque,
    put_PaneToggleButtonStyle: *const anyopaque,
    get_SelectedItem: *const anyopaque,
    put_SelectedItem: *const anyopaque,
    get_MenuItems: *const fn (this: *const INavigationView, result: **anyopaque) callconv(.winapi) HRESULT,
};

pub const INavigationView = extern struct {
    vtable: *const INavigationView_Vtbl,
    pub const Vtbl = INavigationView_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xE77A4B36,
        .data2 = 0x3DD1,
        .data3 = 0x53D9,
        .data4 = .{ 0x9F, 0x97, 0x65, 0xDC, 0xCA, 0xA7, 0x4A, 0x5C },
    };

    pub fn QueryInterface(self: *const INavigationView, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const INavigationView) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const INavigationView) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const INavigationView, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }

    pub fn get_MenuItems(self: *const INavigationView, result: **anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.get_MenuItems(self, result);
    }
};

pub const INavigationViewFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const INavigationViewFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **NavigationView,
    ) callconv(.winapi) HRESULT,
};

pub const INavigationViewFactory = extern struct {
    vtable: *const INavigationViewFactory_Vtbl,
    pub const Vtbl = INavigationViewFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xFFEA1ADA,
        .data2 = 0x9232,
        .data3 = 0x5507,
        .data4 = .{ 0xA3, 0x20, 0xED, 0x2F, 0xAD, 0xBE, 0x61, 0x27 },
    };

    pub fn CreateInstance(self: *const INavigationViewFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **NavigationView) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const NavigationView = extern struct {
    vtable: *const INavigationView_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.NavigationView";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};

pub const INavigationViewItem_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Icon: *const anyopaque,
    put_Icon: *const anyopaque,
    get_CompactPaneLength: *const anyopaque,
};

pub const INavigationViewItem = extern struct {
    vtable: *const INavigationViewItem_Vtbl,
    pub const Vtbl = INavigationViewItem_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x3AB3D503,
        .data2 = 0xA37C,
        .data3 = 0x5836,
        .data4 = .{ 0x8A, 0xDB, 0x28, 0x82, 0x06, 0x2E, 0x73, 0xA1 },
    };

    pub fn QueryInterface(self: *const INavigationViewItem, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const INavigationViewItem) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const INavigationViewItem) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn cast(self: *const INavigationViewItem, comptime T: type) ?*const T {
        var out: ?*anyopaque = null;
        if (self.QueryInterface(&T.IID, &out) < 0) return null;
        return @ptrCast(@alignCast(out));
    }
};

pub const INavigationViewItemFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateInstance: *const fn (
        this: *const INavigationViewItemFactory,
        outer: ?*const anyopaque,
        inner: *?*const anyopaque,
        result: **NavigationViewItem,
    ) callconv(.winapi) HRESULT,
};

pub const INavigationViewItemFactory = extern struct {
    vtable: *const INavigationViewItemFactory_Vtbl,
    pub const Vtbl = INavigationViewItemFactory_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xDE60A001,
        .data2 = 0x9385,
        .data3 = 0x5535,
        .data4 = .{ 0x80, 0xE1, 0x2B, 0x68, 0xF4, 0xBF, 0xDE, 0x26 },
    };

    pub fn CreateInstance(self: *const INavigationViewItemFactory, outer: ?*const anyopaque, inner: *?*const anyopaque, result: **NavigationViewItem) callconv(.winapi) HRESULT {
        return self.vtable.CreateInstance(self, outer, inner, result);
    }
};

pub const NavigationViewItem = extern struct {
    vtable: *const INavigationViewItem_Vtbl,
    pub const NAME: []const u8 = "Microsoft.UI.Xaml.Controls.NavigationViewItem";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
};
