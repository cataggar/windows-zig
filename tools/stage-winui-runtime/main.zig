//! Stages the framework-dependent Windows App Runtime bootstrap assets
//! (`Microsoft.WindowsAppRuntime.Bootstrap.dll` + `resources.pri`) into a
//! destination directory.
//!
//! This intentionally mirrors the sibling `windows-rs` checkout's
//! `windows-reactor-setup::as_framework_dependent()` layout so the Zig
//! hello-window spike can run directly from `zig-out/bin/` without
//! bundling the full self-contained runtime.

const std = @import("std");

const bootstrap_dll_name = "Microsoft.WindowsAppRuntime.Bootstrap.dll";
const resources_pri_name = "resources.pri";

const Options = struct {
    dest_dir: []const u8,
    arch: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(arena);
    const options = try parseArgs(args, stderr);

    const bootstrap_src = try locateBootstrapDll(io, arena, options.arch) orelse {
        try stderr.print(
            "could not locate {s}; set WINDOWS_APP_RUNTIME_BOOTSTRAP_DLL or place a sibling windows-rs checkout next to this repo\n",
            .{bootstrap_dll_name},
        );
        try stderr.flush();
        return error.MissingBootstrapDll;
    };
    const resources_src = try locateResourcesPri(io, arena) orelse {
        try stderr.print(
            "could not locate {s}; set WINDOWS_APP_RUNTIME_RESOURCES_PRI or place a sibling windows-rs checkout next to this repo\n",
            .{resources_pri_name},
        );
        try stderr.flush();
        return error.MissingResourcesPri;
    };

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, options.dest_dir);

    const bootstrap_dest = try std.fs.path.join(arena, &.{ options.dest_dir, bootstrap_dll_name });
    const resources_dest = try std.fs.path.join(arena, &.{ options.dest_dir, resources_pri_name });

    try cwd.copyFile(bootstrap_src, cwd, bootstrap_dest, io, .{ .make_path = true });
    try cwd.copyFile(resources_src, cwd, resources_dest, io, .{ .make_path = true });

    try stderr.print("staged {s} -> {s}\n", .{ bootstrap_src, bootstrap_dest });
    try stderr.print("staged {s} -> {s}\n", .{ resources_src, resources_dest });
    try stderr.flush();
}

fn parseArgs(args: []const []const u8, stderr: *std.Io.Writer) !Options {
    var dest_dir: ?[]const u8 = null;
    var arch: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--dest-dir")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("--dest-dir requires a path argument\n");
                try stderr.flush();
                std.process.exit(2);
            }
            dest_dir = args[i];
        } else if (std.mem.eql(u8, args[i], "--arch")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("--arch requires a value (x86|x64|arm64)\n");
                try stderr.flush();
                std.process.exit(2);
            }
            arch = args[i];
        } else {
            try stderr.print("unknown argument: {s}\n", .{args[i]});
            try stderr.flush();
            std.process.exit(2);
        }
    }

    return .{
        .dest_dir = dest_dir orelse {
            try stderr.writeAll("--dest-dir is required\n");
            try stderr.flush();
            std.process.exit(2);
        },
        .arch = arch orelse {
            try stderr.writeAll("--arch is required\n");
            try stderr.flush();
            std.process.exit(2);
        },
    };
}

fn locateBootstrapDll(io: std.Io, arena: std.mem.Allocator, arch: []const u8) !?[]const u8 {
    if (try envFileIfExists(io, arena, "WINDOWS_APP_RUNTIME_BOOTSTRAP_DLL")) |path| return path;

    const sibling = try std.fs.path.resolve(arena, &.{
        "..",
        "windows-rs",
        "crates",
        "libs",
        "reactor-setup",
        "bootstrap",
        arch,
        bootstrap_dll_name,
    });
    if (exists(io, sibling)) return sibling;

    if (std.mem.eql(u8, arch, "x64")) {
        const wsl_settings = try std.fs.path.resolve(arena, &.{
            "C:\\Program Files\\WSL\\wslsettings",
            bootstrap_dll_name,
        });
        if (exists(io, wsl_settings)) return wsl_settings;
    }

    return null;
}

fn locateResourcesPri(io: std.Io, arena: std.mem.Allocator) !?[]const u8 {
    if (try envFileIfExists(io, arena, "WINDOWS_APP_RUNTIME_RESOURCES_PRI")) |path| return path;

    const sibling = try std.fs.path.resolve(arena, &.{
        "..",
        "windows-rs",
        "crates",
        "libs",
        "reactor-setup",
        "assets",
        resources_pri_name,
    });
    if (exists(io, sibling)) return sibling;

    return null;
}

fn envFileIfExists(io: std.Io, arena: std.mem.Allocator, key: []const u8) !?[]const u8 {
    const environ: std.process.Environ = .{ .block = .global };
    const raw = environ.getAlloc(arena, key) catch |err| switch (err) {
        error.EnvironmentVariableMissing => return null,
        else => return err,
    };
    const abs = try std.fs.path.resolve(arena, &.{raw});
    if (exists(io, abs)) return abs;
    return null;
}

fn exists(io: std.Io, abs_path: []const u8) bool {
    std.Io.Dir.cwd().access(io, abs_path, .{}) catch return false;
    return true;
}
