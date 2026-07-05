const std = @import("std");
const core = @import("win-core");
const abi = @import("abi.zig");
const interfaces = @import("interfaces.zig");

const Mutex = struct {
    state: std.atomic.Mutex = .unlocked,

    fn lock(self: *Mutex) void {
        while (!self.state.tryLock()) std.atomic.spinLoopHint();
    }

    fn unlock(self: *Mutex) void {
        self.state.unlock();
    }
};

fn guardOut(ptr: anytype) ?core.HRESULT {
    return if (@intFromPtr(ptr) == 0) core.hresult.E_POINTER else null;
}

fn guardBuffer(count: u32, ptr: anytype) ?core.HRESULT {
    return if (count != 0 and @intFromPtr(ptr) == 0) core.hresult.E_POINTER else null;
}

fn fillValues(comptime T: type, source: []const abi.StoredType(T), start_index: usize, items: []abi.BufferElement(T)) abi.CollectionError!u32 {
    if (start_index >= source.len) return 0;

    const actual = @min(source.len - start_index, items.len);
    for (0..actual) |i| {
        try abi.fillAbiClone(T, source[start_index + i], &items[i]);
    }
    return @intCast(actual);
}

fn EntryStored(comptime K: type, comptime V: type) type {
    return struct {
        key: abi.StoredType(K),
        value: abi.StoredType(V),
    };
}

fn EntryList(comptime K: type, comptime V: type) type {
    return std.ArrayList(EntryStored(K, V));
}

fn cloneInputEntry(comptime K: type, comptime V: type, entry: abi.Entry(K, V)) abi.CollectionError!EntryStored(K, V) {
    var key = try abi.cloneInput(K, entry.key);
    errdefer abi.releaseStored(K, &key);

    var value = try abi.cloneInput(V, entry.value);
    errdefer abi.releaseStored(V, &value);

    return .{
        .key = key,
        .value = value,
    };
}

fn cloneStoredEntry(comptime K: type, comptime V: type, entry: EntryStored(K, V)) abi.CollectionError!EntryStored(K, V) {
    var key = try abi.cloneStored(K, entry.key);
    errdefer abi.releaseStored(K, &key);

    var value = try abi.cloneStored(V, entry.value);
    errdefer abi.releaseStored(V, &value);

    return .{
        .key = key,
        .value = value,
    };
}

fn releaseStoredEntry(comptime K: type, comptime V: type, entry: *EntryStored(K, V)) void {
    abi.releaseStored(K, &entry.key);
    abi.releaseStored(V, &entry.value);
}

fn clearEntries(comptime K: type, comptime V: type, entries: *EntryList(K, V)) void {
    for (entries.items) |*entry| releaseStoredEntry(K, V, entry);
    entries.clearRetainingCapacity();
}

fn deinitEntries(comptime K: type, comptime V: type, allocator: std.mem.Allocator, entries: *EntryList(K, V)) void {
    clearEntries(K, V, entries);
    entries.deinit(allocator);
}

fn cloneEntriesFromInput(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const abi.Entry(K, V)) abi.CollectionError!EntryList(K, V) {
    var values = try EntryList(K, V).initCapacity(allocator, items.len);
    errdefer deinitEntries(K, V, allocator, &values);

    for (items) |item| {
        var cloned = try cloneInputEntry(K, V, item);
        errdefer releaseStoredEntry(K, V, &cloned);
        if (findEntryIndex(K, V, values.items, item.key)) |index| {
            abi.releaseStored(K, &cloned.key);
            var old_value = values.items[index].value;
            values.items[index].value = cloned.value;
            abi.releaseStored(V, &old_value);
        } else {
            try values.append(allocator, cloned);
        }
    }

    return values;
}

fn cloneEntriesFromStored(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const EntryStored(K, V)) abi.CollectionError!EntryList(K, V) {
    var values = try EntryList(K, V).initCapacity(allocator, items.len);
    errdefer deinitEntries(K, V, allocator, &values);

    for (items) |item| {
        var cloned = try cloneStoredEntry(K, V, item);
        errdefer releaseStoredEntry(K, V, &cloned);
        try values.append(allocator, cloned);
    }

    return values;
}

fn findEntryIndex(comptime K: type, comptime V: type, items: []const EntryStored(K, V), key: K) ?usize {
    for (items, 0..) |entry, i| {
        if (abi.equalsStoredInput(K, entry.key, key)) return i;
    }
    return null;
}

fn PairHandle(comptime K: type, comptime V: type) type {
    return *interfaces.IKeyValuePair(K, V);
}

fn PairList(comptime K: type, comptime V: type) type {
    return std.ArrayList(abi.StoredType(PairHandle(K, V)));
}

fn clearPairs(comptime K: type, comptime V: type, values: *PairList(K, V)) void {
    for (values.items) |*value| abi.releaseStored(PairHandle(K, V), value);
    values.clearRetainingCapacity();
}

fn deinitPairs(comptime K: type, comptime V: type, allocator: std.mem.Allocator, values: *PairList(K, V)) void {
    clearPairs(K, V, values);
    values.deinit(allocator);
}

fn KeyValuePairState(comptime K: type, comptime V: type) type {
    return struct {
        key: abi.StoredType(K),
        value: abi.StoredType(V),

        pub fn deinit(self: *@This()) void {
            abi.releaseStored(K, &self.key);
            abi.releaseStored(V, &self.value);
        }
    };
}

fn KeyValuePairAuthor(comptime K: type, comptime V: type) type {
    const State = KeyValuePairState(K, V);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IKeyValuePair(K, V).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IKeyValuePair(K, V), .{
                .base = undefined,
                .get_Key = getKey,
                .get_Value = getValue,
            }),
        });

        fn getKey(this: *const interfaces.IKeyValuePair(K, V), result: *abi.BufferElement(K)) callconv(.winapi) core.HRESULT {
            abi.fillAbiClone(K, Author.stateFrom(interfaces.IKeyValuePair(K, V), this).key, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getValue(this: *const interfaces.IKeyValuePair(K, V), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT {
            abi.fillAbiClone(V, Author.stateFrom(interfaces.IKeyValuePair(K, V), this).value, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn createKeyValuePairFromStored(comptime K: type, comptime V: type, allocator: std.mem.Allocator, entry: EntryStored(K, V)) abi.CollectionError!*interfaces.IKeyValuePair(K, V) {
    var key = try abi.cloneStored(K, entry.key);
    errdefer abi.releaseStored(K, &key);
    var value = try abi.cloneStored(V, entry.value);
    errdefer abi.releaseStored(V, &value);
    const storage = try KeyValuePairAuthor(K, V).create(allocator, .{
        .key = key,
        .value = value,
    });
    return KeyValuePairAuthor(K, V).as(storage, interfaces.IKeyValuePair(K, V));
}

fn createPairsSnapshot(comptime K: type, comptime V: type, allocator: std.mem.Allocator, entries: []const EntryStored(K, V)) abi.CollectionError!PairList(K, V) {
    var values = try PairList(K, V).initCapacity(allocator, entries.len);
    errdefer deinitPairs(K, V, allocator, &values);

    for (entries) |entry| {
        const pair = try createKeyValuePairFromStored(K, V, allocator, entry);
        errdefer pair.deinit();
        try values.append(allocator, pair);
    }

    return values;
}

fn MapIteratorState(comptime K: type, comptime V: type) type {
    return struct {
        values: PairList(K, V),
        current: std.atomic.Value(usize),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitPairs(K, V, allocator, &self.values);
        }
    };
}

fn MapIteratorAuthor(comptime K: type, comptime V: type) type {
    const Handle = interfaces.IIterator(PairHandle(K, V));
    const State = MapIteratorState(K, V);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = Handle.NAME_W,
        }, .{
            core.interfaceSpec(Handle, .{
                .base = undefined,
                .get_Current = getCurrent,
                .get_HasCurrent = getHasCurrent,
                .MoveNext = moveNext,
                .GetMany = getMany,
            }),
        });

        fn getCurrent(this: *const Handle, result: *abi.BufferElement(PairHandle(K, V))) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(Handle, this);
            const current = state.current.load(.acquire);
            if (current >= state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(PairHandle(K, V), state.values.items[current], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getHasCurrent(this: *const Handle, result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(Handle, this);
            result.* = core.boolToWin32(state.current.load(.acquire) < state.values.items.len);
            return core.hresult.S_OK;
        }

        fn moveNext(this: *const Handle, result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(Handle, this);
            const current = state.current.load(.acquire);
            const len = state.values.items.len;
            if (current < len) _ = state.current.fetchAdd(1, .acq_rel);
            result.* = core.boolToWin32(len > current + 1);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const Handle, items_size: u32, items_ptr: [*]abi.BufferElement(PairHandle(K, V)), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(Handle, this);
            const current = state.current.load(.acquire);
            const actual = fillValues(PairHandle(K, V), state.values.items, current, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            _ = state.current.fetchAdd(actual, .acq_rel);
            result.* = actual;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn MapViewState(comptime K: type, comptime V: type) type {
    return struct {
        entries: EntryList(K, V),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitEntries(K, V, allocator, &self.entries);
        }
    };
}

fn MapViewAuthor(comptime K: type, comptime V: type) type {
    const IterableHandle = interfaces.IIterable(PairHandle(K, V));
    const ViewHandle = interfaces.IMapView(K, V);
    const State = MapViewState(K, V);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = ViewHandle.NAME_W,
        }, .{
            core.interfaceSpec(IterableHandle, .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(ViewHandle, .{
                .base = undefined,
                .Lookup = lookup,
                .get_Size = getSize,
                .HasKey = hasKey,
                .Split = split,
            }),
        });

        fn first(this: *const IterableHandle, result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(IterableHandle, this);
            const snapshot = createPairsSnapshot(K, V, storage.allocator, storage.state.entries.items) catch |err| return abi.toHRESULT(err);
            const iter_storage = MapIteratorAuthor(K, V).create(storage.allocator, .{
                .values = snapshot,
                .current = std.atomic.Value(usize).init(0),
            }) catch |err| {
                var values = snapshot;
                deinitPairs(K, V, storage.allocator, &values);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(MapIteratorAuthor(K, V).as(iter_storage, interfaces.IIterator(PairHandle(K, V))));
            return core.hresult.S_OK;
        }

        fn lookup(this: *const ViewHandle, key_raw: abi.BufferElement(K), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT {
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(ViewHandle, this);
            const index = findEntryIndex(K, V, state.entries.items, key) orelse return interfaces.E_BOUNDS;
            abi.fillAbiClone(V, state.entries.items[index].value, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const ViewHandle, result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            result.* = @intCast(Author.stateFrom(ViewHandle, this).entries.items.len);
            return core.hresult.S_OK;
        }

        fn hasKey(this: *const ViewHandle, key_raw: abi.BufferElement(K), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(ViewHandle, this);
            result.* = core.boolToWin32(findEntryIndex(K, V, state.entries.items, key) != null);
            return core.hresult.S_OK;
        }

        fn split(_: *const ViewHandle, first_out: **anyopaque, second_out: **anyopaque) callconv(.winapi) core.HRESULT {
            if (@intFromPtr(first_out) == 0 or @intFromPtr(second_out) == 0) return core.hresult.E_POINTER;
            @as(*?*anyopaque, @ptrCast(first_out)).* = null;
            @as(*?*anyopaque, @ptrCast(second_out)).* = null;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn MapState(comptime K: type, comptime V: type) type {
    return struct {
        mutex: Mutex = .{},
        entries: EntryList(K, V),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitEntries(K, V, allocator, &self.entries);
        }
    };
}

fn MapAuthor(comptime K: type, comptime V: type) type {
    const IterableHandle = interfaces.IIterable(PairHandle(K, V));
    const MapHandle = interfaces.IMap(K, V);
    const State = MapState(K, V);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = MapHandle.NAME_W,
        }, .{
            core.interfaceSpec(IterableHandle, .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(MapHandle, .{
                .base = undefined,
                .Lookup = lookup,
                .get_Size = getSize,
                .HasKey = hasKey,
                .GetView = getView,
                .Insert = insert,
                .Remove = remove,
                .Clear = clear,
            }),
        });

        fn first(this: *const IterableHandle, result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(IterableHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = createPairsSnapshot(K, V, storage.allocator, state.entries.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const iter_storage = MapIteratorAuthor(K, V).create(storage.allocator, .{
                .values = snapshot,
                .current = std.atomic.Value(usize).init(0),
            }) catch |err| {
                var values = snapshot;
                deinitPairs(K, V, storage.allocator, &values);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(MapIteratorAuthor(K, V).as(iter_storage, interfaces.IIterator(PairHandle(K, V))));
            return core.hresult.S_OK;
        }

        fn lookup(this: *const MapHandle, key_raw: abi.BufferElement(K), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT {
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();

            const index = findEntryIndex(K, V, state.entries.items, key) orelse return interfaces.E_BOUNDS;
            abi.fillAbiClone(V, state.entries.items[index].value, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const MapHandle, result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = @intCast(state.entries.items.len);
            return core.hresult.S_OK;
        }

        fn hasKey(this: *const MapHandle, key_raw: abi.BufferElement(K), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = core.boolToWin32(findEntryIndex(K, V, state.entries.items, key) != null);
            return core.hresult.S_OK;
        }

        fn getView(this: *const MapHandle, result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = cloneEntriesFromStored(K, V, storage.allocator, state.entries.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const view_storage = MapViewAuthor(K, V).create(storage.allocator, .{
                .entries = snapshot,
            }) catch |err| {
                var entries = snapshot;
                deinitEntries(K, V, storage.allocator, &entries);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(MapViewAuthor(K, V).as(view_storage, interfaces.IMapView(K, V)));
            return core.hresult.S_OK;
        }

        fn insert(this: *const MapHandle, key_raw: abi.BufferElement(K), value_raw: abi.BufferElement(V), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const value = abi.borrowedAbiValue(V, value_raw) catch |err| return abi.toHRESULT(err);

            var cloned_key = abi.cloneInput(K, key) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(K, &cloned_key);
            var cloned_value = abi.cloneInput(V, value) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(V, &cloned_value);

            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            if (findEntryIndex(K, V, state.entries.items, key)) |index| {
                var old_value = state.entries.items[index].value;
                state.entries.items[index].value = cloned_value;
                state.mutex.unlock();
                abi.releaseStored(K, &cloned_key);
                abi.releaseStored(V, &old_value);
                result.* = core.boolToWin32(true);
                return core.hresult.S_OK;
            }

            state.entries.append(storage.allocator, .{
                .key = cloned_key,
                .value = cloned_value,
            }) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();
            result.* = core.boolToWin32(false);
            return core.hresult.S_OK;
        }

        fn remove(this: *const MapHandle, key_raw: abi.BufferElement(K)) callconv(.winapi) core.HRESULT {
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            const index = findEntryIndex(K, V, state.entries.items, key) orelse {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            };
            var removed = state.entries.orderedRemove(index);
            state.mutex.unlock();
            releaseStoredEntry(K, V, &removed);
            return core.hresult.S_OK;
        }

        fn clear(this: *const MapHandle) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            const emptied = EntryList(K, V).initCapacity(storage.allocator, 0) catch return core.hresult.E_OUTOFMEMORY;
            state.mutex.lock();
            var removed = state.entries;
            state.entries = emptied;
            state.mutex.unlock();
            deinitEntries(K, V, storage.allocator, &removed);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn MapChangedArgsState(comptime K: type) type {
    return struct {
        change: interfaces.CollectionChange,
        has_key: bool,
        key: abi.StoredType(K),

        pub fn deinit(self: *@This()) void {
            abi.releaseStored(K, &self.key);
        }
    };
}

fn MapChangedArgsAuthor(comptime K: type) type {
    const Handle = interfaces.IMapChangedEventArgs(K);
    const State = MapChangedArgsState(K);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = Handle.NAME_W,
        }, .{
            core.interfaceSpec(Handle, .{
                .base = undefined,
                .get_CollectionChange = getCollectionChange,
                .get_Key = getKey,
            }),
        });

        fn getCollectionChange(this: *const Handle, result: *interfaces.CollectionChange) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            result.* = Author.stateFrom(Handle, this).change;
            return core.hresult.S_OK;
        }

        fn getKey(this: *const Handle, result: *abi.BufferElement(K)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(Handle, this);
            if (!state.has_key) return interfaces.E_BOUNDS;
            abi.fillAbiClone(K, state.key, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn createMapChangedArgsWithKey(comptime K: type, allocator: std.mem.Allocator, change: interfaces.CollectionChange, key: K) abi.CollectionError!*interfaces.IMapChangedEventArgs(K) {
    var cloned_key = try abi.cloneInput(K, key);
    errdefer abi.releaseStored(K, &cloned_key);
    const storage = try MapChangedArgsAuthor(K).create(allocator, .{
        .change = change,
        .has_key = true,
        .key = cloned_key,
    });
    return MapChangedArgsAuthor(K).as(storage, interfaces.IMapChangedEventArgs(K));
}

fn createMapChangedArgsWithStoredKey(comptime K: type, allocator: std.mem.Allocator, change: interfaces.CollectionChange, key: abi.StoredType(K)) abi.CollectionError!*interfaces.IMapChangedEventArgs(K) {
    var cloned_key = try abi.cloneStored(K, key);
    errdefer abi.releaseStored(K, &cloned_key);
    const storage = try MapChangedArgsAuthor(K).create(allocator, .{
        .change = change,
        .has_key = true,
        .key = cloned_key,
    });
    return MapChangedArgsAuthor(K).as(storage, interfaces.IMapChangedEventArgs(K));
}

fn createMapChangedArgsReset(comptime K: type, allocator: std.mem.Allocator) abi.CollectionError!*interfaces.IMapChangedEventArgs(K) {
    const storage = try MapChangedArgsAuthor(K).create(allocator, .{
        .change = .Reset,
        .has_key = false,
        .key = abi.defaultStored(K),
    });
    return MapChangedArgsAuthor(K).as(storage, interfaces.IMapChangedEventArgs(K));
}

fn ObservableMapState(comptime K: type, comptime V: type) type {
    return struct {
        mutex: Mutex = .{},
        entries: EntryList(K, V),
        handlers: std.ArrayList(HandlerEntry),
        pending_notifications: std.ArrayList(Notification),
        dispatching: bool = false,
        next_token: i64 = 1,
        handlers_mutex: Mutex = .{},

        const HandlerEntry = struct {
            token: interfaces.EventRegistrationToken,
            handler: *anyopaque,
        };

        const Notification = struct {
            change: interfaces.CollectionChange,
            has_key: bool,
            key: abi.StoredType(K),
        };

        fn init(allocator: std.mem.Allocator, entries: EntryList(K, V)) abi.CollectionError!@This() {
            return .{
                .entries = entries,
                .handlers = try std.ArrayList(HandlerEntry).initCapacity(allocator, 0),
                .pending_notifications = try std.ArrayList(Notification).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.pending_notifications.items) |*notification| {
                if (notification.has_key) abi.releaseStored(K, &notification.key);
            }
            self.pending_notifications.deinit(allocator);
            for (self.handlers.items) |entry| abi.releaseAny(entry.handler);
            self.handlers.deinit(allocator);
            deinitEntries(K, V, allocator, &self.entries);
        }

        fn enqueueReset(self: *@This(), allocator: std.mem.Allocator) abi.CollectionError!bool {
            try self.pending_notifications.append(allocator, .{
                .change = .Reset,
                .has_key = false,
                .key = abi.defaultStored(K),
            });
            if (self.dispatching) return false;
            self.dispatching = true;
            return true;
        }

        fn enqueueWithKey(self: *@This(), allocator: std.mem.Allocator, change: interfaces.CollectionChange, key: K) abi.CollectionError!bool {
            var cloned_key = try abi.cloneInput(K, key);
            errdefer abi.releaseStored(K, &cloned_key);
            try self.pending_notifications.append(allocator, .{
                .change = change,
                .has_key = true,
                .key = cloned_key,
            });
            if (self.dispatching) return false;
            self.dispatching = true;
            return true;
        }

        fn nextNotification(self: *@This()) ?Notification {
            if (self.pending_notifications.items.len == 0) {
                self.dispatching = false;
                return null;
            }
            return self.pending_notifications.orderedRemove(0);
        }

        fn addHandler(self: *@This(), allocator: std.mem.Allocator, handler: *anyopaque) abi.CollectionError!interfaces.EventRegistrationToken {
            if (@intFromPtr(handler) == 0) return error.Pointer;
            self.handlers_mutex.lock();
            defer self.handlers_mutex.unlock();

            const token: interfaces.EventRegistrationToken = .{ .Value = self.next_token };
            try self.handlers.append(allocator, .{
                .token = token,
                .handler = handler,
            });
            self.next_token += 1;
            abi.addRefAny(handler);
            return token;
        }

        fn removeHandler(self: *@This(), token: interfaces.EventRegistrationToken) void {
            self.handlers_mutex.lock();
            defer self.handlers_mutex.unlock();

            for (self.handlers.items, 0..) |entry, i| {
                if (entry.token.Value == token.Value) {
                    const removed = self.handlers.orderedRemove(i);
                    abi.releaseAny(removed.handler);
                    return;
                }
            }
        }

        fn snapshotHandlers(self: *@This(), allocator: std.mem.Allocator) abi.CollectionError!std.ArrayList(*anyopaque) {
            self.handlers_mutex.lock();
            defer self.handlers_mutex.unlock();

            var out = try std.ArrayList(*anyopaque).initCapacity(allocator, self.handlers.items.len);
            errdefer {
                for (out.items) |handler| abi.releaseAny(handler);
                out.deinit(allocator);
            }

            for (self.handlers.items) |entry| {
                abi.addRefAny(entry.handler);
                errdefer abi.releaseAny(entry.handler);
                try out.append(allocator, entry.handler);
            }

            return out;
        }
    };
}

fn ObservableMapAuthor(comptime K: type, comptime V: type) type {
    const IterableHandle = interfaces.IIterable(PairHandle(K, V));
    const MapHandle = interfaces.IMap(K, V);
    const ObservableHandle = interfaces.IObservableMap(K, V);
    const State = ObservableMapState(K, V);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = ObservableHandle.NAME_W,
            .agile = false,
        }, .{
            core.interfaceSpec(IterableHandle, .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(MapHandle, .{
                .base = undefined,
                .Lookup = lookup,
                .get_Size = getSize,
                .HasKey = hasKey,
                .GetView = getView,
                .Insert = insert,
                .Remove = remove,
                .Clear = clear,
            }),
            core.interfaceSpec(ObservableHandle, .{
                .base = undefined,
                .add_MapChanged = addMapChanged,
                .remove_MapChanged = removeMapChanged,
            }),
        });

        fn fireChangedWithKey(storage: *Author.Storage, change: interfaces.CollectionChange, key: K) core.HRESULT {
            var args = createMapChangedArgsWithKey(K, storage.allocator, change, key) catch |err| return abi.toHRESULT(err);
            defer args.deinit();
            return dispatchChanged(storage, args);
        }

        fn fireChangedWithStoredKey(storage: *Author.Storage, change: interfaces.CollectionChange, key: abi.StoredType(K)) core.HRESULT {
            var args = createMapChangedArgsWithStoredKey(K, storage.allocator, change, key) catch |err| return abi.toHRESULT(err);
            defer args.deinit();
            return dispatchChanged(storage, args);
        }

        fn fireChangedReset(storage: *Author.Storage) core.HRESULT {
            var args = createMapChangedArgsReset(K, storage.allocator) catch |err| return abi.toHRESULT(err);
            defer args.deinit();
            return dispatchChanged(storage, args);
        }

        fn dispatchChanged(storage: *Author.Storage, args: *interfaces.IMapChangedEventArgs(K)) core.HRESULT {
            var snapshot = storage.state.snapshotHandlers(storage.allocator) catch |err| return abi.toHRESULT(err);
            defer {
                for (snapshot.items) |handler| abi.releaseAny(handler);
                snapshot.deinit(storage.allocator);
            }

            const sender = Author.as(storage, ObservableHandle);
            _ = sender.AddRef();
            defer _ = sender.Release();
            const sender_raw: *anyopaque = @ptrCast(sender);
            const args_raw: *anyopaque = @ptrCast(args);
            for (snapshot.items) |raw| {
                const handler: *const interfaces.MapChangedEventHandler(K, V) = @ptrCast(@alignCast(raw));
                _ = handler.vtable.Invoke(handler, sender_raw, args_raw);
            }

            return core.hresult.S_OK;
        }

        fn drainNotifications(storage: *Author.Storage) void {
            while (true) {
                storage.state.mutex.lock();
                const notification = storage.state.nextNotification();
                storage.state.mutex.unlock();
                var next = notification orelse break;
                defer if (next.has_key) abi.releaseStored(K, &next.key);
                if (next.has_key) {
                    _ = fireChangedWithStoredKey(storage, next.change, next.key);
                } else {
                    _ = fireChangedReset(storage);
                }
            }
        }

        fn first(this: *const IterableHandle, result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(IterableHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = createPairsSnapshot(K, V, storage.allocator, state.entries.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const iter_storage = MapIteratorAuthor(K, V).create(storage.allocator, .{
                .values = snapshot,
                .current = std.atomic.Value(usize).init(0),
            }) catch |err| {
                var values = snapshot;
                deinitPairs(K, V, storage.allocator, &values);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(MapIteratorAuthor(K, V).as(iter_storage, interfaces.IIterator(PairHandle(K, V))));
            return core.hresult.S_OK;
        }

        fn lookup(this: *const MapHandle, key_raw: abi.BufferElement(K), result: *abi.BufferElement(V)) callconv(.winapi) core.HRESULT {
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();

            const index = findEntryIndex(K, V, state.entries.items, key) orelse return interfaces.E_BOUNDS;
            abi.fillAbiClone(V, state.entries.items[index].value, result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const MapHandle, result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = @intCast(state.entries.items.len);
            return core.hresult.S_OK;
        }

        fn hasKey(this: *const MapHandle, key_raw: abi.BufferElement(K), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const state = Author.stateFrom(MapHandle, this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = core.boolToWin32(findEntryIndex(K, V, state.entries.items, key) != null);
            return core.hresult.S_OK;
        }

        fn getView(this: *const MapHandle, result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = cloneEntriesFromStored(K, V, storage.allocator, state.entries.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const view_storage = MapViewAuthor(K, V).create(storage.allocator, .{
                .entries = snapshot,
            }) catch |err| {
                var entries = snapshot;
                deinitEntries(K, V, storage.allocator, &entries);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(MapViewAuthor(K, V).as(view_storage, interfaces.IMapView(K, V)));
            return core.hresult.S_OK;
        }

        fn insert(this: *const MapHandle, key_raw: abi.BufferElement(K), value_raw: abi.BufferElement(V), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const value = abi.borrowedAbiValue(V, value_raw) catch |err| return abi.toHRESULT(err);

            var cloned_key = abi.cloneInput(K, key) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(K, &cloned_key);
            var cloned_value = abi.cloneInput(V, value) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(V, &cloned_value);

            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            state.mutex.lock();
            if (findEntryIndex(K, V, state.entries.items, key)) |index| {
                var old_value = state.entries.items[index].value;
                state.entries.items[index].value = cloned_value;
                const should_dispatch = state.enqueueWithKey(storage.allocator, .ItemChanged, key) catch {
                    state.mutex.unlock();
                    abi.releaseStored(K, &cloned_key);
                    abi.releaseStored(V, &old_value);
                    result.* = core.boolToWin32(true);
                    return core.hresult.S_OK;
                };
                state.mutex.unlock();
                abi.releaseStored(K, &cloned_key);
                abi.releaseStored(V, &old_value);
                result.* = core.boolToWin32(true);
                if (should_dispatch) drainNotifications(storage);
                return core.hresult.S_OK;
            } else {
                state.entries.append(storage.allocator, .{
                    .key = cloned_key,
                    .value = cloned_value,
                }) catch |err| {
                    state.mutex.unlock();
                    return abi.toHRESULT(err);
                };
                const should_dispatch = state.enqueueWithKey(storage.allocator, .ItemInserted, key) catch {
                    state.mutex.unlock();
                    result.* = core.boolToWin32(false);
                    return core.hresult.S_OK;
                };
                state.mutex.unlock();
                result.* = core.boolToWin32(false);
                if (should_dispatch) drainNotifications(storage);
                return core.hresult.S_OK;
            }
        }

        fn remove(this: *const MapHandle, key_raw: abi.BufferElement(K)) callconv(.winapi) core.HRESULT {
            const key = abi.borrowedAbiValue(K, key_raw) catch |err| return abi.toHRESULT(err);
            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;

            state.mutex.lock();
            const index = findEntryIndex(K, V, state.entries.items, key) orelse {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            };
            var removed = state.entries.orderedRemove(index);
            const should_dispatch = state.enqueueWithKey(storage.allocator, .ItemRemoved, key) catch {
                state.mutex.unlock();
                releaseStoredEntry(K, V, &removed);
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            releaseStoredEntry(K, V, &removed);

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn clear(this: *const MapHandle) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(MapHandle, this);
            const state = &storage.state;
            const emptied = EntryList(K, V).initCapacity(storage.allocator, 0) catch return core.hresult.E_OUTOFMEMORY;
            state.mutex.lock();
            var removed = state.entries;
            state.entries = emptied;
            const should_dispatch = state.enqueueReset(storage.allocator) catch {
                state.mutex.unlock();
                state.entries = removed;
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            deinitEntries(K, V, storage.allocator, &removed);
            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn addMapChanged(this: *const ObservableHandle, handler: *anyopaque, result: *interfaces.EventRegistrationToken) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(ObservableHandle, this);
            result.* = storage.state.addHandler(storage.allocator, handler) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn removeMapChanged(this: *const ObservableHandle, token: interfaces.EventRegistrationToken) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(ObservableHandle, this);
            storage.state.removeHandler(token);
            return core.hresult.S_OK;
        }
    }.Author;
}

pub fn createMapView(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const abi.Entry(K, V)) abi.CollectionError!*interfaces.IMapView(K, V) {
    var entries = try cloneEntriesFromInput(K, V, allocator, items);
    errdefer deinitEntries(K, V, allocator, &entries);
    const storage = try MapViewAuthor(K, V).create(allocator, .{
        .entries = entries,
    });
    return MapViewAuthor(K, V).as(storage, interfaces.IMapView(K, V));
}

pub fn createMap(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const abi.Entry(K, V)) abi.CollectionError!*interfaces.IMap(K, V) {
    var entries = try cloneEntriesFromInput(K, V, allocator, items);
    errdefer deinitEntries(K, V, allocator, &entries);
    const storage = try MapAuthor(K, V).create(allocator, .{
        .entries = entries,
    });
    return MapAuthor(K, V).as(storage, interfaces.IMap(K, V));
}

pub fn createObservableMap(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const abi.Entry(K, V)) abi.CollectionError!*interfaces.IObservableMap(K, V) {
    var entries = try cloneEntriesFromInput(K, V, allocator, items);
    errdefer deinitEntries(K, V, allocator, &entries);
    var state = try ObservableMapState(K, V).init(allocator, entries);
    errdefer state.deinit(allocator);
    const storage = try ObservableMapAuthor(K, V).create(allocator, state);
    return ObservableMapAuthor(K, V).as(storage, interfaces.IObservableMap(K, V));
}
