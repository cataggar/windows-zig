const std = @import("std");

pub const core = @import("win-core");

const abi = @import("abi.zig");
const interfaces = @import("interfaces.zig");
const buffered_iterator = @import("buffered_iterator.zig");
const stock_vector = @import("stock_vector.zig");
const stock_map = @import("stock_map.zig");

pub const CollectionError = abi.CollectionError;
pub const E_BOUNDS = interfaces.E_BOUNDS;
pub const EventRegistrationToken = interfaces.EventRegistrationToken;
pub const CollectionChange = interfaces.CollectionChange;
pub const IVectorChangedEventArgs = interfaces.IVectorChangedEventArgs;

pub const Entry = abi.Entry;
pub const BufferElement = abi.BufferElement;
pub const releaseValue = abi.releaseValue;
pub const releaseBuffer = abi.releaseBuffer;
pub const parameterizedIid = abi.parameterizedIid;
pub const signatureOf = abi.signatureOf;

pub const IIterable = interfaces.IIterable;
pub const IIterator = interfaces.IIterator;
pub const IVector = interfaces.IVector;
pub const IVectorView = interfaces.IVectorView;
pub const IObservableVector = interfaces.IObservableVector;
pub const VectorChangedEventHandler = interfaces.VectorChangedEventHandler;
pub const IKeyValuePair = interfaces.IKeyValuePair;
pub const IMap = interfaces.IMap;
pub const IMapView = interfaces.IMapView;
pub const IObservableMap = interfaces.IObservableMap;
pub const IMapChangedEventArgs = interfaces.IMapChangedEventArgs;
pub const MapChangedEventHandler = interfaces.MapChangedEventHandler;

pub const BufferedIterator = buffered_iterator.BufferedIterator;

pub fn createIterable(comptime T: type, allocator: std.mem.Allocator, items: []const T) CollectionError!*IIterable(T) {
    return stock_vector.createIterable(T, allocator, items);
}

pub fn createVectorView(comptime T: type, allocator: std.mem.Allocator, items: []const T) CollectionError!*IVectorView(T) {
    return stock_vector.createVectorView(T, allocator, items);
}

pub fn createVector(comptime T: type, allocator: std.mem.Allocator, items: []const T) CollectionError!*IVector(T) {
    return stock_vector.createVector(T, allocator, items);
}

pub fn createObservableVector(comptime T: type, allocator: std.mem.Allocator, items: []const T) CollectionError!*IObservableVector(T) {
    return stock_vector.createObservableVector(T, allocator, items);
}

pub fn createMapView(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const Entry(K, V)) CollectionError!*IMapView(K, V) {
    return stock_map.createMapView(K, V, allocator, items);
}

pub fn createMap(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const Entry(K, V)) CollectionError!*IMap(K, V) {
    return stock_map.createMap(K, V, allocator, items);
}

pub fn createObservableMap(comptime K: type, comptime V: type, allocator: std.mem.Allocator, items: []const Entry(K, V)) CollectionError!*IObservableMap(K, V) {
    return stock_map.createObservableMap(K, V, allocator, items);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
