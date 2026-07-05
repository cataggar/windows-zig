//! `win-time` — hand-written WinRT time value types.
//!
//! Ports the `windows-time` `DateTime` and `TimeSpan` helpers to Zig while
//! staying ABI-compatible with the WinRT 100-nanosecond tick layouts.

pub const TimeRangeError = @import("timespan.zig").TimeRangeError;
pub const TimeSpan = @import("timespan.zig").TimeSpan;
pub const DateTime = @import("datetime.zig").DateTime;

test {
    _ = @import("timespan.zig");
    _ = @import("datetime.zig");
}
