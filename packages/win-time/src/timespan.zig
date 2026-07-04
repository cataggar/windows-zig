const std = @import("std");
const math = std.math;

pub const TimeRangeError = error{OutOfRange};

pub const TimeSpan = extern struct {
    const Self = @This();

    Duration: i64,

    pub const ticks_per_microsecond: i64 = 10;
    pub const ticks_per_millisecond: i64 = 10_000;
    pub const ticks_per_second: i64 = 10_000_000;
    pub const ticks_per_minute: i64 = ticks_per_second * 60;
    pub const ticks_per_hour: i64 = ticks_per_minute * 60;
    pub const ticks_per_day: i64 = ticks_per_hour * 24;

    pub const zero: Self = .{ .Duration = 0 };
    pub const min: Self = .{ .Duration = math.minInt(i64) };
    pub const max: Self = .{ .Duration = math.maxInt(i64) };

    pub fn fromTicks(raw_ticks: i64) Self {
        return .{ .Duration = raw_ticks };
    }

    pub fn fromMicros(micros: i64) Self {
        return .{ .Duration = micros *| ticks_per_microsecond };
    }

    pub fn fromMillis(millis: i64) Self {
        return .{ .Duration = millis *| ticks_per_millisecond };
    }

    pub fn fromSeconds(seconds: i64) Self {
        return .{ .Duration = seconds *| ticks_per_second };
    }

    pub fn fromMinutes(minutes: i64) Self {
        return .{ .Duration = minutes *| ticks_per_minute };
    }

    pub fn fromHours(hours: i64) Self {
        return .{ .Duration = hours *| ticks_per_hour };
    }

    pub fn fromDays(days: i64) Self {
        return .{ .Duration = days *| ticks_per_day };
    }

    pub fn fromIoDuration(duration: std.Io.Duration) TimeRangeError!Self {
        const tick_count = @divTrunc(duration.toNanoseconds(), 100);
        if (tick_count < @as(i96, math.minInt(i64)) or tick_count > @as(i96, math.maxInt(i64))) {
            return TimeRangeError.OutOfRange;
        }
        return .{ .Duration = @intCast(tick_count) };
    }

    pub fn ticks(self: Self) i64 {
        return self.Duration;
    }

    pub fn wholeMicros(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_microsecond);
    }

    pub fn wholeMillis(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_millisecond);
    }

    pub fn wholeSeconds(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_second);
    }

    pub fn wholeMinutes(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_minute);
    }

    pub fn wholeHours(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_hour);
    }

    pub fn wholeDays(self: Self) i64 {
        return @divTrunc(self.Duration, ticks_per_day);
    }

    pub fn wholeNanos(self: Self) i128 {
        return @as(i128, self.Duration) * 100;
    }

    pub fn isZero(self: Self) bool {
        return self.Duration == 0;
    }

    pub fn isNegative(self: Self) bool {
        return self.Duration < 0;
    }

    pub fn isPositive(self: Self) bool {
        return self.Duration > 0;
    }

    pub fn abs(self: Self) Self {
        return if (self.Duration < 0) self.saturatingNeg() else self;
    }

    pub fn signum(self: Self) i64 {
        return if (self.Duration > 0) 1 else if (self.Duration < 0) -1 else 0;
    }

    pub fn checkedAdd(self: Self, rhs: Self) ?Self {
        const sum = @addWithOverflow(self.Duration, rhs.Duration);
        if (sum[1] != 0) return null;
        return .{ .Duration = sum[0] };
    }

    pub fn checkedSub(self: Self, rhs: Self) ?Self {
        const diff = @subWithOverflow(self.Duration, rhs.Duration);
        if (diff[1] != 0) return null;
        return .{ .Duration = diff[0] };
    }

    pub fn checkedNeg(self: Self) ?Self {
        if (self.Duration == math.minInt(i64)) return null;
        return .{ .Duration = -self.Duration };
    }

    pub fn checkedMul(self: Self, rhs: i64) ?Self {
        const product = @mulWithOverflow(self.Duration, rhs);
        if (product[1] != 0) return null;
        return .{ .Duration = product[0] };
    }

    pub fn checkedDiv(self: Self, rhs: i64) ?Self {
        const quotient = std.math.divTrunc(i64, self.Duration, rhs) catch return null;
        return .{ .Duration = quotient };
    }

    pub fn saturatingAdd(self: Self, rhs: Self) Self {
        return .{ .Duration = self.Duration +| rhs.Duration };
    }

    pub fn saturatingSub(self: Self, rhs: Self) Self {
        return .{ .Duration = self.Duration -| rhs.Duration };
    }

    pub fn saturatingNeg(self: Self) Self {
        return .{ .Duration = @as(i64, 0) -| self.Duration };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return self.checkedAdd(rhs) orelse @panic("overflow when adding TimeSpan values");
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return self.checkedSub(rhs) orelse @panic("overflow when subtracting TimeSpan values");
    }

    pub fn neg(self: Self) Self {
        return self.checkedNeg() orelse @panic("overflow when negating TimeSpan value");
    }

    pub fn mul(self: Self, rhs: i64) Self {
        return self.checkedMul(rhs) orelse @panic("overflow when multiplying TimeSpan value");
    }

    pub fn div(self: Self, rhs: i64) Self {
        return self.checkedDiv(rhs) orelse if (rhs == 0)
            @panic("attempt to divide TimeSpan by zero")
        else
            @panic("overflow when dividing TimeSpan value");
    }

    pub fn addAssign(self: *Self, rhs: Self) void {
        self.* = self.add(rhs);
    }

    pub fn subAssign(self: *Self, rhs: Self) void {
        self.* = self.sub(rhs);
    }

    pub fn toIoDuration(self: Self) std.Io.Duration {
        return std.Io.Duration.fromNanoseconds(@as(i96, self.Duration) * 100);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.Duration == 0) {
            return writer.writeAll("PT0S");
        }

        const signed_ticks = @as(i128, self.Duration);
        const tick_count: u128 = if (signed_ticks < 0)
            @intCast(-signed_ticks)
        else
            @intCast(signed_ticks);
        const ticks_per_second_u: u128 = @intCast(ticks_per_second);

        if (self.Duration < 0) try writer.writeByte('-');
        try writer.writeByte('P');

        const total_seconds = tick_count / ticks_per_second_u;
        const fraction: u32 = @intCast(tick_count % ticks_per_second_u);
        const days = total_seconds / 86_400;
        const rem_after_days = total_seconds % 86_400;
        const hours = rem_after_days / 3_600;
        const rem_after_hours = rem_after_days % 3_600;
        const minutes = rem_after_hours / 60;
        const seconds = rem_after_hours % 60;

        if (days != 0) {
            try writer.print("{d}D", .{days});
        }

        const need_time = hours != 0 or minutes != 0 or seconds != 0 or fraction != 0 or days == 0;
        if (!need_time) return;

        try writer.writeByte('T');
        if (hours != 0) {
            try writer.print("{d}H", .{hours});
        }
        if (minutes != 0) {
            try writer.print("{d}M", .{minutes});
        }
        if (seconds != 0 or fraction != 0 or (hours == 0 and minutes == 0)) {
            try writer.print("{d}", .{seconds});
            try writeFraction(writer, fraction);
            try writer.writeByte('S');
        }
    }
};

fn writeFraction(writer: *std.Io.Writer, fraction: u32) std.Io.Writer.Error!void {
    if (fraction == 0) return;

    var digits: [7]u8 = undefined;
    var value = fraction;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        digits[i] = '0' + @as(u8, @intCast(@mod(value, 10)));
        value = @divTrunc(value, 10);
    }

    var len: usize = digits.len;
    while (len > 0 and digits[len - 1] == '0') : (len -= 1) {}

    try writer.writeByte('.');
    try writer.writeAll(digits[0..len]);
}

test "TimeSpan constructors and accessors" {
    try std.testing.expectEqual(@as(i64, 123), TimeSpan.fromTicks(123).ticks());
    try std.testing.expectEqual(@as(i64, 12), TimeSpan.fromMicros(12).wholeMicros());
    try std.testing.expectEqual(@as(i64, 34), TimeSpan.fromMillis(34).wholeMillis());
    try std.testing.expectEqual(@as(i64, 56), TimeSpan.fromSeconds(56).wholeSeconds());
    try std.testing.expectEqual(@as(i64, 78), TimeSpan.fromMinutes(78).wholeMinutes());
    try std.testing.expectEqual(@as(i64, 9), TimeSpan.fromHours(9).wholeHours());
    try std.testing.expectEqual(@as(i64, 3), TimeSpan.fromDays(3).wholeDays());
    try std.testing.expectEqual(@as(i128, -123_400), TimeSpan.fromTicks(-1_234).wholeNanos());
}

test "TimeSpan constructor saturation" {
    try std.testing.expectEqual(TimeSpan.max, TimeSpan.fromDays(math.maxInt(i64)));
    try std.testing.expectEqual(TimeSpan.min, TimeSpan.fromDays(math.minInt(i64)));
    try std.testing.expectEqual(TimeSpan.max, TimeSpan.fromMicros(math.maxInt(i64)));
    try std.testing.expectEqual(TimeSpan.min, TimeSpan.fromMillis(math.minInt(i64)));
}

test "TimeSpan sign helpers" {
    try std.testing.expect(TimeSpan.zero.isZero());
    try std.testing.expect(!TimeSpan.zero.isPositive());
    try std.testing.expect(!TimeSpan.zero.isNegative());
    try std.testing.expect(TimeSpan.fromTicks(1).isPositive());
    try std.testing.expect(TimeSpan.fromTicks(-1).isNegative());
    try std.testing.expectEqual(@as(i64, 1), TimeSpan.fromTicks(99).signum());
    try std.testing.expectEqual(@as(i64, -1), TimeSpan.fromTicks(-99).signum());
    try std.testing.expectEqual(@as(i64, 0), TimeSpan.zero.signum());
    try std.testing.expectEqual(TimeSpan.fromTicks(5), TimeSpan.fromTicks(-5).abs());
    try std.testing.expectEqual(TimeSpan.max, TimeSpan.min.abs());
}

test "TimeSpan checked arithmetic" {
    try std.testing.expectEqual(
        TimeSpan.fromSeconds(3),
        TimeSpan.fromSeconds(1).checkedAdd(TimeSpan.fromSeconds(2)).?,
    );
    try std.testing.expectEqual(
        TimeSpan.fromSeconds(-1),
        TimeSpan.fromSeconds(1).checkedSub(TimeSpan.fromSeconds(2)).?,
    );
    try std.testing.expectEqual(TimeSpan.fromTicks(5), TimeSpan.fromTicks(-5).checkedNeg().?);
    try std.testing.expectEqual(TimeSpan.fromSeconds(6), TimeSpan.fromSeconds(2).checkedMul(3).?);
    try std.testing.expectEqual(TimeSpan.fromSeconds(2), TimeSpan.fromSeconds(6).checkedDiv(3).?);

    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.max.checkedAdd(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.min.checkedSub(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.min.checkedNeg());
    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.max.checkedMul(2));
    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.fromTicks(1).checkedDiv(0));
    try std.testing.expectEqual(@as(?TimeSpan, null), TimeSpan.min.checkedDiv(-1));
}

test "TimeSpan saturating arithmetic" {
    try std.testing.expectEqual(TimeSpan.max, TimeSpan.max.saturatingAdd(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(TimeSpan.min, TimeSpan.min.saturatingSub(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(TimeSpan.max, TimeSpan.min.saturatingNeg());
}

test "TimeSpan assign helpers" {
    var span = TimeSpan.fromSeconds(1);
    span.addAssign(TimeSpan.fromSeconds(2));
    try std.testing.expectEqual(TimeSpan.fromSeconds(3), span);
    span.subAssign(TimeSpan.fromSeconds(1));
    try std.testing.expectEqual(TimeSpan.fromSeconds(2), span);
}

test "TimeSpan formatting" {
    try std.testing.expectFmt("PT0S", "{f}", .{TimeSpan.zero});
    try std.testing.expectFmt("P2D", "{f}", .{TimeSpan.fromDays(2)});
    try std.testing.expectFmt("PT1H30M", "{f}", .{TimeSpan.fromMinutes(90)});
    try std.testing.expectFmt("P1DT2H3M4.5S", "{f}", .{
        TimeSpan.fromDays(1)
            .add(TimeSpan.fromHours(2))
            .add(TimeSpan.fromMinutes(3))
            .add(TimeSpan.fromSeconds(4))
            .add(TimeSpan.fromTicks(5_000_000)),
    });
    try std.testing.expectFmt("PT0.0000001S", "{f}", .{TimeSpan.fromTicks(1)});
    try std.testing.expectFmt("-PT0.0000001S", "{f}", .{TimeSpan.fromTicks(-1)});
}

test "TimeSpan Io.Duration conversions" {
    try std.testing.expectEqual(
        TimeSpan.fromTicks(12),
        try TimeSpan.fromIoDuration(std.Io.Duration.fromNanoseconds(1_299)),
    );
    try std.testing.expectEqual(
        @as(i96, -12_300),
        TimeSpan.fromTicks(-123).toIoDuration().toNanoseconds(),
    );
    try std.testing.expectEqual(TimeSpan.zero, try TimeSpan.fromIoDuration(std.Io.Duration.fromNanoseconds(-99)));

    const too_large = std.Io.Duration.fromNanoseconds((@as(i96, math.maxInt(i64)) + 1) * 100);
    const too_small = std.Io.Duration.fromNanoseconds((@as(i96, math.minInt(i64)) - 1) * 100);
    try std.testing.expectError(TimeRangeError.OutOfRange, TimeSpan.fromIoDuration(too_large));
    try std.testing.expectError(TimeRangeError.OutOfRange, TimeSpan.fromIoDuration(too_small));
}
