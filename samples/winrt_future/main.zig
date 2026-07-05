const std = @import("std");
const win = @import("win");
const future = @import("win-future");
const Foundation = @import("Windows.Foundation");
const Storage = @import("Windows.Storage");
const Streams = @import("Windows.Storage.Streams");

const core = win.core;
const Async = future.Async;

const TempFile = struct {
    relative_name: []const u8,
    absolute_path: [:0]u8,
    absolute_path_utf16: []u16,
};

const WhenState = struct {
    fired: u32 = 0,
};

const ProgressState = struct {
    callbacks: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    last_value: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

fn createTempFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    relative_name: []const u8,
    contents: []const u8,
) !TempFile {
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{
        .sub_path = relative_name,
        .data = contents,
    });

    const absolute_path = try cwd.realPathFileAlloc(io, relative_name, allocator);
    errdefer allocator.free(absolute_path);

    const absolute_path_utf16 = try std.unicode.utf8ToUtf16LeAlloc(allocator, absolute_path);
    errdefer allocator.free(absolute_path_utf16);

    return .{
        .relative_name = relative_name,
        .absolute_path = absolute_path,
        .absolute_path_utf16 = absolute_path_utf16,
    };
}

fn deinitTempFile(allocator: std.mem.Allocator, temp_file: *TempFile) void {
    allocator.free(temp_file.absolute_path_utf16);
    allocator.free(temp_file.absolute_path);
}

fn deleteTempFile(io: std.Io, temp_file: TempFile) void {
    std.Io.Dir.cwd().deleteFile(io, temp_file.relative_name) catch {};
}

fn releaseRuntimeClass(ptr: anytype) void {
    const inspectable: core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(ptr)),
    };
    inspectable.deinit();
}

fn storageFileTypeAlloc(allocator: std.mem.Allocator, file: *Storage.StorageFile) ![]u8 {
    const iface: *const Storage.IStorageFile = @ptrCast(@alignCast(file));
    var ext_raw: core.HSTRING = null;
    try core.hresult.ok(iface.get_FileType(&ext_raw));
    var ext = core.Hstring.fromRaw(ext_raw);
    defer ext.deinit();
    return std.unicode.utf16LeToUtf8Alloc(allocator, ext.slice());
}

fn onCopyProgress(context: ?*anyopaque, value: u32) void {
    const state: *ProgressState = @ptrCast(@alignCast(context.?));
    _ = state.callbacks.fetchAdd(1, .acq_rel);
    state.last_value.store(value, .release);
}

fn runCopyWithProgressSample(
    allocator: std.mem.Allocator,
    progress_state: *ProgressState,
) !u32 {
    const payload_len = 256 * 1024;
    const payload = try allocator.alloc(u8, payload_len);
    defer allocator.free(payload);
    @memset(payload, 0x5A);

    const sink_ra = try core.activateInstance(
        Streams.IRandomAccessStream,
        &Streams.InMemoryRandomAccessStream.NAME_W,
    );
    defer _ = sink_ra.Release();

    const writer_iface = try core.activateInstance(
        Streams.IDataWriter,
        &Streams.DataWriter.NAME_W,
    );
    defer _ = writer_iface.Release();
    try core.hresult.ok(writer_iface.WriteBytes(@intCast(payload.len), payload.ptr));

    var payload_buffer: *Streams.IBuffer = undefined;
    try core.hresult.ok(writer_iface.DetachBuffer(&payload_buffer));
    defer _ = payload_buffer.Release();

    var sink_output: *Streams.IOutputStream = undefined;
    try core.hresult.ok(sink_ra.GetOutputStreamAt(0, &sink_output));
    defer _ = sink_output.Release();

    var write_op: *Foundation.IAsyncOperationWithProgress__G2__u32__u32 = undefined;
    try core.hresult.ok(sink_output.WriteAsync(payload_buffer, &write_op));
    defer releaseRuntimeClass(write_op);

    const written_bytes = try Async.waitResultWithProgress(
        u32,
        u32,
        allocator,
        write_op,
        &onCopyProgress,
        @ptrCast(progress_state),
    );

    var sink_size: u64 = 0;
    try core.hresult.ok(sink_ra.get_Size(&sink_size));
    const expected_len: u32 = @intCast(payload.len);
    if (written_bytes != expected_len or sink_size != expected_len) {
        return error.WrittenByteCountMismatch;
    }

    return written_bytes;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    try core.roInitialize(.multi_threaded);
    defer core.winrt.RoUninitialize();

    const allocator = std.heap.page_allocator;

    var left_file = try createTempFile(io, allocator, "winrt-future-left.txt", "left file\n");
    defer deleteTempFile(io, left_file);
    defer deinitTempFile(allocator, &left_file);

    var right_file = try createTempFile(io, allocator, "winrt-future-right.log", "right file\n");
    defer deleteTempFile(io, right_file);
    defer deinitTempFile(allocator, &right_file);

    const statics = try Storage.StorageFile.statics2();
    defer statics.deinit();
    const storage_file_statics: *const Storage.StorageFile.Statics2 =
        @ptrCast(@alignCast(statics.ptr));

    var join_left_op: *Foundation.IAsyncOperation__G1__Windows_Storage_StorageFile = undefined;
    try core.hresult.ok(storage_file_statics.GetFileFromPathAsyncFromUtf16(
        left_file.absolute_path_utf16,
        @ptrCast(&join_left_op),
    ));
    defer releaseRuntimeClass(join_left_op);

    var join_right_op: *Foundation.IAsyncOperation__G1__Windows_Storage_StorageFile = undefined;
    try core.hresult.ok(storage_file_statics.GetFileFromPathAsyncFromUtf16(
        right_file.absolute_path_utf16,
        @ptrCast(&join_right_op),
    ));
    defer releaseRuntimeClass(join_right_op);

    const joined_files = try Async.join(allocator, .{
        Async.operation(*Storage.StorageFile, join_left_op),
        Async.operation(*Storage.StorageFile, join_right_op),
    });
    defer releaseRuntimeClass(joined_files.@"0");
    defer releaseRuntimeClass(joined_files.@"1");

    const left_ext = try storageFileTypeAlloc(allocator, joined_files.@"0");
    defer allocator.free(left_ext);
    const right_ext = try storageFileTypeAlloc(allocator, joined_files.@"1");
    defer allocator.free(right_ext);

    var when_left_op: *Foundation.IAsyncOperation__G1__Windows_Storage_StorageFile = undefined;
    try core.hresult.ok(storage_file_statics.GetFileFromPathAsyncFromUtf16(
        left_file.absolute_path_utf16,
        @ptrCast(&when_left_op),
    ));
    defer releaseRuntimeClass(when_left_op);

    var when_right_op: *Foundation.IAsyncOperation__G1__Windows_Storage_StorageFile = undefined;
    try core.hresult.ok(storage_file_statics.GetFileFromPathAsyncFromUtf16(
        right_file.absolute_path_utf16,
        @ptrCast(&when_right_op),
    ));
    defer releaseRuntimeClass(when_right_op);

    const when_ops = .{
        Async.operation(*Storage.StorageFile, when_left_op),
        Async.operation(*Storage.StorageFile, when_right_op),
    };
    const WhenJoined = Async.JoinResult(@TypeOf(when_ops));
    var when_state: WhenState = .{};

    const WhenCallback = struct {
        fn run(state: *WhenState, files: WhenJoined) void {
            state.fired += 1;
            releaseRuntimeClass(files.@"0");
            releaseRuntimeClass(files.@"1");
        }
    };
    try Async.when(allocator, when_ops, &when_state, WhenCallback.run);

    var progress_state: ProgressState = .{};
    const copied_bytes = try runCopyWithProgressSample(allocator, &progress_state);
    const progress_callbacks = progress_state.callbacks.load(.acquire);
    const last_progress = progress_state.last_value.load(.acquire);
    // `InMemoryRandomAccessStream.WriteAsync` often completes in one shot,
    // so the unit tests remain the source of truth for progress-callback
    // plumbing. If a callback does fire, it must report the final byte count.
    if (progress_callbacks != 0 and last_progress != copied_bytes) {
        return error.ProgressEndedBeforeWriteCompleted;
    }

    std.debug.print("join(): left={s} right={s}\n", .{ left_ext, right_ext });
    std.debug.print("when(): callback fired {d} time(s)\n", .{when_state.fired});
    std.debug.print(
        "write progress: {d} callback(s), last={d}, written={d}\n",
        .{ progress_callbacks, last_progress, copied_bytes },
    );
}
