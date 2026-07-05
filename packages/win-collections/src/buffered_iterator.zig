const abi = @import("abi.zig");
const interfaces = @import("interfaces.zig");

fn blockSize(comptime T: type) usize {
    const elem_size = @max(@sizeOf(abi.BufferElement(T)), 1);
    const by_bytes = 2048 / elem_size;
    return @max(@min(by_bytes, 128), 1);
}

pub fn BufferedIterator(comptime T: type) type {
    const Block = blockSize(T);

    return struct {
        const Self = @This();

        iterator: *interfaces.IIterator(T),
        buffer: [Block]abi.BufferElement(T) = std.mem.zeroes([Block]abi.BufferElement(T)),
        index: usize = 0,
        len: usize = 0,

        const std = @import("std");

        pub fn init(iterator: *interfaces.IIterator(T)) Self {
            return .{ .iterator = iterator };
        }

        pub fn deinit(self: *Self) void {
            if (self.len > self.index) {
                abi.releaseBuffer(T, self.buffer[self.index..self.len]);
            }
            _ = self.iterator.Release();
        }

        pub fn next(self: *Self) (@import("win-core").hresult.Error)!?T {
            if (self.index >= self.len) {
                if (self.len > self.index) {
                    abi.releaseBuffer(T, self.buffer[self.index..self.len]);
                }
                self.index = 0;
                self.len = @intCast(try self.iterator.GetMany(self.buffer[0..]));
                if (self.len == 0) {
                    return null;
                }
            }

            const value = try abi.takeAbiValue(T, &self.buffer[self.index]);
            self.index += 1;
            return value;
        }
    };
}
