const std = @import("std");
const math = std.math;
const win_sys = @import("win-sys");

const TimeRangeError = @import("timespan.zig").TimeRangeError;
const TimeSpan = @import("timespan.zig").TimeSpan;

const FILETIME = win_sys.structs.FILETIME;
const file_time_api = win_sys.project(.{
    .@"Windows.Win32.Storage.FileSystem" = .{"FileTimeToLocalFileTime"},
});

const unix_epoch_difference_secs_value: i64 = 11_644_473_600;
const unix_epoch_ticks: i64 = unix_epoch_difference_secs_value * TimeSpan.ticks_per_second;

pub const DateTime = extern struct {
    const Self = @This();

    UniversalTime: i64,

    pub const unix_epoch_difference_secs: i64 = unix_epoch_difference_secs_value;
    pub const unix_epoch: Self = .{ .UniversalTime = unix_epoch_ticks };
    pub const min: Self = .{ .UniversalTime = math.minInt(i64) };
    pub const max: Self = .{ .UniversalTime = math.maxInt(i64) };
    pub const ticks_per_second: i64 = TimeSpan.ticks_per_second;

    pub fn fromTicks(raw_ticks: i64) Self {
        return .{ .UniversalTime = raw_ticks };
    }

    pub fn fromUnixSecs(secs: i64) Self {
        const total = secs +| unix_epoch_difference_secs;
        return .{ .UniversalTime = total *| ticks_per_second };
    }

    pub fn fromUnixMillis(millis: i64) Self {
        const unix_ticks = millis *| TimeSpan.ticks_per_millisecond;
        return .{ .UniversalTime = unix_ticks +| unix_epoch_ticks };
    }

    pub fn fromIoTimestamp(timestamp: std.Io.Timestamp) TimeRangeError!Self {
        const unix_ticks = @divTrunc(timestamp.toNanoseconds(), 100);
        const total_ticks = unix_ticks + @as(i96, unix_epoch_ticks);
        if (total_ticks < @as(i96, math.minInt(i64)) or total_ticks > @as(i96, math.maxInt(i64))) {
            return TimeRangeError.OutOfRange;
        }
        return .{ .UniversalTime = @intCast(total_ticks) };
    }

    pub fn now(io: std.Io) Self {
        return Self.fromIoTimestamp(std.Io.Clock.real.now(io)) catch max;
    }

    pub fn ticks(self: Self) i64 {
        return self.UniversalTime;
    }

    pub fn unixSecs(self: Self) i64 {
        return @divTrunc(self.UniversalTime, ticks_per_second) - unix_epoch_difference_secs;
    }

    pub fn unixMillis(self: Self) i64 {
        return @divTrunc(self.UniversalTime, TimeSpan.ticks_per_millisecond) - unix_epoch_difference_secs * 1_000;
    }

    pub fn unixNanos(self: Self) i128 {
        return @as(i128, self.UniversalTime) * 100 -
            @as(i128, unix_epoch_difference_secs) * std.time.ns_per_s;
    }

    pub fn checkedAdd(self: Self, rhs: TimeSpan) ?Self {
        const sum = @addWithOverflow(self.UniversalTime, rhs.Duration);
        if (sum[1] != 0) return null;
        return .{ .UniversalTime = sum[0] };
    }

    pub fn checkedSub(self: Self, rhs: TimeSpan) ?Self {
        const diff = @subWithOverflow(self.UniversalTime, rhs.Duration);
        if (diff[1] != 0) return null;
        return .{ .UniversalTime = diff[0] };
    }

    pub fn checkedDurationSince(self: Self, earlier: Self) ?TimeSpan {
        const diff = @subWithOverflow(self.UniversalTime, earlier.UniversalTime);
        if (diff[1] != 0) return null;
        return .{ .Duration = diff[0] };
    }

    pub fn saturatingAdd(self: Self, rhs: TimeSpan) Self {
        return .{ .UniversalTime = self.UniversalTime +| rhs.Duration };
    }

    pub fn saturatingSub(self: Self, rhs: TimeSpan) Self {
        return .{ .UniversalTime = self.UniversalTime -| rhs.Duration };
    }

    pub fn add(self: Self, rhs: TimeSpan) Self {
        return self.checkedAdd(rhs) orelse @panic("overflow when adding TimeSpan to DateTime");
    }

    pub fn sub(self: Self, rhs: TimeSpan) Self {
        return self.checkedSub(rhs) orelse @panic("overflow when subtracting TimeSpan from DateTime");
    }

    pub fn durationSince(self: Self, earlier: Self) TimeSpan {
        return self.checkedDurationSince(earlier) orelse @panic("overflow when subtracting DateTime values");
    }

    pub fn addAssign(self: *Self, rhs: TimeSpan) void {
        self.* = self.add(rhs);
    }

    pub fn subAssign(self: *Self, rhs: TimeSpan) void {
        self.* = self.sub(rhs);
    }

    pub fn toIoTimestamp(self: Self) std.Io.Timestamp {
        const unix_ticks = @as(i96, self.UniversalTime) - @as(i96, unix_epoch_ticks);
        return std.Io.Timestamp.fromNanoseconds(unix_ticks * 100);
    }

    pub fn toLocal(self: Self) Self {
        var utc = toFileTime(self.UniversalTime);
        var local: FILETIME = undefined;
        std.debug.assert(file_time_api.FileTimeToLocalFileTime(&utc, &local) != 0);
        return .{ .UniversalTime = fromFileTime(local) };
    }

    pub fn year(self: Self) i64 {
        return self.decompose().year;
    }

    pub fn month(self: Self) u32 {
        return self.decompose().month;
    }

    pub fn day(self: Self) u32 {
        return self.decompose().day;
    }

    pub fn hour(self: Self) u32 {
        return self.decompose().hour;
    }

    pub fn minute(self: Self) u32 {
        return self.decompose().minute;
    }

    pub fn second(self: Self) u32 {
        return self.decompose().second;
    }

    pub fn milliseconds(self: Self) u32 {
        return self.decompose().millisecond;
    }

    pub fn dayOfWeek(self: Self) u32 {
        return self.decompose().day_of_week;
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const unix_ticks = @as(i128, self.UniversalTime) - @as(i128, unix_epoch_ticks);
        const ticks_per_day_i128 = @as(i128, TimeSpan.ticks_per_day);
        const days: i64 = @intCast(@divFloor(unix_ticks, ticks_per_day_i128));
        const intraday: i64 = @intCast(@mod(unix_ticks, ticks_per_day_i128));
        const date = civilFromDays(days);

        const secs = @divTrunc(intraday, ticks_per_second);
        const fraction: u32 = @intCast(@mod(intraday, ticks_per_second));
        const hour_value: u32 = @intCast(@divTrunc(secs, 3_600));
        const minute_value: u32 = @intCast(@divTrunc(@mod(secs, 3_600), 60));
        const second_value: u32 = @intCast(@mod(secs, 60));

        if (date.year < 0) {
            try writer.print("-{d:0>4}", .{@as(u64, @intCast(-date.year))});
        } else {
            try writer.print("{d:0>4}", .{@as(u64, @intCast(date.year))});
        }
        try writer.print("-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            date.month,
            date.day,
            hour_value,
            minute_value,
            second_value,
        });
        try writeFraction(writer, fraction);
        try writer.writeByte('Z');
    }

    fn decompose(self: Self) Components {
        const unix_ticks = @as(i128, self.UniversalTime) - @as(i128, unix_epoch_ticks);
        const ticks_per_day_i128 = @as(i128, TimeSpan.ticks_per_day);
        const days: i64 = @intCast(@divFloor(unix_ticks, ticks_per_day_i128));
        const intraday: i64 = @intCast(@mod(unix_ticks, ticks_per_day_i128));
        const date = civilFromDays(days);
        const secs = @divTrunc(intraday, ticks_per_second);
        const subsec_ticks: i64 = @mod(intraday, ticks_per_second);

        return .{
            .year = date.year,
            .month = date.month,
            .day = date.day,
            .hour = @intCast(@divTrunc(secs, 3_600)),
            .minute = @intCast(@divTrunc(@mod(secs, 3_600), 60)),
            .second = @intCast(@mod(secs, 60)),
            .millisecond = @intCast(@divTrunc(subsec_ticks, TimeSpan.ticks_per_millisecond)),
            .day_of_week = dayOfWeekFromDays(days),
        };
    }
};

const Components = struct {
    year: i64,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
    millisecond: u32,
    day_of_week: u32,
};

const CivilDate = struct {
    year: i64,
    month: u32,
    day: u32,
};

fn toFileTime(ticks: i64) FILETIME {
    const bits: u64 = @bitCast(ticks);
    return .{
        .dwLowDateTime = @truncate(bits),
        .dwHighDateTime = @truncate(bits >> 32),
    };
}

fn fromFileTime(filetime: FILETIME) i64 {
    const bits: u64 = @as(u64, filetime.dwLowDateTime) |
        (@as(u64, filetime.dwHighDateTime) << 32);
    return @bitCast(bits);
}

fn dayOfWeekFromDays(days: i64) u32 {
    return @intCast(@mod(days + 4, 7));
}

fn civilFromDays(z: i64) CivilDate {
    const shifted = z + 719_468;
    const era = @divFloor(shifted, 146_097);
    const doe: u64 = @intCast(shifted - era * 146_097);
    const yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    const y = @as(i64, @intCast(yoe)) + era * 400;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const day: u32 = @intCast(doy - (153 * mp + 2) / 5 + 1);
    const month: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{
        .year = if (month <= 2) y + 1 else y,
        .month = month,
        .day = day,
    };
}

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

test "DateTime unix conversions" {
    try std.testing.expectEqual(DateTime.unix_epoch, DateTime.fromUnixSecs(0));
    try std.testing.expectEqual(@as(i64, 1), DateTime.fromUnixSecs(1).unixSecs());
    try std.testing.expectEqual(@as(i64, -1), DateTime.fromUnixMillis(-1).unixMillis());
    try std.testing.expectEqual(
        @as(i128, 123_456_700),
        DateTime.fromTicks(unix_epoch_ticks + 1_234_567).unixNanos(),
    );
}

test "DateTime constructor saturation" {
    const max_unix_secs = @divFloor(math.maxInt(i64), DateTime.ticks_per_second) - DateTime.unix_epoch_difference_secs;
    const min_unix_secs = @divFloor(math.minInt(i64), DateTime.ticks_per_second) - DateTime.unix_epoch_difference_secs;
    try std.testing.expectEqual(DateTime.max, DateTime.fromUnixSecs(max_unix_secs + 1));
    try std.testing.expectEqual(DateTime.min, DateTime.fromUnixSecs(min_unix_secs - 1));
    try std.testing.expectEqual(DateTime.max, DateTime.fromUnixMillis(math.maxInt(i64)));
}

test "DateTime checked arithmetic" {
    const base = DateTime.fromUnixSecs(10);
    const plus = base.checkedAdd(TimeSpan.fromSeconds(2)).?;
    try std.testing.expectEqual(DateTime.fromUnixSecs(12), plus);
    try std.testing.expectEqual(DateTime.fromUnixSecs(8), base.checkedSub(TimeSpan.fromSeconds(2)).?);
    try std.testing.expectEqual(TimeSpan.fromSeconds(3), DateTime.fromUnixSecs(10).checkedDurationSince(DateTime.fromUnixSecs(7)).?);

    try std.testing.expectEqual(@as(?DateTime, null), DateTime.max.checkedAdd(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(@as(?DateTime, null), DateTime.min.checkedSub(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(@as(?TimeSpan, null), DateTime.max.checkedDurationSince(DateTime.min));
}

test "DateTime saturating arithmetic" {
    try std.testing.expectEqual(DateTime.max, DateTime.max.saturatingAdd(TimeSpan.fromTicks(1)));
    try std.testing.expectEqual(DateTime.min, DateTime.min.saturatingSub(TimeSpan.fromTicks(1)));
}

test "DateTime assign helpers" {
    var dt = DateTime.fromUnixSecs(1);
    dt.addAssign(TimeSpan.fromSeconds(2));
    try std.testing.expectEqual(DateTime.fromUnixSecs(3), dt);
    dt.subAssign(TimeSpan.fromSeconds(1));
    try std.testing.expectEqual(DateTime.fromUnixSecs(2), dt);
}

test "DateTime decomposition" {
    const epoch = DateTime.fromUnixSecs(0);
    try std.testing.expectEqual(@as(i64, 1970), epoch.year());
    try std.testing.expectEqual(@as(u32, 1), epoch.month());
    try std.testing.expectEqual(@as(u32, 1), epoch.day());
    try std.testing.expectEqual(@as(u32, 0), epoch.hour());
    try std.testing.expectEqual(@as(u32, 0), epoch.minute());
    try std.testing.expectEqual(@as(u32, 0), epoch.second());
    try std.testing.expectEqual(@as(u32, 0), epoch.milliseconds());
    try std.testing.expectEqual(@as(u32, 4), epoch.dayOfWeek());

    const leap_day = DateTime.fromUnixSecs(951_782_400);
    try std.testing.expectEqual(@as(i64, 2000), leap_day.year());
    try std.testing.expectEqual(@as(u32, 2), leap_day.month());
    try std.testing.expectEqual(@as(u32, 29), leap_day.day());

    const pre_epoch = DateTime.fromUnixMillis(-1);
    try std.testing.expectEqual(@as(i64, 1969), pre_epoch.year());
    try std.testing.expectEqual(@as(u32, 12), pre_epoch.month());
    try std.testing.expectEqual(@as(u32, 31), pre_epoch.day());
    try std.testing.expectEqual(@as(u32, 23), pre_epoch.hour());
    try std.testing.expectEqual(@as(u32, 59), pre_epoch.minute());
    try std.testing.expectEqual(@as(u32, 59), pre_epoch.second());
    try std.testing.expectEqual(@as(u32, 999), pre_epoch.milliseconds());
    try std.testing.expectEqual(@as(u32, 3), pre_epoch.dayOfWeek());
}

test "DateTime formatting" {
    try std.testing.expectFmt("1970-01-01T00:00:00Z", "{f}", .{DateTime.unix_epoch});
    try std.testing.expectFmt("1970-01-01T00:00:00.0000001Z", "{f}", .{DateTime.fromTicks(unix_epoch_ticks + 1)});
    try std.testing.expectFmt("1969-12-31T23:59:59.999Z", "{f}", .{DateTime.fromUnixMillis(-1)});
}

test "DateTime Io.Timestamp conversions" {
    const ts = std.Io.Timestamp.fromNanoseconds(1_234_567_890);
    const dt = try DateTime.fromIoTimestamp(ts);
    try std.testing.expectEqual(@as(i96, 1_234_567_800), dt.toIoTimestamp().toNanoseconds());

    const negative = try DateTime.fromIoTimestamp(std.Io.Timestamp.fromNanoseconds(-150));
    try std.testing.expectEqual(DateTime.unix_epoch.sub(TimeSpan.fromTicks(1)), negative);
    try std.testing.expectEqual(DateTime.unix_epoch, try DateTime.fromIoTimestamp(std.Io.Timestamp.fromNanoseconds(-99)));

    const before = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    const now = DateTime.now(std.testing.io).toIoTimestamp().toNanoseconds();
    const after = std.Io.Clock.real.now(std.testing.io).toNanoseconds();
    try std.testing.expect(now >= before - 99);
    try std.testing.expect(now <= after);

    const too_large_ticks = (@as(i96, math.maxInt(i64)) - @as(i96, unix_epoch_ticks) + 1) * 100;
    const too_small_ticks = (@as(i96, math.minInt(i64)) - @as(i96, unix_epoch_ticks) - 1) * 100;
    try std.testing.expectError(TimeRangeError.OutOfRange, DateTime.fromIoTimestamp(std.Io.Timestamp.fromNanoseconds(too_large_ticks)));
    try std.testing.expectError(TimeRangeError.OutOfRange, DateTime.fromIoTimestamp(std.Io.Timestamp.fromNanoseconds(too_small_ticks)));
}

test "DateTime local conversion preserves sub-second ticks" {
    const utc = DateTime.fromTicks(unix_epoch_ticks + 1_234_567);
    const local = utc.toLocal();
    try std.testing.expectEqual(@mod(utc.ticks(), TimeSpan.ticks_per_second), @mod(local.ticks(), TimeSpan.ticks_per_second));

    const offset = local.durationSince(utc);
    try std.testing.expect(offset.abs().wholeHours() <= 24);
    try std.testing.expectEqual(@as(i64, 0), @mod(offset.ticks(), TimeSpan.ticks_per_minute));

    _ = DateTime.min.toLocal();
    _ = DateTime.max.toLocal();
}
