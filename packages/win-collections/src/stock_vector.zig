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

fn ValuesList(comptime T: type) type {
    return std.ArrayList(abi.StoredType(T));
}

fn cloneValues(comptime T: type, allocator: std.mem.Allocator, items: []const T) abi.CollectionError!ValuesList(T) {
    var values = try ValuesList(T).initCapacity(allocator, items.len);
    errdefer deinitValues(T, allocator, &values);

    for (items) |item| {
        var cloned = try abi.cloneInput(T, item);
        errdefer abi.releaseStored(T, &cloned);
        try values.append(allocator, cloned);
    }

    return values;
}

fn clearValues(comptime T: type, values: *ValuesList(T)) void {
    for (values.items) |*item| abi.releaseStored(T, item);
    values.clearRetainingCapacity();
}

fn deinitValues(comptime T: type, allocator: std.mem.Allocator, values: *ValuesList(T)) void {
    clearValues(T, values);
    values.deinit(allocator);
}

fn fillValues(comptime T: type, source: []const abi.StoredType(T), start_index: usize, items: []abi.BufferElement(T)) abi.CollectionError!u32 {
    if (start_index >= source.len) return 0;

    const actual = @min(source.len - start_index, items.len);
    var filled: usize = 0;
    errdefer abi.releaseBuffer(T, items[0..filled]);
    for (0..actual) |i| {
        try abi.fillAbiClone(T, source[start_index + i], &items[i]);
        filled += 1;
    }
    return @intCast(actual);
}

fn HandlerList(comptime DelegateHandle: type) type {
    comptime _ = DelegateHandle;
    return struct {
        entries: std.ArrayList(Entry),
        next_token: i64 = 1,
        mutex: Mutex = .{},

        const Entry = struct {
            token: interfaces.EventRegistrationToken,
            handler: *anyopaque,
        };

        fn init(allocator: std.mem.Allocator) abi.CollectionError!@This() {
            return .{
                .entries = try std.ArrayList(Entry).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.entries.items) |entry| abi.releaseAny(entry.handler);
            self.entries.deinit(allocator);
        }

        fn add(self: *@This(), allocator: std.mem.Allocator, handler: *anyopaque) abi.CollectionError!interfaces.EventRegistrationToken {
            if (@intFromPtr(handler) == 0) return error.Pointer;
            self.mutex.lock();
            defer self.mutex.unlock();

            const token: interfaces.EventRegistrationToken = .{ .Value = self.next_token };
            try self.entries.append(allocator, .{
                .token = token,
                .handler = handler,
            });
            self.next_token += 1;
            abi.addRefAny(handler);
            return token;
        }

        fn remove(self: *@This(), token: interfaces.EventRegistrationToken) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (self.entries.items, 0..) |entry, i| {
                if (entry.token.Value == token.Value) {
                    const removed = self.entries.orderedRemove(i);
                    abi.releaseAny(removed.handler);
                    return;
                }
            }
        }

        fn snapshot(self: *@This(), allocator: std.mem.Allocator) abi.CollectionError!std.ArrayList(*anyopaque) {
            self.mutex.lock();
            defer self.mutex.unlock();

            var out = try std.ArrayList(*anyopaque).initCapacity(allocator, self.entries.items.len);
            errdefer {
                for (out.items) |handler| abi.releaseAny(handler);
                out.deinit(allocator);
            }

            for (self.entries.items) |entry| {
                abi.addRefAny(entry.handler);
                errdefer abi.releaseAny(entry.handler);
                try out.append(allocator, entry.handler);
            }

            return out;
        }
    };
}

fn VectorChangedArgsState() type {
    return struct {
        change: interfaces.CollectionChange,
        index: u32,
    };
}

fn VectorChangedArgsAuthor() type {
    return struct {
        pub const Author = core.MultiInterfaceObject(VectorChangedArgsState(), .{
            .runtime_class_name = interfaces.IVectorChangedEventArgs.NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IVectorChangedEventArgs, .{
                .base = undefined,
                .get_CollectionChange = getCollectionChange,
                .get_Index = getIndex,
            }),
        });

        fn getCollectionChange(this: *const interfaces.IVectorChangedEventArgs, result: *interfaces.CollectionChange) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            result.* = Author.stateFrom(interfaces.IVectorChangedEventArgs, this).change;
            return core.hresult.S_OK;
        }

        fn getIndex(this: *const interfaces.IVectorChangedEventArgs, result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            result.* = Author.stateFrom(interfaces.IVectorChangedEventArgs, this).index;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn createVectorChangedArgs(
    allocator: std.mem.Allocator,
    change: interfaces.CollectionChange,
    index: u32,
) abi.CollectionError!*interfaces.IVectorChangedEventArgs {
    const storage = try VectorChangedArgsAuthor().create(allocator, .{
        .change = change,
        .index = index,
    });
    return VectorChangedArgsAuthor().as(storage, interfaces.IVectorChangedEventArgs);
}

fn IterableState(comptime T: type) type {
    return struct {
        values: ValuesList(T),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitValues(T, allocator, &self.values);
        }
    };
}

fn IterableIteratorState(comptime T: type) type {
    return struct {
        owner: *interfaces.IIterable(T),
        current: std.atomic.Value(usize),

        pub fn deinit(self: *@This()) void {
            _ = self.owner.Release();
        }
    };
}

fn IterableIteratorAuthor(comptime T: type) type {
    const Owner = interfaces.IIterable(T);
    const State = IterableIteratorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IIterator(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterator(T), .{
                .base = undefined,
                .get_Current = getCurrent,
                .get_HasCurrent = getHasCurrent,
                .MoveNext = moveNext,
                .GetMany = getMany,
            }),
        });

        fn getCurrent(this: *const interfaces.IIterator(T), result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = IterableAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            if (current >= owner_state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, owner_state.values.items[current], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getHasCurrent(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = IterableAuthor(T).stateFrom(Owner, state.owner);
            result.* = core.boolToWin32(state.current.load(.acquire) < owner_state.values.items.len);
            return core.hresult.S_OK;
        }

        fn moveNext(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = IterableAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            const len = owner_state.values.items.len;
            if (current < len) _ = state.current.fetchAdd(1, .acq_rel);
            result.* = core.boolToWin32(len > current + 1);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IIterator(T), items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = IterableAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            const items = items_ptr[0..items_size];
            const actual = fillValues(T, owner_state.values.items, current, items) catch |err| return abi.toHRESULT(err);
            _ = state.current.fetchAdd(actual, .acq_rel);
            result.* = actual;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn IterableAuthor(comptime T: type) type {
    const State = IterableState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IIterable(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterable(T), .{
                .base = undefined,
                .First = first,
            }),
        });

        fn first(this: *const interfaces.IIterable(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IIterable(T), this);
            const owner = Author.as(storage, interfaces.IIterable(T));
            _ = owner.AddRef();

            const iter_storage = IterableIteratorAuthor(T).create(storage.allocator, .{
                .owner = owner,
                .current = std.atomic.Value(usize).init(0),
            }) catch {
                _ = owner.Release();
                return core.hresult.E_OUTOFMEMORY;
            };

            result.* = @ptrCast(IterableIteratorAuthor(T).as(iter_storage, interfaces.IIterator(T)));
            return core.hresult.S_OK;
        }
    }.Author;
}

fn VectorViewState(comptime T: type) type {
    return struct {
        values: ValuesList(T),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitValues(T, allocator, &self.values);
        }
    };
}

fn VectorViewIteratorState(comptime T: type) type {
    return struct {
        owner: *interfaces.IVectorView(T),
        current: std.atomic.Value(usize),

        pub fn deinit(self: *@This()) void {
            _ = self.owner.Release();
        }
    };
}

fn VectorViewIteratorAuthor(comptime T: type) type {
    const Owner = interfaces.IVectorView(T);
    const State = VectorViewIteratorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IIterator(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterator(T), .{
                .base = undefined,
                .get_Current = getCurrent,
                .get_HasCurrent = getHasCurrent,
                .MoveNext = moveNext,
                .GetMany = getMany,
            }),
        });

        fn getCurrent(this: *const interfaces.IIterator(T), result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorViewAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            if (current >= owner_state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, owner_state.values.items[current], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getHasCurrent(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorViewAuthor(T).stateFrom(Owner, state.owner);
            result.* = core.boolToWin32(state.current.load(.acquire) < owner_state.values.items.len);
            return core.hresult.S_OK;
        }

        fn moveNext(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorViewAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            const len = owner_state.values.items.len;
            if (current < len) _ = state.current.fetchAdd(1, .acq_rel);
            result.* = core.boolToWin32(len > current + 1);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IIterator(T), items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorViewAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            const items = items_ptr[0..items_size];
            const actual = fillValues(T, owner_state.values.items, current, items) catch |err| return abi.toHRESULT(err);
            _ = state.current.fetchAdd(actual, .acq_rel);
            result.* = actual;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn VectorViewAuthor(comptime T: type) type {
    const State = VectorViewState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IVectorView(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterable(T), .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(interfaces.IVectorView(T), .{
                .base = undefined,
                .GetAt = getAt,
                .get_Size = getSize,
                .IndexOf = indexOf,
                .GetMany = getMany,
            }),
        });

        fn first(this: *const interfaces.IIterable(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IIterable(T), this);
            const owner = Author.as(storage, interfaces.IVectorView(T));
            _ = owner.AddRef();

            const iter_storage = VectorViewIteratorAuthor(T).create(storage.allocator, .{
                .owner = owner,
                .current = std.atomic.Value(usize).init(0),
            }) catch {
                _ = owner.Release();
                return core.hresult.E_OUTOFMEMORY;
            };

            result.* = @ptrCast(VectorViewIteratorAuthor(T).as(iter_storage, interfaces.IIterator(T)));
            return core.hresult.S_OK;
        }

        fn getAt(this: *const interfaces.IVectorView(T), index: u32, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IVectorView(T), this);
            if (index >= state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, state.values.items[index], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const interfaces.IVectorView(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            result.* = @intCast(Author.stateFrom(interfaces.IVectorView(T), this).values.items.len);
            return core.hresult.S_OK;
        }

        fn indexOf(this: *const interfaces.IVectorView(T), value: abi.BufferElement(T), index: *u32, result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(index)) |hr| return hr;
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVectorView(T), this);
            const needle = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);

            for (state.values.items, 0..) |item, i| {
                if (abi.equalsStoredInput(T, item, needle)) {
                    index.* = @intCast(i);
                    result.* = core.boolToWin32(true);
                    return core.hresult.S_OK;
                }
            }

            index.* = 0;
            result.* = core.boolToWin32(false);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IVectorView(T), start_index: u32, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVectorView(T), this);
            result.* = fillValues(T, state.values.items, start_index, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn VectorState(comptime T: type) type {
    return struct {
        mutex: Mutex = .{},
        values: ValuesList(T),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            deinitValues(T, allocator, &self.values);
        }
    };
}

fn VectorIteratorState(comptime T: type) type {
    return struct {
        owner: *interfaces.IVector(T),
        current: std.atomic.Value(usize),

        pub fn deinit(self: *@This()) void {
            _ = self.owner.Release();
        }
    };
}

fn VectorIteratorAuthor(comptime T: type) type {
    const Owner = interfaces.IVector(T);
    const State = VectorIteratorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IIterator(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterator(T), .{
                .base = undefined,
                .get_Current = getCurrent,
                .get_HasCurrent = getHasCurrent,
                .MoveNext = moveNext,
                .GetMany = getMany,
            }),
        });

        fn getCurrent(this: *const interfaces.IIterator(T), result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            if (current >= owner_state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, owner_state.values.items[current], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getHasCurrent(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorAuthor(T).stateFrom(Owner, state.owner);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            result.* = core.boolToWin32(state.current.load(.acquire) < owner_state.values.items.len);
            return core.hresult.S_OK;
        }

        fn moveNext(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorAuthor(T).stateFrom(Owner, state.owner);
            owner_state.mutex.lock();
            const current = state.current.load(.acquire);
            const len = owner_state.values.items.len;
            owner_state.mutex.unlock();
            if (current < len) _ = state.current.fetchAdd(1, .acq_rel);
            result.* = core.boolToWin32(len > current + 1);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IIterator(T), items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = VectorAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            const actual = fillValues(T, owner_state.values.items, current, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            _ = state.current.fetchAdd(actual, .acq_rel);
            result.* = actual;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn VectorAuthor(comptime T: type) type {
    const State = VectorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IVector(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterable(T), .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(interfaces.IVector(T), .{
                .base = undefined,
                .GetAt = getAt,
                .get_Size = getSize,
                .GetView = getView,
                .IndexOf = indexOf,
                .SetAt = setAt,
                .InsertAt = insertAt,
                .RemoveAt = removeAt,
                .Append = append,
                .RemoveAtEnd = removeAtEnd,
                .Clear = clear,
                .GetMany = getMany,
                .ReplaceAll = replaceAll,
            }),
        });

        fn first(this: *const interfaces.IIterable(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IIterable(T), this);
            const owner = Author.as(storage, interfaces.IVector(T));
            _ = owner.AddRef();

            const iter_storage = VectorIteratorAuthor(T).create(storage.allocator, .{
                .owner = owner,
                .current = std.atomic.Value(usize).init(0),
            }) catch {
                _ = owner.Release();
                return core.hresult.E_OUTOFMEMORY;
            };

            result.* = @ptrCast(VectorIteratorAuthor(T).as(iter_storage, interfaces.IIterator(T)));
            return core.hresult.S_OK;
        }

        fn getAt(this: *const interfaces.IVector(T), index: u32, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            defer state.mutex.unlock();
            if (index >= state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, state.values.items[index], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const interfaces.IVector(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = @intCast(state.values.items.len);
            return core.hresult.S_OK;
        }

        fn getView(this: *const interfaces.IVector(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = cloneStoredSlice(T, storage.allocator, state.values.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const view_storage = VectorViewAuthor(T).create(storage.allocator, .{ .values = snapshot }) catch |err| {
                var values = snapshot;
                deinitValues(T, storage.allocator, &values);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(VectorViewAuthor(T).as(view_storage, interfaces.IVectorView(T)));
            return core.hresult.S_OK;
        }

        fn indexOf(this: *const interfaces.IVector(T), value: abi.BufferElement(T), index: *u32, result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(index)) |hr| return hr;
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            const needle = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);

            state.mutex.lock();
            defer state.mutex.unlock();

            for (state.values.items, 0..) |item, i| {
                if (abi.equalsStoredInput(T, item, needle)) {
                    index.* = @intCast(i);
                    result.* = core.boolToWin32(true);
                    return core.hresult.S_OK;
                }
            }

            index.* = 0;
            result.* = core.boolToWin32(false);
            return core.hresult.S_OK;
        }

        fn setAt(this: *const interfaces.IVector(T), index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            if (index >= state.values.items.len) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            var old = state.values.items[index];
            state.values.items[index] = cloned;
            state.mutex.unlock();
            abi.releaseStored(T, &old);
            return core.hresult.S_OK;
        }

        fn insertAt(this: *const interfaces.IVector(T), index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            defer state.mutex.unlock();
            if (index > state.values.items.len) return interfaces.E_BOUNDS;
            state.values.insert(storage.allocator, index, cloned) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn removeAt(this: *const interfaces.IVector(T), index: u32) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            if (index >= state.values.items.len) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            var removed = state.values.orderedRemove(index);
            state.mutex.unlock();
            abi.releaseStored(T, &removed);
            return core.hresult.S_OK;
        }

        fn append(this: *const interfaces.IVector(T), value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            defer state.mutex.unlock();
            state.values.append(storage.allocator, cloned) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn removeAtEnd(this: *const interfaces.IVector(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            const removed_opt = state.values.pop();
            if (removed_opt == null) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            var removed = removed_opt.?;
            state.mutex.unlock();
            abi.releaseStored(T, &removed);
            return core.hresult.S_OK;
        }

        fn clear(this: *const interfaces.IVector(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const emptied = ValuesList(T).initCapacity(storage.allocator, 0) catch return core.hresult.E_OUTOFMEMORY;
            state.mutex.lock();
            var removed = state.values;
            state.values = emptied;
            state.mutex.unlock();
            deinitValues(T, storage.allocator, &removed);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IVector(T), start_index: u32, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = fillValues(T, state.values.items, start_index, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn replaceAll(this: *const interfaces.IVector(T), items_size: u32, items_ptr: [*]const abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const inputs = items_ptr[0..items_size];
            var replacements = cloneAbiSlice(T, storage.allocator, inputs) catch |err| return abi.toHRESULT(err);
            errdefer deinitValues(T, storage.allocator, &replacements);

            state.mutex.lock();
            var old_values = state.values;
            state.values = replacements;
            state.mutex.unlock();
            deinitValues(T, storage.allocator, &old_values);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn ObservableVectorState(comptime T: type) type {
    return struct {
        mutex: Mutex = .{},
        values: ValuesList(T),
        handlers: HandlerList(interfaces.VectorChangedEventHandler(T)),
        pending_notifications: std.ArrayList(Notification),
        dispatching: bool = false,

        const Notification = struct {
            change: interfaces.CollectionChange,
            index: u32,
        };

        fn enqueue(self: *@This(), allocator: std.mem.Allocator, change: interfaces.CollectionChange, index: u32) abi.CollectionError!bool {
            try self.pending_notifications.append(allocator, .{
                .change = change,
                .index = index,
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

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.pending_notifications.deinit(allocator);
            self.handlers.deinit(allocator);
            deinitValues(T, allocator, &self.values);
        }
    };
}

fn ObservableVectorIteratorState(comptime T: type) type {
    return struct {
        owner: *interfaces.IObservableVector(T),
        current: std.atomic.Value(usize),

        pub fn deinit(self: *@This()) void {
            _ = self.owner.Release();
        }
    };
}

fn ObservableVectorIteratorAuthor(comptime T: type) type {
    const Owner = interfaces.IObservableVector(T);
    const State = ObservableVectorIteratorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IIterator(T).NAME_W,
        }, .{
            core.interfaceSpec(interfaces.IIterator(T), .{
                .base = undefined,
                .get_Current = getCurrent,
                .get_HasCurrent = getHasCurrent,
                .MoveNext = moveNext,
                .GetMany = getMany,
            }),
        });

        fn getCurrent(this: *const interfaces.IIterator(T), result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = ObservableVectorAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            if (current >= owner_state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, owner_state.values.items[current], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getHasCurrent(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = ObservableVectorAuthor(T).stateFrom(Owner, state.owner);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            result.* = core.boolToWin32(state.current.load(.acquire) < owner_state.values.items.len);
            return core.hresult.S_OK;
        }

        fn moveNext(this: *const interfaces.IIterator(T), result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = ObservableVectorAuthor(T).stateFrom(Owner, state.owner);
            owner_state.mutex.lock();
            const current = state.current.load(.acquire);
            const len = owner_state.values.items.len;
            owner_state.mutex.unlock();
            if (current < len) _ = state.current.fetchAdd(1, .acq_rel);
            result.* = core.boolToWin32(len > current + 1);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IIterator(T), items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IIterator(T), this);
            const owner_state = ObservableVectorAuthor(T).stateFrom(Owner, state.owner);
            const current = state.current.load(.acquire);
            owner_state.mutex.lock();
            defer owner_state.mutex.unlock();
            const actual = fillValues(T, owner_state.values.items, current, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            _ = state.current.fetchAdd(actual, .acq_rel);
            result.* = actual;
            return core.hresult.S_OK;
        }
    }.Author;
}

fn ObservableVectorAuthor(comptime T: type) type {
    const State = ObservableVectorState(T);

    return struct {
        pub const Author = core.MultiInterfaceObject(State, .{
            .runtime_class_name = interfaces.IObservableVector(T).NAME_W,
            .agile = false,
        }, .{
            core.interfaceSpec(interfaces.IIterable(T), .{
                .base = undefined,
                .First = first,
            }),
            core.interfaceSpec(interfaces.IVector(T), .{
                .base = undefined,
                .GetAt = getAt,
                .get_Size = getSize,
                .GetView = getView,
                .IndexOf = indexOf,
                .SetAt = setAt,
                .InsertAt = insertAt,
                .RemoveAt = removeAt,
                .Append = append,
                .RemoveAtEnd = removeAtEnd,
                .Clear = clear,
                .GetMany = getMany,
                .ReplaceAll = replaceAll,
            }),
            core.interfaceSpec(interfaces.IObservableVector(T), .{
                .base = undefined,
                .add_VectorChanged = addVectorChanged,
                .remove_VectorChanged = removeVectorChanged,
            }),
        });

        fn fireChanged(storage: *Author.Storage, change: interfaces.CollectionChange, index: u32) core.HRESULT {
            var args = createVectorChangedArgs(storage.allocator, change, index) catch |err| return abi.toHRESULT(err);
            defer _ = args.Release();

            var snapshot = storage.state.handlers.snapshot(storage.allocator) catch |err| return abi.toHRESULT(err);
            defer {
                for (snapshot.items) |handler| abi.releaseAny(handler);
                snapshot.deinit(storage.allocator);
            }

            const sender = Author.as(storage, interfaces.IObservableVector(T));
            _ = sender.AddRef();
            defer _ = sender.Release();
            const sender_raw: *anyopaque = @ptrCast(sender);
            for (snapshot.items) |raw| {
                const handler: *const interfaces.VectorChangedEventHandler(T) = @ptrCast(@alignCast(raw));
                _ = handler.vtable.Invoke(handler, sender_raw, args);
            }

            return core.hresult.S_OK;
        }

        fn drainNotifications(storage: *Author.Storage) void {
            while (true) {
                storage.state.mutex.lock();
                const notification = storage.state.nextNotification();
                storage.state.mutex.unlock();
                const next = notification orelse break;
                _ = fireChanged(storage, next.change, next.index);
            }
        }

        fn first(this: *const interfaces.IIterable(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IIterable(T), this);
            const owner = Author.as(storage, interfaces.IObservableVector(T));
            _ = owner.AddRef();

            const iter_storage = ObservableVectorIteratorAuthor(T).create(storage.allocator, .{
                .owner = owner,
                .current = std.atomic.Value(usize).init(0),
            }) catch {
                _ = owner.Release();
                return core.hresult.E_OUTOFMEMORY;
            };

            result.* = @ptrCast(ObservableVectorIteratorAuthor(T).as(iter_storage, interfaces.IIterator(T)));
            return core.hresult.S_OK;
        }

        fn getAt(this: *const interfaces.IVector(T), index: u32, result: *abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            state.mutex.lock();
            defer state.mutex.unlock();
            if (index >= state.values.items.len) return interfaces.E_BOUNDS;
            abi.fillAbiClone(T, state.values.items[index], result) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn getSize(this: *const interfaces.IVector(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = @intCast(state.values.items.len);
            return core.hresult.S_OK;
        }

        fn getView(this: *const interfaces.IVector(T), result: **anyopaque) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            state.mutex.lock();
            const snapshot = cloneStoredSlice(T, storage.allocator, state.values.items) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            state.mutex.unlock();

            const view_storage = VectorViewAuthor(T).create(storage.allocator, .{ .values = snapshot }) catch |err| {
                var values = snapshot;
                deinitValues(T, storage.allocator, &values);
                return abi.toHRESULT(err);
            };

            result.* = @ptrCast(VectorViewAuthor(T).as(view_storage, interfaces.IVectorView(T)));
            return core.hresult.S_OK;
        }

        fn indexOf(this: *const interfaces.IVector(T), value: abi.BufferElement(T), index: *u32, result: *core.BOOL) callconv(.winapi) core.HRESULT {
            if (guardOut(index)) |hr| return hr;
            if (guardOut(result)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            const needle = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);

            state.mutex.lock();
            defer state.mutex.unlock();

            for (state.values.items, 0..) |item, i| {
                if (abi.equalsStoredInput(T, item, needle)) {
                    index.* = @intCast(i);
                    result.* = core.boolToWin32(true);
                    return core.hresult.S_OK;
                }
            }

            index.* = 0;
            result.* = core.boolToWin32(false);
            return core.hresult.S_OK;
        }

        fn setAt(this: *const interfaces.IVector(T), index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            if (index >= state.values.items.len) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            var old = state.values.items[index];
            state.values.items[index] = cloned;
            const should_dispatch = state.enqueue(storage.allocator, .ItemChanged, index) catch {
                state.mutex.unlock();
                abi.releaseStored(T, &old);
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            abi.releaseStored(T, &old);

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn insertAt(this: *const interfaces.IVector(T), index: u32, value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            if (index > state.values.items.len) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            state.values.insert(storage.allocator, index, cloned) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            const should_dispatch = state.enqueue(storage.allocator, .ItemInserted, index) catch {
                state.mutex.unlock();
                return core.hresult.S_OK;
            };
            state.mutex.unlock();

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn removeAt(this: *const interfaces.IVector(T), index: u32) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;

            state.mutex.lock();
            if (index >= state.values.items.len) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            }
            var removed = state.values.orderedRemove(index);
            const should_dispatch = state.enqueue(storage.allocator, .ItemRemoved, index) catch {
                state.mutex.unlock();
                abi.releaseStored(T, &removed);
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            abi.releaseStored(T, &removed);

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn append(this: *const interfaces.IVector(T), value: abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const incoming = abi.borrowedAbiValue(T, value) catch |err| return abi.toHRESULT(err);
            var cloned = abi.cloneInput(T, incoming) catch |err| return abi.toHRESULT(err);
            errdefer abi.releaseStored(T, &cloned);

            state.mutex.lock();
            state.values.append(storage.allocator, cloned) catch |err| {
                state.mutex.unlock();
                return abi.toHRESULT(err);
            };
            const index: u32 = @intCast(state.values.items.len - 1);
            const should_dispatch = state.enqueue(storage.allocator, .ItemInserted, index) catch {
                state.mutex.unlock();
                return core.hresult.S_OK;
            };
            state.mutex.unlock();

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn removeAtEnd(this: *const interfaces.IVector(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;

            state.mutex.lock();
            const index: u32 = if (state.values.items.len == 0) {
                state.mutex.unlock();
                return interfaces.E_BOUNDS;
            } else @intCast(state.values.items.len - 1);
            var removed = state.values.pop().?;
            const should_dispatch = state.enqueue(storage.allocator, .ItemRemoved, index) catch {
                state.mutex.unlock();
                abi.releaseStored(T, &removed);
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            abi.releaseStored(T, &removed);

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn clear(this: *const interfaces.IVector(T)) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const emptied = ValuesList(T).initCapacity(storage.allocator, 0) catch return core.hresult.E_OUTOFMEMORY;
            state.mutex.lock();
            var removed = state.values;
            state.values = emptied;
            const should_dispatch = state.enqueue(storage.allocator, .Reset, 0) catch {
                state.mutex.unlock();
                state.values = removed;
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            deinitValues(T, storage.allocator, &removed);
            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn getMany(this: *const interfaces.IVector(T), start_index: u32, items_size: u32, items_ptr: [*]abi.BufferElement(T), result: *u32) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const state = Author.stateFrom(interfaces.IVector(T), this);
            state.mutex.lock();
            defer state.mutex.unlock();
            result.* = fillValues(T, state.values.items, start_index, items_ptr[0..items_size]) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn replaceAll(this: *const interfaces.IVector(T), items_size: u32, items_ptr: [*]const abi.BufferElement(T)) callconv(.winapi) core.HRESULT {
            if (guardBuffer(items_size, items_ptr)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IVector(T), this);
            const state = &storage.state;
            const inputs = items_ptr[0..items_size];
            var replacements = cloneAbiSlice(T, storage.allocator, inputs) catch |err| return abi.toHRESULT(err);
            errdefer deinitValues(T, storage.allocator, &replacements);

            state.mutex.lock();
            var old_values = state.values;
            state.values = replacements;
            const should_dispatch = state.enqueue(storage.allocator, .Reset, 0) catch {
                var rolled_back = replacements;
                state.mutex.unlock();
                state.values = old_values;
                deinitValues(T, storage.allocator, &rolled_back);
                return core.hresult.S_OK;
            };
            state.mutex.unlock();
            deinitValues(T, storage.allocator, &old_values);

            if (should_dispatch) drainNotifications(storage);
            return core.hresult.S_OK;
        }

        fn addVectorChanged(this: *const interfaces.IObservableVector(T), handler: *anyopaque, result: *interfaces.EventRegistrationToken) callconv(.winapi) core.HRESULT {
            if (guardOut(result)) |hr| return hr;
            const storage = Author.storageFrom(interfaces.IObservableVector(T), this);
            result.* = storage.state.handlers.add(storage.allocator, handler) catch |err| return abi.toHRESULT(err);
            return core.hresult.S_OK;
        }

        fn removeVectorChanged(this: *const interfaces.IObservableVector(T), token: interfaces.EventRegistrationToken) callconv(.winapi) core.HRESULT {
            const storage = Author.storageFrom(interfaces.IObservableVector(T), this);
            storage.state.handlers.remove(token);
            return core.hresult.S_OK;
        }
    }.Author;
}

fn cloneStoredSlice(comptime T: type, allocator: std.mem.Allocator, items: []const abi.StoredType(T)) abi.CollectionError!ValuesList(T) {
    var values = try ValuesList(T).initCapacity(allocator, items.len);
    errdefer deinitValues(T, allocator, &values);
    for (items) |item| {
        var cloned = try abi.cloneStored(T, item);
        errdefer abi.releaseStored(T, &cloned);
        try values.append(allocator, cloned);
    }
    return values;
}

fn cloneAbiSlice(comptime T: type, allocator: std.mem.Allocator, items: []const abi.BufferElement(T)) abi.CollectionError!ValuesList(T) {
    var values = try ValuesList(T).initCapacity(allocator, items.len);
    errdefer deinitValues(T, allocator, &values);
    for (items) |item| {
        const incoming = try abi.borrowedAbiValue(T, item);
        var cloned = try abi.cloneInput(T, incoming);
        errdefer abi.releaseStored(T, &cloned);
        try values.append(allocator, cloned);
    }
    return values;
}

pub fn createIterable(comptime T: type, allocator: std.mem.Allocator, items: []const T) abi.CollectionError!*interfaces.IIterable(T) {
    var values = try cloneValues(T, allocator, items);
    errdefer deinitValues(T, allocator, &values);
    const storage = try IterableAuthor(T).create(allocator, .{
        .values = values,
    });
    return IterableAuthor(T).as(storage, interfaces.IIterable(T));
}

pub fn createVectorView(comptime T: type, allocator: std.mem.Allocator, items: []const T) abi.CollectionError!*interfaces.IVectorView(T) {
    var values = try cloneValues(T, allocator, items);
    errdefer deinitValues(T, allocator, &values);
    const storage = try VectorViewAuthor(T).create(allocator, .{
        .values = values,
    });
    return VectorViewAuthor(T).as(storage, interfaces.IVectorView(T));
}

pub fn createVector(comptime T: type, allocator: std.mem.Allocator, items: []const T) abi.CollectionError!*interfaces.IVector(T) {
    var values = try cloneValues(T, allocator, items);
    errdefer deinitValues(T, allocator, &values);
    const storage = try VectorAuthor(T).create(allocator, .{
        .values = values,
    });
    return VectorAuthor(T).as(storage, interfaces.IVector(T));
}

pub fn createObservableVector(comptime T: type, allocator: std.mem.Allocator, items: []const T) abi.CollectionError!*interfaces.IObservableVector(T) {
    var values = try cloneValues(T, allocator, items);
    errdefer deinitValues(T, allocator, &values);
    var handlers = try HandlerList(interfaces.VectorChangedEventHandler(T)).init(allocator);
    errdefer handlers.deinit(allocator);
    var pending_notifications = try std.ArrayList(ObservableVectorState(T).Notification).initCapacity(allocator, 0);
    errdefer pending_notifications.deinit(allocator);
    const storage = try ObservableVectorAuthor(T).create(allocator, .{
        .values = values,
        .handlers = handlers,
        .pending_notifications = pending_notifications,
    });
    return ObservableVectorAuthor(T).as(storage, interfaces.IObservableVector(T));
}
