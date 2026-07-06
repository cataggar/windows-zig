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
        },
        .events = .{
            .Click = Event{
                .payload = .unit,
            },
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
        },
    },

    .@"Microsoft.UI.Xaml.Controls.TextBlock" = .{
        .props = .{
            .Text = Prop{
                .value = .string,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.TextBox" = .{
        .events = .{
            .TextChanged = Event{
                .payload = .string,
                .source = .{
                    .sender_property = "Text",
                },
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
