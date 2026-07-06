# vendor/winmd/

Vendored ECMA-335 `.winmd` metadata consumed by `winmd`/`winbindgen` (and, by
extension, the generated `win-sys`/`win` sources).

## Committed files (MIT-licensed)

These come from the [win32metadata](https://github.com/microsoft/win32metadata)
project and are committed to git, matching the same files windows-rs uses to
generate the `windows`/`windows-sys` crates.

| File | Source NuGet package | Version |
|------|----------------------|---------|
| `Windows.winmd` | [`Microsoft.Windows.SDK.Contracts`](https://www.nuget.org/packages/Microsoft.Windows.SDK.Contracts) | `10.0.26100.7705` |
| `Windows.Win32.winmd` | [`Microsoft.Windows.SDK.Win32Metadata`](https://www.nuget.org/packages/Microsoft.Windows.SDK.Win32Metadata) | `70.0.11` |
| `Windows.Wdk.winmd` | [`Microsoft.Windows.WDK.Win32Metadata`](https://www.nuget.org/packages/Microsoft.Windows.WDK.Win32Metadata) | `0.13.25` |

`Windows.winmd` was produced by merging the `Microsoft.Windows.SDK.Contracts`
package's `.winmd` files with `mdmerge -o out -i . -n 1` (see
[windows-rs's own notes](https://github.com/microsoft/windows-rs/blob/master/crates/libs/bindgen/default/readme.md)
on these same three files — copied here rather than regenerated, since the
merge step requires the Windows SDK's `mdmerge` tool).

Refresh by copying the latest files from
`windows-rs/crates/libs/bindgen/default/*.winmd` (or redoing the NuGet
download + merge steps above) and updating this table.

## Fetched-on-demand files (proprietary-licensed — NOT committed)

| File | Source NuGet package | Version |
|------|----------------------|---------|
| `Microsoft.UI.Xaml.winmd` | [`Microsoft.WindowsAppSDK.WinUI`](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI) | `2.2.1` |
| `Microsoft.UI.Text.winmd` | [`Microsoft.WindowsAppSDK.WinUI`](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI) | `2.2.1` |
| `Microsoft.UI.winmd` | [`Microsoft.WindowsAppSDK.InteractiveExperiences`](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.InteractiveExperiences) | `2.0.15` |

The WindowsAppSDK/WinUI NuGet packages ship under Microsoft's proprietary
"Windows App SDK" software license terms (`requireLicenseAcceptance=true`),
**not** MIT — unlike the win32metadata-derived files above. Redistributing
that binary in this MIT-licensed public repo isn't appropriate, so these three
files are `.gitignore`d and fetched locally instead, the same way
[windows-rs itself never commits any `.winmd` to git](https://github.com/microsoft/windows-rs)
(its top-level `winmd/` directory is populated out of band and is entirely
`.gitignore`d there too).

Fetch them with:

```sh
zig build fetch-winui-metadata
```

`zig build bindings` also invokes that step automatically before
emitting the WinUI snapshot files under `packages/win/src/generated/`.

This downloads `Microsoft.WindowsAppSDK.WinUI.2.2.1.nupkg` and
`Microsoft.WindowsAppSDK.InteractiveExperiences.2.0.15.nupkg` from
nuget.org, verifies each one against a pinned sha256 in
`tools/fetch-winui-metadata/main.zig`, extracts
`metadata/Microsoft.UI.Xaml.winmd`, `metadata/Microsoft.UI.Text.winmd`,
and `metadata/10.0.18362.0/Microsoft.UI.winmd`, and writes them here.
The helper is idempotent: once all three `.winmd` files are already
present it prints a short "skipping download" message instead of
hitting the network again.

To bump a version: update the corresponding `PackageSpec` entry in
`tools/fetch-winui-metadata/main.zig` together with its `expected_sha256`
(recompute the sha256 of the new `.nupkg`, e.g. via `Get-FileHash` /
`sha256sum`), then rerun the step.
