const ui = @import("Microsoft.UI");
const composition = @import("Microsoft.UI.Composition");
const content = @import("Microsoft.UI.Content");
const dispatching = @import("Microsoft.UI.Dispatching");
const input = @import("Microsoft.UI.Input");
const windowing = @import("Microsoft.UI.Windowing");

test "WinUI dependency namespaces expose concrete projected types" {
    _ = ui.WindowId;
    _ = composition.Compositor;
    _ = content.ContentIsland;
    _ = dispatching.DispatcherQueue;
    _ = input.InputPointerSource;
    _ = windowing.AppWindow;
}
