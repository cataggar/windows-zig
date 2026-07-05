const std = @import("std");
const builtin = @import("builtin");
const core = @import("win-core");
const win = @import("win");

const abi = @import("abi.zig");
const interfaces = @import("interfaces.zig");
const buffered_iterator = @import("buffered_iterator.zig");
const stock_map = @import("stock_map.zig");
const stock_vector = @import("stock_vector.zig");

fn makeHstring(text: []const u8) !core.Hstring {
    return core.Hstring.createUtf8(std.testing.allocator, text);
}

fn expectHstringEq(actual: core.Hstring, expected: []const u8) !void {
    var want = try makeHstring(expected);
    defer want.deinit();
    try std.testing.expect(core.Hstring.eql(actual, want));
}

fn runtimeClassName(handle: anytype) !core.Hstring {
    var raw: ?*anyopaque = null;
    try core.hresult.ok(handle.QueryInterface(&core.IID_IInspectable, &raw));
    const inspectable = core.IInspectable.from(raw orelse return error.Pointer);
    defer inspectable.deinit();

    var name_raw: core.HSTRING = null;
    try core.hresult.ok(inspectable.vtbl().GetRuntimeClassName(inspectable.ptr, &name_raw));
    return core.Hstring.fromRaw(name_raw);
}

fn expectRuntimeClassName(handle: anytype, expected: []const u8) !void {
    var name = try runtimeClassName(handle);
    defer name.deinit();
    try expectHstringEq(name, expected);
}

fn takeAndExpectPair(pair_ptr: *?*interfaces.IKeyValuePair(i32, u64), key: i32, value: u64) !void {
    const pair = pair_ptr.* orelse return error.ExpectedPair;
    pair_ptr.* = null;
    defer pair.deinit();

    try std.testing.expectEqual(key, try pair.Key());
    try std.testing.expectEqual(value, try pair.Value());
}

const VectorEventLog = struct {
    len: usize = 0,
    items: [8]Item = undefined,

    const Item = struct {
        change: interfaces.CollectionChange,
        index: u32,
    };

    fn push(self: *VectorEventLog, change: interfaces.CollectionChange, index: u32) void {
        self.items[self.len] = .{ .change = change, .index = index };
        self.len += 1;
    }
};

const MapEventLog = struct {
    len: usize = 0,
    items: [8]Item = undefined,

    const Item = struct {
        change: interfaces.CollectionChange,
        key: ?i32,
    };

    fn push(self: *MapEventLog, change: interfaces.CollectionChange, key: ?i32) void {
        self.items[self.len] = .{ .change = change, .key = key };
        self.len += 1;
    }
};

fn onVectorChanged(
    this: *const interfaces.VectorChangedEventHandler(i32),
    sender: *anyopaque,
    event: *interfaces.IVectorChangedEventArgs,
) callconv(.winapi) core.HRESULT {
    _ = sender;

    const D = core.Delegate(@TypeOf(onVectorChanged), interfaces.VectorChangedEventHandler(i32).IID);
    const ctx_raw = D.userData(@ptrCast(@constCast(this))) orelse return core.hresult.E_POINTER;
    const ctx: *VectorEventLog = @ptrCast(@alignCast(ctx_raw));

    const change = event.CollectionChange() catch return core.hresult.E_FAIL;
    const index = event.Index() catch return core.hresult.E_FAIL;
    ctx.push(change, index);
    return core.hresult.S_OK;
}

fn onMapChanged(
    this: *const interfaces.MapChangedEventHandler(i32, u64),
    sender: *anyopaque,
    event: *anyopaque,
) callconv(.winapi) core.HRESULT {
    _ = sender;

    const D = core.Delegate(@TypeOf(onMapChanged), interfaces.MapChangedEventHandler(i32, u64).IID);
    const ctx_raw = D.userData(@ptrCast(@constCast(this))) orelse return core.hresult.E_POINTER;
    const ctx: *MapEventLog = @ptrCast(@alignCast(ctx_raw));
    const args: *interfaces.IMapChangedEventArgs(i32) = @ptrCast(@alignCast(event));

    const change = args.CollectionChange() catch return core.hresult.E_FAIL;
    const key = args.Key() catch |err| switch (err) {
        error.Bounds => null,
        else => return core.hresult.E_FAIL,
    };
    ctx.push(change, key);
    return core.hresult.S_OK;
}

const ProbeIteratorState = struct {
    values: []const i32,
    next_index: usize = 0,
    current_calls: usize = 0,
    has_current_calls: usize = 0,
    move_next_calls: usize = 0,
    get_many_calls: usize = 0,
};

const ProbeIteratorAuthor = core.MultiInterfaceObject(ProbeIteratorState, .{
    .runtime_class_name = interfaces.IIterator(i32).NAME_W,
}, .{
    core.interfaceSpec(interfaces.IIterator(i32), .{
        .base = undefined,
        .get_Current = probeGetCurrent,
        .get_HasCurrent = probeGetHasCurrent,
        .MoveNext = probeMoveNext,
        .GetMany = probeGetMany,
    }),
});

fn probeGetCurrent(this: *const interfaces.IIterator(i32), result: *i32) callconv(.winapi) core.HRESULT {
    _ = result;
    ProbeIteratorAuthor.stateFrom(interfaces.IIterator(i32), this).current_calls += 1;
    return core.hresult.E_NOTIMPL;
}

fn probeGetHasCurrent(this: *const interfaces.IIterator(i32), result: *core.BOOL) callconv(.winapi) core.HRESULT {
    const state = ProbeIteratorAuthor.stateFrom(interfaces.IIterator(i32), this);
    state.has_current_calls += 1;
    result.* = core.boolToWin32(state.next_index < state.values.len);
    return core.hresult.S_OK;
}

fn probeMoveNext(this: *const interfaces.IIterator(i32), result: *core.BOOL) callconv(.winapi) core.HRESULT {
    const state = ProbeIteratorAuthor.stateFrom(interfaces.IIterator(i32), this);
    state.move_next_calls += 1;
    if (state.next_index < state.values.len) state.next_index += 1;
    result.* = core.boolToWin32(state.next_index < state.values.len);
    return core.hresult.S_OK;
}

fn probeGetMany(this: *const interfaces.IIterator(i32), items_size: u32, items_ptr: [*]i32, result: *u32) callconv(.winapi) core.HRESULT {
    const state = ProbeIteratorAuthor.stateFrom(interfaces.IIterator(i32), this);
    state.get_many_calls += 1;

    if (state.next_index >= state.values.len) {
        result.* = 0;
        return core.hresult.S_OK;
    }

    const items = items_ptr[0..items_size];
    const actual = @min(state.values.len - state.next_index, items.len);
    for (0..actual) |i| items[i] = state.values[state.next_index + i];
    state.next_index += actual;
    result.* = @intCast(actual);
    return core.hresult.S_OK;
}

test "vector supports mutable operations and runtime class names" {
    const allocator = std.testing.allocator;

    const vector = try stock_vector.createVector(i32, allocator, &[_]i32{});
    defer vector.deinit();

    try std.testing.expectError(error.Bounds, vector.GetAt(0));
    try std.testing.expectEqual(@as(u32, 0), try vector.Size());

    try vector.Append(1);
    try vector.Append(2);
    try vector.Append(3);
    try std.testing.expectEqual(@as(u32, 3), try vector.Size());
    try std.testing.expectEqual(@as(i32, 1), try vector.GetAt(0));
    try std.testing.expectEqual(@as(i32, 2), try vector.GetAt(1));
    try std.testing.expectEqual(@as(i32, 3), try vector.GetAt(2));

    try vector.SetAt(1, 20);
    try std.testing.expectEqual(@as(i32, 20), try vector.GetAt(1));

    try vector.InsertAt(1, 10);
    try std.testing.expectEqual(@as(u32, 4), try vector.Size());
    try std.testing.expectEqual(@as(i32, 10), try vector.GetAt(1));

    var index: u32 = 99;
    try std.testing.expect(try vector.IndexOf(20, &index));
    try std.testing.expectEqual(@as(u32, 2), index);
    try std.testing.expect(!(try vector.IndexOf(999, &index)));
    try std.testing.expectEqual(@as(u32, 0), index);

    var many = std.mem.zeroes([5]i32);
    try std.testing.expectEqual(@as(u32, 4), try vector.GetMany(0, many[0..]));
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 10, 20, 3, 0 }, &many);

    const view = try vector.GetView();
    defer view.deinit();
    try vector.Append(99);
    try std.testing.expectEqual(@as(u32, 4), try view.Size());
    try std.testing.expectEqual(@as(u32, 5), try vector.Size());

    const iterable = try vector.cast(interfaces.IIterable(i32));
    defer iterable.deinit();
    const roundtrip = try iterable.cast(interfaces.IVector(i32));
    defer roundtrip.deinit();
    try std.testing.expectEqual(vector, roundtrip);

    var inspectable_raw: ?*anyopaque = null;
    try core.hresult.ok(vector.QueryInterface(&core.IID_IInspectable, &inspectable_raw));
    const inspectable = core.IInspectable.from(inspectable_raw orelse return error.Pointer);
    defer inspectable.deinit();

    var iid_count: u32 = 0;
    var iid_values: ?[*]core.GUID = null;
    try core.hresult.ok(inspectable.vtbl().GetIids(inspectable.ptr, &iid_count, &iid_values));
    defer core.ole32.CoTaskMemFree(iid_values);
    try std.testing.expectEqual(@as(u32, 2), iid_count);
    try std.testing.expect(std.meta.eql(iid_values.?[0], interfaces.IIterable(i32).IID));
    try std.testing.expect(std.meta.eql(iid_values.?[1], interfaces.IVector(i32).IID));

    try expectRuntimeClassName(vector, "Windows.Foundation.Collections.IVector`1<Int32>");
    try expectRuntimeClassName(view, "Windows.Foundation.Collections.IVectorView`1<Int32>");
}

test "vector view and iterator surface mirrors WinRT collection behavior" {
    const allocator = std.testing.allocator;

    const view = try stock_vector.createVectorView(i32, allocator, &[_]i32{ 1, 2, 3 });
    defer view.deinit();

    try std.testing.expectEqual(@as(i32, 1), try view.GetAt(0));
    try std.testing.expectEqual(@as(i32, 2), try view.GetAt(1));
    try std.testing.expectEqual(@as(i32, 3), try view.GetAt(2));
    try std.testing.expectError(error.Bounds, view.GetAt(3));

    var index: u32 = 123;
    try std.testing.expect(try view.IndexOf(2, &index));
    try std.testing.expectEqual(@as(u32, 1), index);
    try std.testing.expect(!(try view.IndexOf(9, &index)));
    try std.testing.expectEqual(@as(u32, 0), index);

    const iter = try view.First();
    defer iter.deinit();

    try std.testing.expectEqual(@as(i32, 1), try iter.Current());
    try std.testing.expect(try iter.HasCurrent());
    try std.testing.expect(try iter.MoveNext());
    try std.testing.expectEqual(@as(i32, 2), try iter.Current());
    try std.testing.expect(try iter.MoveNext());
    try std.testing.expectEqual(@as(i32, 3), try iter.Current());
    try std.testing.expect(!(try iter.MoveNext()));
    try std.testing.expect(!(try iter.HasCurrent()));
    try std.testing.expectError(error.Bounds, iter.Current());

    const iter_many = try view.First();
    defer iter_many.deinit();
    var values = std.mem.zeroes([5]i32);
    try std.testing.expectEqual(@as(u32, 3), try iter_many.GetMany(values[0..]));
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 0, 0 }, &values);
    try std.testing.expectEqual(@as(u32, 0), try iter_many.GetMany(values[0..]));

    try expectRuntimeClassName(view, "Windows.Foundation.Collections.IVectorView`1<Int32>");
}

test "observable vector raises VectorChanged events" {
    const allocator = std.testing.allocator;

    const vector = try stock_vector.createObservableVector(i32, allocator, &[_]i32{ 1, 2, 3 });
    defer vector.deinit();

    var log: VectorEventLog = .{};
    const token = try vector.VectorChanged(allocator, &onVectorChanged, &log);
    defer vector.RemoveVectorChanged(token) catch {};

    try vector.Append(4);
    try vector.SetAt(0, 10);
    try vector.RemoveAt(1);
    try vector.Clear();

    try std.testing.expectEqual(@as(usize, 4), log.len);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemInserted, log.items[0].change);
    try std.testing.expectEqual(@as(u32, 3), log.items[0].index);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemChanged, log.items[1].change);
    try std.testing.expectEqual(@as(u32, 0), log.items[1].index);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemRemoved, log.items[2].change);
    try std.testing.expectEqual(@as(u32, 1), log.items[2].index);
    try std.testing.expectEqual(interfaces.CollectionChange.Reset, log.items[3].change);
    try std.testing.expectEqual(@as(u32, 0), log.items[3].index);

    try vector.RemoveVectorChanged(token);
    try vector.Append(99);
    try std.testing.expectEqual(@as(usize, 4), log.len);

    try expectRuntimeClassName(vector, "Windows.Foundation.Collections.IObservableVector`1<Int32>");
}

test "buffered iterator drains via GetMany without per-element ABI calls" {
    var source: [300]i32 = undefined;
    for (0..source.len) |i| source[i] = @intCast(i);

    const storage = try ProbeIteratorAuthor.create(std.testing.allocator, .{
        .values = source[0..],
    });

    var iter = buffered_iterator.BufferedIterator(i32).init(ProbeIteratorAuthor.as(storage, interfaces.IIterator(i32)));
    defer iter.deinit();

    var index: usize = 0;
    while (try iter.next()) |value| : (index += 1) {
        try std.testing.expectEqual(@as(i32, @intCast(index)), value);
    }

    try std.testing.expectEqual(source.len, index);
    try std.testing.expectEqual(@as(usize, 0), storage.state.current_calls);
    try std.testing.expectEqual(@as(usize, 0), storage.state.has_current_calls);
    try std.testing.expectEqual(@as(usize, 0), storage.state.move_next_calls);
    try std.testing.expectEqual(@as(usize, 4), storage.state.get_many_calls);
}

test "map view exposes lookup iteration and null Split halves" {
    const allocator = std.testing.allocator;

    const entries = [_]abi.Entry(i32, u64){
        .{ .key = 1, .value = 10 },
        .{ .key = 2, .value = 20 },
        .{ .key = 3, .value = 30 },
    };
    const view = try stock_map.createMapView(i32, u64, allocator, &entries);
    defer view.deinit();

    try std.testing.expectEqual(@as(u64, 10), try view.Lookup(1));
    try std.testing.expectEqual(@as(u32, 3), try view.Size());
    try std.testing.expect(try view.HasKey(2));
    try std.testing.expect(!(try view.HasKey(99)));
    try std.testing.expectError(error.Bounds, view.Lookup(99));

    var first_half: ?*interfaces.IMapView(i32, u64) = undefined;
    var second_half: ?*interfaces.IMapView(i32, u64) = undefined;
    try view.Split(&first_half, &second_half);
    try std.testing.expectEqual(@as(?*interfaces.IMapView(i32, u64), null), first_half);
    try std.testing.expectEqual(@as(?*interfaces.IMapView(i32, u64), null), second_half);

    const iter = try view.First();
    defer iter.deinit();
    const first_pair = try iter.Current();
    defer first_pair.deinit();
    try std.testing.expectEqual(@as(i32, 1), try first_pair.Key());
    const iter_many = try view.First();
    defer iter_many.deinit();
    var many = std.mem.zeroes([5]?*interfaces.IKeyValuePair(i32, u64));
    try std.testing.expectEqual(@as(u32, 3), try iter_many.GetMany(many[0..]));
    try takeAndExpectPair(&many[0], 1, 10);
    try takeAndExpectPair(&many[1], 2, 20);
    try takeAndExpectPair(&many[2], 3, 30);
    try std.testing.expectEqual(@as(?*interfaces.IKeyValuePair(i32, u64), null), many[3]);
    try std.testing.expectEqual(@as(?*interfaces.IKeyValuePair(i32, u64), null), many[4]);

    try expectRuntimeClassName(view, "Windows.Foundation.Collections.IMapView`2<Int32, UInt64>");
}

test "map supports mutation snapshots and runtime class names" {
    const allocator = std.testing.allocator;

    const map = try stock_map.createMap(i32, u64, allocator, &[_]abi.Entry(i32, u64){});
    defer map.deinit();

    try std.testing.expect(!(try map.Insert(1, 10)));
    try std.testing.expect(!(try map.Insert(2, 20)));
    try std.testing.expect(!(try map.Insert(3, 30)));
    try std.testing.expectEqual(@as(u32, 3), try map.Size());
    try std.testing.expectEqual(@as(u64, 10), try map.Lookup(1));
    try std.testing.expect(try map.Insert(2, 200));
    try std.testing.expectEqual(@as(u64, 200), try map.Lookup(2));

    const snapshot_iter = try map.First();
    defer snapshot_iter.deinit();
    try std.testing.expect(!(try map.Insert(4, 40)));

    var snapshot_pairs = std.mem.zeroes([4]?*interfaces.IKeyValuePair(i32, u64));
    try std.testing.expectEqual(@as(u32, 3), try snapshot_iter.GetMany(snapshot_pairs[0..]));
    try takeAndExpectPair(&snapshot_pairs[0], 1, 10);
    try takeAndExpectPair(&snapshot_pairs[1], 2, 200);
    try takeAndExpectPair(&snapshot_pairs[2], 3, 30);

    const view = try map.GetView();
    defer view.deinit();
    try std.testing.expectEqual(@as(u32, 4), try map.Size());
    try std.testing.expectEqual(@as(u32, 4), try view.Size());

    try map.Remove(4);
    try std.testing.expect(!(try map.HasKey(4)));
    try std.testing.expectError(error.Bounds, map.Remove(4));

    try map.Clear();
    try std.testing.expectEqual(@as(u32, 0), try map.Size());

    try expectRuntimeClassName(map, "Windows.Foundation.Collections.IMap`2<Int32, UInt64>");
}

test "observable map raises MapChanged events" {
    const allocator = std.testing.allocator;

    const map = try stock_map.createObservableMap(i32, u64, allocator, &[_]abi.Entry(i32, u64){
        .{ .key = 1, .value = 10 },
    });
    defer map.deinit();

    var log: MapEventLog = .{};
    const token = try map.MapChanged(allocator, &onMapChanged, &log);
    defer map.RemoveMapChanged(token) catch {};

    try std.testing.expect(!(try map.Insert(2, 20)));
    try std.testing.expect(try map.Insert(1, 100));
    try map.Remove(2);
    try map.Clear();

    try std.testing.expectEqual(@as(usize, 4), log.len);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemInserted, log.items[0].change);
    try std.testing.expectEqual(@as(?i32, 2), log.items[0].key);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemChanged, log.items[1].change);
    try std.testing.expectEqual(@as(?i32, 1), log.items[1].key);
    try std.testing.expectEqual(interfaces.CollectionChange.ItemRemoved, log.items[2].change);
    try std.testing.expectEqual(@as(?i32, 2), log.items[2].key);
    try std.testing.expectEqual(interfaces.CollectionChange.Reset, log.items[3].change);
    try std.testing.expectEqual(@as(?i32, null), log.items[3].key);

    try map.RemoveMapChanged(token);
    try std.testing.expect(!(try map.Insert(5, 50)));
    try std.testing.expectEqual(@as(usize, 4), log.len);

    try expectRuntimeClassName(map, "Windows.Foundation.Collections.IObservableMap`2<Int32, UInt64>");
}

test "string-backed collections clone and compare HSTRING values" {
    const allocator = std.testing.allocator;

    var values = [_]core.Hstring{
        try makeHstring("one"),
        try makeHstring("two"),
        try makeHstring("three"),
    };
    defer for (&values) |*value| value.deinit();

    const view = try stock_vector.createVectorView(core.Hstring, allocator, &values);
    defer view.deinit();

    var first = try view.GetAt(0);
    defer first.deinit();
    try expectHstringEq(first, "one");

    var query = try makeHstring("two");
    defer query.deinit();
    var index: u32 = 0;
    try std.testing.expect(try view.IndexOf(query, &index));
    try std.testing.expectEqual(@as(u32, 1), index);

    var key_one = try makeHstring("one");
    defer key_one.deinit();
    var key_two = try makeHstring("two");
    defer key_two.deinit();

    const map_entries = [_]abi.Entry(core.Hstring, i32){
        .{ .key = key_one, .value = 1 },
        .{ .key = key_two, .value = 2 },
    };
    const map = try stock_map.createMap(core.Hstring, i32, allocator, &map_entries);
    defer map.deinit();

    var lookup = try makeHstring("two");
    defer lookup.deinit();
    try std.testing.expectEqual(@as(i32, 2), try map.Lookup(lookup));
    try std.testing.expect(try map.HasKey(lookup));
}

test "can consume a real WinRT IVectorView<HSTRING> through win-collections wrappers" {
    if (builtin.target.os.tag != .windows) return;

    try core.roInitialize(.multi_threaded);
    defer core.winrt.RoUninitialize();

    const Globalization = win.WinRT.Globalization;
    const Collections = win.WinRT.Collections;

    const statics = try Globalization.ApplicationLanguages.statics();
    defer statics.deinit();

    const statics_this: *const Globalization.ApplicationLanguages.Statics = @ptrCast(@alignCast(statics.ptr));

    var raw_view: *Collections.IVectorView__G1__HSTRING = undefined;
    try core.hresult.ok(statics_this.get_Languages(&raw_view));

    const raw_view_insp: core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(raw_view)),
    };
    defer raw_view_insp.deinit();

    var ours_raw: ?*anyopaque = null;
    try core.hresult.ok(raw_view.vtable.base.base.QueryInterface(@ptrCast(raw_view), &interfaces.IVectorView(core.Hstring).IID, &ours_raw));
    const view: *interfaces.IVectorView(core.Hstring) = @ptrCast(@alignCast(ours_raw orelse return error.Pointer));
    defer view.deinit();

    const size = try view.Size();
    try std.testing.expect(size > 0);

    var first = try view.GetAt(0);
    defer first.deinit();
    try std.testing.expect(first.len() > 0);
}

test "custom observable vector can flow into a real WinRT API expecting IIterable<HSTRING>" {
    if (builtin.target.os.tag != .windows) return;

    try core.roInitialize(.multi_threaded);
    defer core.winrt.RoUninitialize();

    const allocator = std.testing.allocator;
    const Globalization = win.WinRT.Globalization;
    const Collections = win.WinRT.Collections;

    var languages = [_]core.Hstring{
        try makeHstring("en-US"),
        try makeHstring("fr-FR"),
    };
    defer for (&languages) |*language| language.deinit();

    const vector = try stock_vector.createObservableVector(core.Hstring, allocator, &languages);
    defer vector.deinit();

    const iterable = try vector.cast(Collections.IIterable__G1__HSTRING);
    const iterable_insp: core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(iterable)),
    };
    defer iterable_insp.deinit();

    const factory = try Globalization.Calendar.factory();
    defer factory.deinit();

    const calendar_factory = try factory.cast(Globalization.ICalendarFactory.Vtbl, &Globalization.ICalendarFactory.IID);
    defer calendar_factory.deinit();
    const calendar_factory_this: *const Globalization.ICalendarFactory = @ptrCast(@alignCast(calendar_factory.ptr));

    var raw_calendar: *Globalization.Calendar = undefined;
    try core.hresult.ok(calendar_factory_this.CreateCalendarDefaultCalendarAndClock(iterable, &raw_calendar));

    const calendar_insp: core.IInspectable = .{
        .ptr = @ptrCast(@alignCast(raw_calendar)),
    };
    defer calendar_insp.deinit();
}
