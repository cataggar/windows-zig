const generated = @import("generated/generated_attach_event.zig");

test "generated attach event glue compiles against a minimal WinUI slice" {
    // This canary intentionally uses a tiny signature-accurate WinUI
    // surface instead of the full committed snapshots, matching the
    // existing `winui_minimal_bindings` strategy for WinUI compile
    // coverage in this repository.
    _ = generated.entries.len;
    _ = generated.connectMicrosoftUIXamlControlsButtonClick;
    _ = generated.disconnectMicrosoftUIXamlControlsButtonClick;
    _ = generated.connectMicrosoftUIXamlControlsListViewSelectionChanged;
    _ = generated.disconnectMicrosoftUIXamlControlsListViewSelectionChanged;
    _ = generated.connectMicrosoftUIXamlControlsTextBoxTextChanged;
    _ = generated.disconnectMicrosoftUIXamlControlsTextBoxTextChanged;
}
