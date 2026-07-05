//! Port of `crates/samples/windows/samples/examples/counter.rs` —
//! reads CPU usage via Performance Data Helper (PDH) in a loop.
//!
//! Exercises: Win32 PDH APIs, generated handle aliases, and generated
//! `PDH_FMT_COUNTERVALUE` layout access.
//!
//! Build:  `zig build samples`
//! Run:    `zig build run-counter`

const std = @import("std");
const win_sys = @import("win-sys");

const win = win_sys.project(.{
    .@"Windows.Win32.System.Performance" = .{
        "PdhOpenQueryW",
        "PdhAddCounterW",
        "PdhCollectQueryData",
        "PdhGetFormattedCounterValue",
        "PdhCloseQuery",
    },
    .@"Windows.Win32.System.Threading" = .{"Sleep"},
});
const perf = win_sys.index.@"Windows.Win32.System.Performance";

pub fn main() !void {
    var query: perf.aliases.PDH_HQUERY = null;
    const open_status = win.PdhOpenQueryW(null, 0, &query);
    if (open_status != 0) {
        std.debug.print("PdhOpenQueryW failed: PDH_STATUS = 0x{x:0>8}\n", .{open_status});
        return error.PdhOpenQueryFailed;
    }
    defer _ = win.PdhCloseQuery(query);

    const counter_path_literal = std.unicode.utf8ToUtf16LeStringLiteral(
        "\\Processor(0)\\% Processor Time",
    );
    const counter_path: ?[*:0]u16 =
        @constCast(@as([*:0]const u16, counter_path_literal));

    var counter: perf.aliases.PDH_HCOUNTER = null;
    const add_status = win.PdhAddCounterW(query, counter_path, 0, &counter);
    if (add_status != 0) {
        std.debug.print("PdhAddCounterW failed: PDH_STATUS = 0x{x:0>8}\n", .{add_status});
        return error.PdhAddCounterFailed;
    }

    // Rate counters need a baseline sample before the first formatted read.
    const initial_collect_status = win.PdhCollectQueryData(query);
    if (initial_collect_status != 0) {
        std.debug.print(
            "Initial PdhCollectQueryData failed: PDH_STATUS = 0x{x:0>8}\n",
            .{initial_collect_status},
        );
        return error.PdhCollectQueryDataFailed;
    }

    std.debug.print("Reading CPU usage...\n", .{});

    var sample_index: u32 = 0;
    while (sample_index < 10) : (sample_index += 1) {
        win.Sleep(1000);

        const collect_status = win.PdhCollectQueryData(query);
        if (collect_status != 0) {
            std.debug.print(
                "PdhCollectQueryData failed: PDH_STATUS = 0x{x:0>8}\n",
                .{collect_status},
            );
            return error.PdhCollectQueryDataFailed;
        }

        var value = std.mem.zeroes(win_sys.structs.PDH_FMT_COUNTERVALUE);
        const format_status = win.PdhGetFormattedCounterValue(
            counter,
            perf.PDH_FMT_DOUBLE,
            null,
            &value,
        );
        if (format_status != 0) {
            std.debug.print(
                "PdhGetFormattedCounterValue failed: PDH_STATUS = 0x{x:0>8}\n",
                .{format_status},
            );
            return error.PdhGetFormattedCounterValueFailed;
        }

        std.debug.print("{d:.2}%\n", .{value.Anonymous.doubleValue});
    }
}
