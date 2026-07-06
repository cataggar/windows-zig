//! Hand-authored WinUI3 widget manifest for future reactor codegen.
//!
//! The shape intentionally mirrors the Rust reactor's `winui.toml`:
//! full WinRT class names key the top-level object, and each widget
//! section lists only the properties/events that need generated glue.
//! Zig adapts the format by splitting members into `.props` and `.events`
//! tables and by using typed enums instead of stringly TOML fields.

const schema = @import("schema.zig");

const Event = schema.EventInit;
const Prop = schema.PropInit;

const canvas_left = Prop{
    .value = .f64,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Canvas",
        .setter = "SetLeft",
    },
};
const canvas_top = Prop{
    .value = .f64,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Canvas",
        .setter = "SetTop",
    },
};
const canvas_z_index = Prop{
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Canvas",
        .setter = "SetZIndex",
    },
};
const pointer_pressed = Event{ .payload = .pointer };
const pointer_moved = Event{ .payload = .pointer };
const pointer_released = Event{ .payload = .pointer };

pub const raw_widgets = .{
    .@"Microsoft.UI.Xaml.Application" = .{},

    .@"Microsoft.UI.Xaml.Window" = .{
        .props = .{
            .Title = Prop{
                .value = .string,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Button" = .{
        .props = .{
            .Content = Prop{
                .value = .string,
                .setter = .text_block,
            },
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
        },
        .events = .{
            .Click = Event{
                .payload = .unit,
            },
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Canvas" = .{
        .props = .{
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
        },
        .events = .{
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.StackPanel" = .{
        .props = .{
            .Orientation = Prop{
                .value = .enum_i32,
            },
            .Spacing = Prop{
                .value = .f64,
            },
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
        },
        .events = .{
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.TextBlock" = .{
        .props = .{
            .Text = Prop{
                .value = .string,
            },
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
        },
        .events = .{
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.TextBox" = .{
        .props = .{
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
        },
        .events = .{
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
            .TextChanged = Event{
                .payload = .string,
                .source = .{
                    .sender_property = "Text",
                },
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Grid" = .{
        .props = .{
            .RowDefinitions = Prop{
                .manual = true,
            },
            .ColumnDefinitions = Prop{
                .manual = true,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ScrollViewer" = .{
        .props = .{
            .Content = Prop{
                .value = .element,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Border" = .{
        .props = .{
            .Child = Prop{
                .value = .element,
            },
            .BorderThickness = Prop{
                .manual = true,
            },
            .CornerRadius = Prop{
                .manual = true,
            },
            .Background = Prop{
                .manual = true,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ContentDialog" = .{
        .props = .{
            .Title = Prop{
                .value = .string,
                .setter = .text_block,
            },
            .Content = Prop{
                .value = .element,
            },
            .PrimaryButtonText = Prop{
                .value = .string,
            },
            .SecondaryButtonText = Prop{
                .value = .string,
            },
            .CloseButtonText = Prop{
                .value = .string,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Flyout" = .{
        .props = .{
            .Content = Prop{
                .value = .element,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.NavigationView" = .{
        .props = .{
            .Content = Prop{
                .value = .element,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.NavigationViewItem" = .{
        .props = .{
            .Content = Prop{
                .value = .string,
                .setter = .text_block,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.MenuBar" = .{},

    .@"Microsoft.UI.Xaml.Controls.MenuBarItem" = .{
        .props = .{
            .Title = Prop{
                .value = .string,
            },
        },
    },
};
