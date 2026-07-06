//! `win-reactor` — a reconciler-driven hook engine plus the first real
//! WinUI 3 backend and app host.

const context = @import("context.zig");
const element = @import("element.zig");
const recording_backend = @import("recording_backend.zig");
const backend = @import("backend.zig");
const reconciler = @import("reconciler.zig");
const render_cx = @import("render_cx.zig");
const app = @import("app.zig");
const widgets = @import("widgets.zig");
const winui_backend = @import("winui_backend.zig");
const winui_dispatcher = @import("winui_dispatcher.zig");

pub const ContextId = context.ContextId;
pub const Context = context.Context;
pub const ContextScope = context.ContextScope;
pub const ContextStack = context.ContextStack;

pub const WidgetKind = element.WidgetKind;
pub const EventCallback = element.EventCallback;
pub const EventHandler = element.EventHandler;
pub const Property = element.Property;
pub const ContextProvision = element.ContextProvision;
pub const WidgetElement = element.WidgetElement;
pub const ComponentElement = element.ComponentElement;
pub const ProviderElement = element.ProviderElement;
pub const GroupElement = element.GroupElement;
pub const Visitor = element.Visitor;
pub const Element = element.Element;
pub const ElementError = element.Error;
pub const LeafBuilder = element.LeafBuilder;
pub const ContainerBuilder = element.ContainerBuilder;
pub const ApplicationBuilder = element.ApplicationBuilder;
pub const WindowBuilder = element.WindowBuilder;
pub const ButtonBuilder = element.ButtonBuilder;
pub const StackPanelBuilder = element.StackPanelBuilder;
pub const TextBlockBuilder = element.TextBlockBuilder;
pub const TextBoxBuilder = element.TextBoxBuilder;
pub const leaf = element.leaf;
pub const container = element.container;
pub const application = element.application;
pub const application_builder = element.application;
pub const window = element.window;
pub const window_builder = element.window;
pub const button_builder = element.button;
pub const stack_panel = element.stack_panel;
pub const stack_panel_builder = element.stack_panel;
pub const text_block_builder = element.text_block;
pub const text_box = element.text_box;
pub const text_box_builder = element.text_box;
pub const DefaultStackSpacing = widgets.DefaultStackSpacing;
pub const button = widgets.button;
pub const text_block = widgets.text_block;
pub const vstack = widgets.vstack;
pub const hstack = widgets.hstack;
pub const component = element.component;
pub const memo = element.memo;
pub const group = element.group;
pub const provide = element.provide;
pub const intoElement = element.intoElement;
pub const collectElements = element.collectElements;

pub const WidgetId = backend.WidgetId;
pub const Backend = backend.Backend;
pub const WinUIBackend = winui_backend.WinUIBackend;
pub const RecordingBackend = recording_backend.RecordingBackend;

pub const RequestRerender = render_cx.RequestRerender;
pub const ContextIdSet = render_cx.ContextIdSet;
pub const HookSlot = render_cx.HookSlot;
pub const RenderCx = render_cx.RenderCx;

pub const SetState = render_cx.SetState;
pub const StateResult = render_cx.StateResult;
pub const Updater = render_cx.Updater;
pub const ReducerResult = render_cx.ReducerResult;
pub const Dispatch = render_cx.Dispatch;
pub const ReducerFnResult = render_cx.ReducerFnResult;
pub const HookRef = render_cx.HookRef;
pub const AsyncSetState = render_cx.AsyncSetState;
pub const AsyncStateResult = render_cx.AsyncStateResult;

pub const Tree = reconciler.Tree;
pub const MountedWidget = reconciler.MountedWidget;
pub const MountedComponent = reconciler.MountedComponent;
pub const MountedProvider = reconciler.MountedProvider;
pub const MountedGroup = reconciler.MountedGroup;
pub const MountedElement = reconciler.MountedElement;
pub const Reconciler = reconciler.Reconciler;

pub const Error = render_cx.Error;
pub const App = app.App;
pub const RootRenderFn = app.RootRenderFn;
pub const DispatcherPriority = winui_dispatcher.DispatcherPriority;
pub const UiTask = winui_dispatcher.Task;
pub const SendDispatcher = winui_dispatcher.SendDispatcher;
pub const UiMarshaller = winui_dispatcher.UiMarshaller;
pub const ChannelDispatcher = winui_dispatcher.ChannelDispatcher;
pub const WinUIDispatcher = winui_dispatcher.WinUIDispatcher;
pub const Win = @import("win");
pub const Xaml = @import("Microsoft.UI.Xaml");
pub const XamlControls = @import("Microsoft.UI.Xaml.Controls");
pub const XamlControlsPrimitives = @import("Microsoft.UI.Xaml.Controls.Primitives");

test {
    _ = @import("app.zig");
    _ = @import("backend.zig");
    _ = @import("context.zig");
    _ = @import("element.zig");
    _ = @import("recording_backend.zig");
    _ = @import("reconciler.zig");
    _ = @import("render_cx.zig");
    _ = @import("widgets.zig");
    _ = @import("winui_backend.zig");
    _ = @import("winui_dispatcher.zig");
}

const widgets_navigation = @import("widgets_navigation.zig");

pub const WidgetRef = element.WidgetRef;
pub const ContentDialogBuilder = element.ContentDialogBuilder;
pub const FlyoutBuilder = element.FlyoutBuilder;
pub const NavigationViewBuilder = element.NavigationViewBuilder;
pub const NavigationViewItemBuilder = element.NavigationViewItemBuilder;
pub const MenuBarBuilder = element.MenuBarBuilder;
pub const MenuBarItemBuilder = element.MenuBarItemBuilder;
pub const content_dialog_builder = element.content_dialog;
pub const flyout_builder = element.flyout;
pub const navigation_view_builder = element.navigation_view;
pub const navigation_view_item_builder = element.navigation_view_item;
pub const menu_bar_builder = element.menu_bar;
pub const menu_bar_item_builder = element.menu_bar_item;
pub const OverlayHost = widgets_navigation.OverlayHost;
pub const ContentDialogHandle = widgets_navigation.ContentDialogHandle;
pub const FlyoutHandle = widgets_navigation.FlyoutHandle;
pub const ContentDialogFuture = widgets_navigation.ContentDialogFuture;
pub const ContentDialogOptions = widgets_navigation.ContentDialogOptions;
pub const ContentDialogResult = widgets_navigation.ContentDialogResult;
pub const OverlayHostContext = &widgets_navigation.overlay_host_context;
pub const with_ref = widgets_navigation.with_ref;
pub const content_dialog = widgets_navigation.content_dialog;
pub const flyout = widgets_navigation.flyout;
pub const navigation_view = widgets_navigation.navigation_view;
pub const navigation_view_item = widgets_navigation.navigation_view_item;
pub const menu_bar = widgets_navigation.menu_bar;
pub const menu_bar_item = widgets_navigation.menu_bar_item;
pub const useOverlayHost = widgets_navigation.useOverlayHost;
pub const useContentDialog = widgets_navigation.useContentDialog;
pub const useFlyout = widgets_navigation.useFlyout;
