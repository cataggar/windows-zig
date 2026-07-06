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
const grid_row = Prop{
    .winrt_name = "Row",
    .field = "grid_row",
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Grid",
        .setter = "SetRow",
    },
};
const grid_column = Prop{
    .winrt_name = "Column",
    .field = "grid_column",
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Grid",
        .setter = "SetColumn",
    },
};
const grid_row_span = Prop{
    .winrt_name = "RowSpan",
    .field = "grid_row_span",
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Grid",
        .setter = "SetRowSpan",
    },
};
const grid_column_span = Prop{
    .winrt_name = "ColumnSpan",
    .field = "grid_column_span",
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Grid",
        .setter = "SetColumnSpan",
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
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
        },
        .events = .{
            .PointerPressed = pointer_pressed,
            .PointerMoved = pointer_moved,
            .PointerReleased = pointer_released,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.TextBox" = .{
        .props = .{
            .Text = Prop{
                .value = .string,
            },
            .Left = canvas_left,
            .Top = canvas_top,
            .ZIndex = canvas_z_index,
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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

    .@"Microsoft.UI.Xaml.Controls.Grid" = .{
        .props = .{
            .RowDefinitions = Prop{
                .manual = true,
            },
            .ColumnDefinitions = Prop{
                .manual = true,
            },
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ScrollViewer" = .{
        .props = .{
            .Content = Prop{
                .value = .element,
            },
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
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

    .@"Microsoft.UI.Xaml.Controls.ListView" = .{
        .props = .{
            .ItemsSource = Prop{
                .value = .object,
            },
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
        },
        .events = .{
            .SelectionChanged = Event{
                .payload = .unit,
            },
        },
    },

    .@"Microsoft.UI.Xaml.Controls.ItemsRepeater" = .{
        .props = .{
            .ItemsSource = Prop{
                .value = .object,
            },
            .@"Grid.Row" = grid_row,
            .@"Grid.Column" = grid_column,
            .@"Grid.RowSpan" = grid_row_span,
            .@"Grid.ColumnSpan" = grid_column_span,
        },
    },
};
