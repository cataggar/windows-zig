//! Fetches the WinUI3 `.winmd` metadata from the `Microsoft.WindowsAppSDK.WinUI`
//! NuGet package and stages it under `vendor/winmd/`.
//!
//! Unlike `Windows.winmd` / `Windows.Win32.winmd` / `Windows.Wdk.winmd` (which
//! come from the MIT-licensed win32metadata project and are committed to
//! git), the WindowsAppSDK/WinUI NuGet packages ship under Microsoft's
//! proprietary Windows App SDK license. Mirroring how windows-rs itself
//! never commits any `.winmd` to git (its top-level `winmd/` directory is
//! populated out of band), this tool fetches the WinUI metadata on demand
//! instead of vendoring it in source control. See `vendor/winmd/README` and
//! the repo `.gitignore`.
//!
//! Usage:
//!     zig build fetch-winui-metadata
//!   or directly:
//!     fetch-winui-metadata [--out-dir <dir>]
//!
//! The download is verified against a pinned sha256 of the `.nupkg` before
//! extraction, so a compromised mirror/CDN can't silently substitute a
//! different payload. Bump `package_version` and `expected_sha256` together
//! when refreshing.

const std = @import("std");

const package_id = "microsoft.windowsappsdk.winui";
const package_version = "2.2.1";
const package_url = "https://api.nuget.org/v3-flatcontainer/" ++
    package_id ++ "/" ++ package_version ++ "/" ++
    package_id ++ "." ++ package_version ++ ".nupkg";

/// sha256 of the `.nupkg` file itself (not its extracted contents).
const expected_sha256 = "9ce50ddd6f2e2702f05f3575d8565651003e87b55d877fa4bff4369192dc5938";

const WantedFile = struct {
    /// Path inside the .nupkg (zip) archive.
    zip_path: []const u8,
    /// Destination file name under the output directory.
    dest_name: []const u8,
};

const wanted_files = [_]WantedFile{
    .{ .zip_path = "metadata/Microsoft.UI.Xaml.winmd", .dest_name = "Microsoft.UI.Xaml.winmd" },
    .{ .zip_path = "metadata/Microsoft.UI.Text.winmd", .dest_name = "Microsoft.UI.Text.winmd" },
};

const default_out_dir = "vendor/winmd";
const scratch_dir = ".zig-cache/tmp/fetch-winui-metadata";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(arena);

    var out_dir_path: []const u8 = default_out_dir;
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--out-dir")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.writeAll("--out-dir requires a path argument\n");
                    try stderr.flush();
                    std.process.exit(2);
                }
                out_dir_path = args[i];
            } else {
                try stderr.print("unknown argument: {s}\n", .{args[i]});
                try stderr.flush();
                std.process.exit(2);
            }
        }
    }

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, out_dir_path);
    var out_dir = try cwd.openDir(io, out_dir_path, .{});
    defer out_dir.close(io);

    // Stage the download + extraction inside a scratch directory so a
    // failed/partial run never leaves stray files next to the vendored
    // metadata, and so reruns start from a clean slate.
    cwd.deleteTree(io, scratch_dir) catch {};
    try cwd.createDirPath(io, scratch_dir);
    defer cwd.deleteTree(io, scratch_dir) catch {};

    const nupkg_name = "package.nupkg";

    try stderr.print("Downloading {s}\n", .{package_url});
    try stderr.flush();

    {
        var scratch_dir_handle = try cwd.openDir(io, scratch_dir, .{});
        defer scratch_dir_handle.close(io);
        try download(io, gpa, package_url, scratch_dir_handle, nupkg_name);
    }

    const nupkg_path = try std.fs.path.join(arena, &.{ scratch_dir, nupkg_name });

    try stderr.writeAll("Verifying checksum\n");
    try stderr.flush();
    try verifySha256(io, gpa, cwd, nupkg_path, expected_sha256);

    const extract_subdir = "extract";
    const extract_dir_path = try std.fs.path.join(arena, &.{ scratch_dir, extract_subdir });
    try cwd.createDirPath(io, extract_dir_path);

    try stderr.writeAll("Extracting\n");
    try stderr.flush();
    {
        var extract_dir = try cwd.openDir(io, extract_dir_path, .{});
        defer extract_dir.close(io);

        const nupkg_file = try cwd.openFile(io, nupkg_path, .{});
        defer nupkg_file.close(io);
        var read_buffer: [4096]u8 = undefined;
        var file_reader = nupkg_file.reader(io, &read_buffer);
        try std.zip.extract(extract_dir, &file_reader, .{});

        for (wanted_files) |wf| {
            try extract_dir.copyFile(wf.zip_path, out_dir, wf.dest_name, io, .{});
            const st = try out_dir.statFile(io, wf.dest_name, .{});
            try stderr.print("  wrote {s}/{s} ({d} bytes)\n", .{ out_dir_path, wf.dest_name, st.size });
        }
    }

    try stderr.writeAll("Done.\n");
    try stderr.flush();
}

fn download(io: std.Io, gpa: std.mem.Allocator, url: []const u8, dir: std.Io.Dir, dest_path: []const u8) !void {
    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    var file = try dir.createFile(io, dest_path, .{});
    defer file.close(io);

    var file_buffer: [1024 * 16]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &file_writer.interface,
    });
    try file_writer.interface.flush();

    if (result.status != .ok) {
        return error.UnexpectedHttpStatus;
    }
}

fn verifySha256(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, path: []const u8, expected_hex: []const u8) !void {
    const bytes = try dir.readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var actual_hex: [digest.len * 2]u8 = undefined;
    _ = std.fmt.bufPrint(&actual_hex, "{x}", .{digest}) catch unreachable;

    if (!std.mem.eql(u8, &actual_hex, expected_hex)) {
        std.log.err(
            "sha256 mismatch for {s}: expected {s}, got {s}. " ++
                "If you intentionally bumped `package_version`, update `expected_sha256` too.",
            .{ path, expected_hex, actual_hex },
        );
        return error.ChecksumMismatch;
    }
}
