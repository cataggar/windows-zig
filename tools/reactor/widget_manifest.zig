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
        .props = .{
            .Text = Prop{
                .value = .string,
            },
        },
        .events = .{
            .TextChanged = Event{
                .payload = .string,
                .source = .{
                    .sender_property = "Text",
                },
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.CheckBox" = .{
        .props = .{
            .Content = Prop{
                .value = .string,
                .setter = .text_block,
            },
            .IsChecked = Prop{
                .value = .bool,
                .setter = .boxed_reference,
            },
        },
        .events = .{
            .Checked = Event{
                .payload = .unit,
            },
            .Unchecked = Event{
                .payload = .unit,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.Slider" = .{
        .props = .{
            .Value = Prop{
                .value = .f64,
            },
            .Minimum = Prop{
                .value = .f64,
            },
            .Maximum = Prop{
                .value = .f64,
            },
        },
        .events = .{
            .ValueChanged = Event{
                .payload = .f64,
                .source = .{
                    .args_property = "NewValue",
                },
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ComboBox" = .{
        .props = .{
            .ItemsSource = Prop{
                .value = .string_list,
            },
            .SelectedIndex = Prop{
                .value = .i32,
            },
        },
        .events = .{
            .SelectionChanged = Event{
                .payload = .i32,
                .source = .{
                    .sender_property = "SelectedIndex",
                },
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ToggleSwitch" = .{
        .props = .{
            .IsOn = Prop{
                .value = .bool,
            },
        },
        .events = .{
            .Toggled = Event{
                .payload = .bool,
                .source = .{
                    .sender_property = "IsOn",
                },
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.RadioButton" = .{
        .props = .{
            .Content = Prop{
                .value = .string,
                .setter = .text_block,
            },
            .IsChecked = Prop{
                .value = .bool,
                .setter = .boxed_reference,
            },
        },
        .events = .{
            .Checked = Event{
                .payload = .unit,
            },
        },
    },
};
