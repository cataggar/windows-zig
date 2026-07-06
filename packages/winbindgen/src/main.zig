//! `winbindgen` CLI — prints the generated Zig source for one namespace
//! to stdout, picking the right `.winmd` by namespace prefix:
//!
//!   * `Windows.Win32.*`  → `Windows.Win32.winmd`
//!   * `Windows.Wdk.*`    → `Windows.Wdk.winmd`
//!   * `Microsoft.UI.Xaml.*` → `Microsoft.UI.Xaml.winmd`
//!   * `Microsoft.UI.Text.*` → `Microsoft.UI.Text.winmd`
//!   * `Microsoft.UI.*`   → `Microsoft.UI.winmd`
//!   * everything else    → `Windows.winmd` (WinRT)
//!
//! Usage:
//!     winbindgen [--arch=x86|x64|arm64] <namespace>
//!     winbindgen bundle --outdir <dir> [--arch=x86|x64|arm64] [--imports=relative|module] [--closure=explicit|transitive] <namespace>...
//!     winbindgen reactor-bindings --outdir <dir>
//!     winbindgen --list
//!
//! `--list` prints every distinct namespace across the committed
//! metadata plus any locally fetched WinUI metadata present under
//! `vendor/winmd/`, one per line. Otherwise the single positional
//! argument is the namespace to emit via `winbindgen.emitNamespace`,
//! and its output is written to stdout. `--arch` picks which
//! `SupportedArchitectureAttribute`-gated overloads to emit; default
//! is `x64`.
//!
//! The metadata files are baked in via `@embedFile` — this is still a
//! driver over `emitNamespace` rather than a full bindgen pipeline.
//! Accepting `--winmd` / `--out` paths and a filter manifest will land
//! in later slices as they start to matter.

const std = @import("std");
const reactor_codegen = @import("reactor-codegen");
const winbindgen = @import("winbindgen");
const winmd = @import("winmd");

const winrt_bytes = @embedFile("Windows.winmd");
const win32_bytes = @embedFile("Windows.Win32.winmd");
const wdk_bytes = @embedFile("Windows.Wdk.winmd");

const winui_xaml_path = "vendor/winmd/Microsoft.UI.Xaml.winmd";
const winui_text_path = "vendor/winmd/Microsoft.UI.Text.winmd";
const winui_ui_path = "vendor/winmd/Microsoft.UI.winmd";

const MetadataSource = enum {
    winrt,
    win32,
    wdk,
    winui_xaml,
    winui_text,
    winui_ui,
};

const metadata_sources = [_]MetadataSource{
    .winrt,
    .win32,
    .wdk,
    .winui_xaml,
    .winui_text,
    .winui_ui,
};
const MetadataSourceCount = metadata_sources.len;

fn namespaceMatchesPrefix(namespace: []const u8, prefix: []const u8) bool {
    return std.mem.eql(u8, namespace, prefix) or
        (namespace.len > prefix.len and
            std.mem.startsWith(u8, namespace, prefix) and
            namespace[prefix.len] == '.');
}

fn selectMetadataSource(namespace: []const u8) MetadataSource {
    if (namespaceMatchesPrefix(namespace, "Windows.Win32")) return .win32;
    if (namespaceMatchesPrefix(namespace, "Windows.Wdk")) return .wdk;
    if (namespaceMatchesPrefix(namespace, "Microsoft.UI.Xaml")) return .winui_xaml;
    if (namespaceMatchesPrefix(namespace, "Microsoft.UI.Text")) return .winui_text;
    if (namespaceMatchesPrefix(namespace, "Microsoft.UI")) return .winui_ui;
    return .winrt;
}

fn metadataDisplayName(source: MetadataSource) []const u8 {
    return switch (source) {
        .winrt => "Windows.winmd",
        .win32 => "Windows.Win32.winmd",
        .wdk => "Windows.Wdk.winmd",
        .winui_xaml => "Microsoft.UI.Xaml.winmd",
        .winui_text => "Microsoft.UI.Text.winmd",
        .winui_ui => "Microsoft.UI.winmd",
    };
}

fn metadataPath(source: MetadataSource) ?[]const u8 {
    return switch (source) {
        .winui_xaml => winui_xaml_path,
        .winui_text => winui_text_path,
        .winui_ui => winui_ui_path,
        else => null,
    };
}

fn isFetchedMetadata(source: MetadataSource) bool {
    return switch (source) {
        .winui_xaml, .winui_text, .winui_ui => true,
        else => false,
    };
}

fn loadMetadataBytes(
    arena: std.mem.Allocator,
    io: std.Io,
    source: MetadataSource,
) ![]const u8 {
    return switch (source) {
        .winrt => winrt_bytes,
        .win32 => win32_bytes,
        .wdk => wdk_bytes,
        .winui_xaml, .winui_text, .winui_ui => blk: {
            const path = metadataPath(source).?;
            break :blk try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);
        },
    };
}

fn loadOptionalMetadataBytes(
    arena: std.mem.Allocator,
    io: std.Io,
    source: MetadataSource,
) !?[]const u8 {
    if (!isFetchedMetadata(source)) return try loadMetadataBytes(arena, io, source);
    return loadMetadataBytes(arena, io, source) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
}

fn writeMetadataLoadError(stderr: *std.Io.Writer, source: MetadataSource, err: anyerror) !void {
    if (err == error.FileNotFound and isFetchedMetadata(source)) {
        try stderr.print(
            "missing {s}; run `zig build fetch-winui-metadata` to stage WinUI3 metadata under vendor/winmd/\n",
            .{metadataPath(source).?},
        );
        return;
    }
    if (metadataPath(source)) |path| {
        try stderr.print("failed to load {s} ({s}): {}\n", .{ metadataDisplayName(source), path, err });
        return;
    }
    try stderr.print("failed to load {s}: {}\n", .{ metadataDisplayName(source), err });
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        const arena = init.arena.allocator();
        for (metadata_sources) |source| {
            const maybe_bytes = loadOptionalMetadataBytes(arena, io, source) catch |err| {
                try writeMetadataLoadError(stderr, source, err);
                try stderr.flush();
                std.process.exit(1);
            };
            const bytes_src = maybe_bytes orelse continue;
            var file = try winmd.parse(bytes_src);
            const names = try winmd.listNamespaces(arena, &file);
            for (names) |n| try stdout.print("{s}\n", .{n});
        }
        try stdout.flush();
        return;
    }

    // `bundle --outdir <dir> [--arch=...] [--imports=relative|module] [--closure=explicit|transitive] ns1 ns2 ...`
    // emits a batch of namespaces as a coordinated bundle, auto-routing
    // cross-namespace closed-generic instantiations to their home
    // namespace. Writes `<outdir>/<ns>.zig` for each input plus a
    // generated `win_bundle.zig` facade root and dependency manifest.
    //
    // Inputs are grouped by metadata file before emission; closed-generic
    // routing happens within each metadata group.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "bundle")) {
        try runBundle(
            init.arena.allocator(),
            gpa,
            io,
            args[2..],
            stderr,
        );
        return;
    }

    // `reactor-bindings --outdir <dir>` emits the manifest-driven
    // WinUI reactor glue that sits alongside the committed WinUI
    // snapshot. Today that includes `generated_set_prop.zig`,
    // `generated_attach_event.zig`, and `generated_attached_props.zig`.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "reactor-bindings")) {
        try runReactorBindings(
            init.arena.allocator(),
            gpa,
            io,
            args[2..],
            stderr,
        );
        return;
    }

    // `--emit-mod <dir>` scans <dir> for sibling `*.structs.zig` and
    // `*.index.zig` generated files and prints a `mod.zig` to stdout
    // that re-exports them by namespace. This retires the hand-edited
    // `generated_structs` block in `win-sys/src/project.zig` — the
    // aggregate file is the single thing `project.zig` imports.
    if (args.len == 3 and std.mem.eql(u8, args[1], "--emit-mod")) {
        var buf: std.Io.Writer.Allocating = .init(gpa);
        defer buf.deinit();
        try emitMod(&buf.writer, init.arena.allocator(), io, args[2]);
        try stdout.writeAll(buf.written());
        try stdout.flush();
        return;
    }

    // Parse `--arch=...` optional flag; the remaining positional must
    // be the namespace. Default to x64 so existing callers don't have
    // to change.
    var arch: winbindgen.Arch = .x64;
    var index_only = false;
    var structs_only = false;
    var closure_only = false;
    var ns_closure_only = false;
    var namespace_arg: ?[]const u8 = null;
    var seed_args = try std.ArrayList([]const u8).initCapacity(init.arena.allocator(), 0);
    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const a = args[i];
            if (std.mem.startsWith(u8, a, "--arch=")) {
                const v = a["--arch=".len..];
                if (std.mem.eql(u8, v, "x86")) {
                    arch = .x86;
                } else if (std.mem.eql(u8, v, "x64")) {
                    arch = .x64;
                } else if (std.mem.eql(u8, v, "arm64")) {
                    arch = .arm64;
                } else {
                    try stderr.print("unknown --arch value: {s}\n", .{v});
                    try stderr.flush();
                    std.process.exit(2);
                }
            } else if (std.mem.startsWith(u8, a, "--seed=")) {
                try seed_args.append(init.arena.allocator(), a["--seed=".len..]);
            } else if (std.mem.eql(u8, a, "--index")) {
                index_only = true;
            } else if (std.mem.eql(u8, a, "--structs")) {
                structs_only = true;
            } else if (std.mem.eql(u8, a, "--namespace-closure")) {
                ns_closure_only = true;
            } else if (std.mem.eql(u8, a, "--structs-closure")) {
                closure_only = true;
            } else if (namespace_arg == null) {
                namespace_arg = a;
            } else {
                try stderr.writeAll(
                    \\usage: winbindgen [--arch=x86|x64|arm64] [--seed=<open_name>,<arg>,...] <namespace>
                    \\       winbindgen --list
                    \\
                );
                try stderr.flush();
                std.process.exit(2);
            }
        }
    }

    const namespace = namespace_arg orelse {
        try stderr.writeAll(
            \\usage: winbindgen [--arch=x86|x64|arm64] [--index|--structs|--structs-closure] <namespace>
            \\       winbindgen --list
            \\
        );
        try stderr.flush();
        std.process.exit(2);
    };

    // Keep the full emitted source in memory first so an error mid-emit
    // doesn't leave partial output on stdout.
    var buf: std.Io.Writer.Allocating = .init(gpa);
    defer buf.deinit();

    const source = selectMetadataSource(namespace);
    const bytes = loadMetadataBytes(init.arena.allocator(), io, source) catch |err| {
        try writeMetadataLoadError(stderr, source, err);
        try stderr.flush();
        std.process.exit(1);
    };
    var file = try winmd.parse(bytes);
    if (index_only) {
        // `--index` emits a standalone `.zig` fragment: a header that
        // pulls in `std` (required for `std.static_string_map`) plus
        // the `pub const method_def_by_name = ...` entry written by
        // `emitMethodIndex`. This is the exact shape Phase 4's
        // `project()` helper `@import`s to perform O(1) method lookups
        // without scanning winmd inside the comptime VM.
        try buf.writer.writeAll("const std = @import(\"std\");\n\n");
        try winbindgen.emitMethodIndex(&buf.writer, init.arena.allocator(), &file, namespace, arch);
    } else if (structs_only) {
        // `--structs` emits a standalone `<ns>.structs.zig` sidecar
        // that can be `@import`ed into a consumer module; header
        // pulls in `win-core` aliases and sibling struct sidecars
        // for any cross-namespace TypeRefs encountered.
        try winbindgen.emitStructsFile(&buf.writer, init.arena.allocator(), &file, namespace, arch);
    } else if (closure_only) {
        // `--structs-closure` prints (one per line, sorted) every
        // namespace whose `.structs.zig` sidecar must also exist for
        // `<namespace>.structs.zig` to compile — i.e. the BFS of the
        // cross-namespace TypeRef graph rooted at `<namespace>`. Lets
        // driver scripts skip the manual "target + transitive" dance.
        const closure = try winbindgen.collectStructsClosure(
            init.arena.allocator(),
            &file,
            namespace,
            arch,
        );
        for (closure) |ns| try buf.writer.print("{s}\n", .{ns});
    } else if (ns_closure_only) {
        // `--namespace-closure` prints (one per line, sorted) every
        // namespace transitively needed for `<namespace>.zig` to
        // compile — walks the full emitter path and follows cross-ns
        // `@import` references. Includes the root namespace itself.
        const closure = try winbindgen.collectNamespaceClosure(
            init.arena.allocator(),
            &file,
            &.{namespace},
            arch,
        );
        for (closure) |ns| try buf.writer.print("{s}\n", .{ns});
    } else {
        // Parse --seed args into a GenericInstSet for emitNamespaceEx.
        // Format: --seed=<open_name>,<arg>,... where <open_name> includes
        // backtick arity (e.g. IVectorView`1) and <arg> is a primitive
        // name (string, i32, object, etc.).
        var seeds: winbindgen.GenericInstSet = .empty;
        const al = init.arena.allocator();
        for (seed_args.items) |seed_str| {
            const seed = winbindgen.parseSeed(al, namespace, seed_str) catch |err| {
                try stderr.print("bad --seed value '{s}': {}\n", .{ seed_str, err });
                try stderr.flush();
                std.process.exit(2);
            };
            try seeds.put(al, seed.key, seed.tn);
        }
        const extra: ?*const winbindgen.GenericInstSet = if (seeds.count() > 0) &seeds else null;
        try winbindgen.emitNamespaceEx(&buf.writer, init.arena.allocator(), &file, namespace, arch, extra);
    }

    try stdout.writeAll(buf.written());
    try stdout.flush();
}

/// Scan `dir` for `*.structs.zig` and `*.index.zig` files and emit a
/// `mod.zig` re-exporting them grouped by flavor. Each file name is
/// expected to be `<namespace>.<flavor>.zig` where `<flavor>` is
/// `structs` or `index`. Output is sorted for determinism.
fn emitMod(
    writer: *std.Io.Writer,
    arena: std.mem.Allocator,
    io: std.Io,
    dir_path: []const u8,
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var structs = try std.ArrayList([]const u8).initCapacity(arena, 0);
    var indexes = try std.ArrayList([]const u8).initCapacity(arena, 0);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (std.mem.endsWith(u8, name, ".structs.zig")) {
            const ns = name[0 .. name.len - ".structs.zig".len];
            if (ns.len == 0) continue;
            try structs.append(arena, try arena.dupe(u8, ns));
        } else if (std.mem.endsWith(u8, name, ".index.zig")) {
            const ns = name[0 .. name.len - ".index.zig".len];
            if (ns.len == 0) continue;
            try indexes.append(arena, try arena.dupe(u8, ns));
        }
    }

    std.mem.sort([]const u8, structs.items, {}, stringLessThan);
    std.mem.sort([]const u8, indexes.items, {}, stringLessThan);

    try writer.writeAll(
        \\//! @generated — do not edit. Regenerate with
        \\//! `zig build bindings` or `winbindgen --emit-mod <dir>`.
        \\//!
        \\//! Aggregate re-export of every sibling `<ns>.structs.zig`
        \\//! and `<ns>.index.zig` file, grouped by flavor. Consumers
        \\//! reach into these via `@field(mod.structs, "<ns>")` so
        \\//! `win-sys/src/project.zig` no longer has to list every
        \\//! namespace by hand.
        \\
        \\pub const structs = struct {
        \\
    );
    for (structs.items) |ns| {
        try writer.print(
            "    pub const @\"{s}\" = @import(\"{s}.structs.zig\");\n",
            .{ ns, ns },
        );
    }
    try writer.writeAll(
        \\};
        \\
        \\pub const index = struct {
        \\
    );
    for (indexes.items) |ns| {
        try writer.print(
            "    pub const @\"{s}\" = @import(\"{s}.index.zig\");\n",
            .{ ns, ns },
        );
    }
    try writer.writeAll("};\n");
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

const BundleClosureMode = enum {
    explicit,
    transitive,
};

fn loadParsedMetadata(
    metadata_cache: *[MetadataSourceCount]?winmd.File,
    arena: std.mem.Allocator,
    io: std.Io,
    source: MetadataSource,
) !*const winmd.File {
    const index = @intFromEnum(source);
    if (metadata_cache[index] == null) {
        const bytes = try loadMetadataBytes(arena, io, source);
        metadata_cache[index] = try winmd.parse(bytes);
    }
    return &metadata_cache[index].?;
}

fn collectTransitiveBundleNamespaces(
    arena: std.mem.Allocator,
    io: std.Io,
    roots: []const []const u8,
    arch: winbindgen.Arch,
) ![][]const u8 {
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    var queue = try std.ArrayList([]const u8).initCapacity(arena, roots.len);
    for (roots) |root| {
        if (visited.contains(root)) continue;
        try visited.put(arena, root, {});
        try queue.append(arena, root);
    }

    var metadata_cache: [MetadataSourceCount]?winmd.File = [_]?winmd.File{null} ** MetadataSourceCount;

    var frontier_start: usize = 0;
    while (frontier_start < queue.items.len) {
        const frontier_end = queue.items.len;
        var groups: [MetadataSourceCount]std.ArrayListUnmanaged([]const u8) =
            [_]std.ArrayListUnmanaged([]const u8){.empty} ** MetadataSourceCount;

        for (queue.items[frontier_start..frontier_end]) |ns| {
            const source = selectMetadataSource(ns);
            try groups[@intFromEnum(source)].append(arena, ns);
        }
        frontier_start = frontier_end;

        for (metadata_sources) |source| {
            const group_ns = groups[@intFromEnum(source)].items;
            if (group_ns.len == 0) continue;

            const file = try loadParsedMetadata(&metadata_cache, arena, io, source);
            const closure = try winbindgen.collectNamespaceClosure(
                arena,
                file,
                group_ns,
                arch,
            );
            for (closure) |ns| {
                if (visited.contains(ns)) continue;
                try visited.put(arena, ns, {});
                try queue.append(arena, ns);
            }
        }
    }

    const result = try arena.dupe([]const u8, queue.items);
    std.mem.sort([]const u8, result, {}, stringLessThan);
    return result;
}

/// Handle the `bundle --outdir <dir> [--arch=...] [--imports=relative|module] [--closure=explicit|transitive] ns1 ns2 ...` subcommand.
/// Calls `winbindgen.emitBundle` to emit every input namespace in a single
/// coordinated pass (cross-namespace closed generics auto-route to their
/// home namespace), then writes `<outdir>/<ns>.zig` for each result plus
/// the generated `win_bundle.zig` facade root and dependency manifest.
fn runBundle(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stderr: *std.Io.Writer,
) !void {
    var arch: winbindgen.Arch = .x64;
    var import_style: winbindgen.ImportStyle = .relative;
    var closure_mode: BundleClosureMode = .explicit;
    var outdir: ?[]const u8 = null;
    var namespaces = try std.ArrayList([]const u8).initCapacity(arena, 0);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.startsWith(u8, a, "--arch=")) {
            const v = a["--arch=".len..];
            if (std.mem.eql(u8, v, "x86")) {
                arch = .x86;
            } else if (std.mem.eql(u8, v, "x64")) {
                arch = .x64;
            } else if (std.mem.eql(u8, v, "arm64")) {
                arch = .arm64;
            } else {
                try stderr.print("unknown --arch value: {s}\n", .{v});
                try stderr.flush();
                std.process.exit(2);
            }
        } else if (std.mem.startsWith(u8, a, "--imports=")) {
            const v = a["--imports=".len..];
            if (std.mem.eql(u8, v, "relative")) {
                import_style = .relative;
            } else if (std.mem.eql(u8, v, "module")) {
                import_style = .module;
            } else {
                try stderr.print("unknown --imports value: {s}\n", .{v});
                try stderr.flush();
                std.process.exit(2);
            }
        } else if (std.mem.startsWith(u8, a, "--closure=")) {
            const v = a["--closure=".len..];
            if (std.mem.eql(u8, v, "explicit")) {
                closure_mode = .explicit;
            } else if (std.mem.eql(u8, v, "transitive")) {
                closure_mode = .transitive;
            } else {
                try stderr.print("unknown --closure value: {s}\n", .{v});
                try stderr.flush();
                std.process.exit(2);
            }
        } else if (std.mem.startsWith(u8, a, "--outdir=")) {
            outdir = a["--outdir=".len..];
        } else if (std.mem.eql(u8, a, "--outdir")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("--outdir requires a path argument\n");
                try stderr.flush();
                std.process.exit(2);
            }
            outdir = args[i];
        } else {
            try namespaces.append(arena, a);
        }
    }

    const dir_path = outdir orelse {
        try stderr.writeAll(
            \\usage: winbindgen bundle --outdir <dir> [--arch=x86|x64|arm64] [--imports=relative|module] [--closure=explicit|transitive] ns1 ns2 ...
            \\
        );
        try stderr.flush();
        std.process.exit(2);
    };

    if (namespaces.items.len == 0) {
        try stderr.writeAll("bundle: need at least one namespace\n");
        try stderr.flush();
        std.process.exit(2);
    }

    const bundle_namespaces = switch (closure_mode) {
        .explicit => namespaces.items,
        .transitive => try collectTransitiveBundleNamespaces(arena, io, namespaces.items, arch),
    };

    // Group namespaces by which winmd file they resolve to; cross-ns
    // generic routing happens only within the same winmd. Phase 4b's
    // WinRT-only routing is a natural fit for this grouping because the
    // Windows.winmd group is where all closed generics live.
    var groups: [MetadataSourceCount]std.ArrayListUnmanaged([]const u8) =
        [_]std.ArrayListUnmanaged([]const u8){.empty} ** MetadataSourceCount;
    for (bundle_namespaces) |ns| {
        const source = selectMetadataSource(ns);
        try groups[@intFromEnum(source)].append(arena, ns);
    }

    var dir = try std.Io.Dir.cwd().createDirPathOpen(io, dir_path, .{});
    defer dir.close(io);

    var all_emission = winbindgen.BundleEmission{
        .namespaces = .empty,
        .dependencies = .empty,
        .facade = "",
    };

    for (metadata_sources) |source| {
        const group_ns = groups[@intFromEnum(source)].items;
        if (group_ns.len == 0) continue;
        const group_bytes = loadMetadataBytes(arena, io, source) catch |err| {
            try writeMetadataLoadError(stderr, source, err);
            try stderr.flush();
            std.process.exit(1);
        };

        var file = try winmd.parse(group_bytes);
        const emission = try winbindgen.emitBundleWithImports(arena, &file, group_ns, arch, import_style);

        for (group_ns) |ns| {
            const bytes = emission.get(ns) orelse continue;
            const file_name = try std.fmt.allocPrint(arena, "{s}.zig", .{ns});
            {
                var out_file = try dir.createFile(io, file_name, .{});
                defer out_file.close(io);

                var out_buf: [4096]u8 = undefined;
                var out_writer = out_file.writer(io, &out_buf);
                try out_writer.interface.writeAll(bytes);
                try out_writer.interface.flush();
            }

            try all_emission.namespaces.put(arena, ns, bytes);
            try all_emission.dependencies.put(arena, ns, emission.getDependencies(ns) orelse &.{});
        }
    }

    {
        var out_file = try dir.createFile(io, winbindgen.BundleFacadeFileName, .{});
        defer out_file.close(io);

        var out_buf: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buf);
        try winbindgen.emitBundleFacadeWithImports(&out_writer.interface, import_style);
        try out_writer.interface.flush();
    }

    {
        var out_file = try dir.createFile(io, winbindgen.BundleDependenciesFileName, .{});
        defer out_file.close(io);

        var out_buf: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buf);
        try winbindgen.emitBundleDependencyManifest(&out_writer.interface, arena, all_emission);
        try out_writer.interface.flush();
    }

    // Suppress-unused-warning; gpa currently only needed for future
    // large-file buffers.
    _ = gpa;
}

fn runReactorBindings(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stderr: *std.Io.Writer,
) !void {
    var outdir: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.startsWith(u8, a, "--outdir=")) {
            outdir = a["--outdir=".len..];
        } else if (std.mem.eql(u8, a, "--outdir")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("--outdir requires a path argument\n");
                try stderr.flush();
                std.process.exit(2);
            }
            outdir = args[i];
        } else {
            try stderr.writeAll(
                \\usage: winbindgen reactor-bindings --outdir <dir>
                \\
            );
            try stderr.flush();
            std.process.exit(2);
        }
    }

    const dir_path = outdir orelse {
        try stderr.writeAll(
            \\usage: winbindgen reactor-bindings --outdir <dir>
            \\
        );
        try stderr.flush();
        std.process.exit(2);
    };

    const bytes = loadMetadataBytes(arena, io, .winui_xaml) catch |err| {
        try writeMetadataLoadError(stderr, .winui_xaml, err);
        try stderr.flush();
        std.process.exit(1);
    };
    var file = try winmd.parse(bytes);

    var dir = try std.Io.Dir.cwd().createDirPathOpen(io, dir_path, .{});
    defer dir.close(io);

    {
        var out_file = try dir.createFile(io, reactor_codegen.SetPropFileName, .{});
        defer out_file.close(io);

        var out_buf: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buf);
        try reactor_codegen.emitSetPropFromManifest(&out_writer.interface, gpa, &file);
        try out_writer.interface.flush();
    }

    {
        var out_file = try dir.createFile(io, reactor_codegen.AttachedPropsFileName, .{});
        defer out_file.close(io);

        var out_buf: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buf);
        try reactor_codegen.emitAttachedPropsFromManifest(&out_writer.interface, gpa);
        try out_writer.interface.flush();
    }

    {
        var out_file = try dir.createFile(io, reactor_codegen.AttachEventFileName, .{});
        defer out_file.close(io);

        var out_buf: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buf);
        try reactor_codegen.emitAttachEventFromManifest(&out_writer.interface, gpa, &file);
        try out_writer.interface.flush();
    }
}
