const std = @import("std");
const Allocator = std.mem.Allocator;

/// High-resolution timer for performance measurement
pub const Timer = struct {
    timer: std.time.Timer,

    /// Start a new timer
    pub fn start() !Timer {
        return Timer{
            .timer = try std.time.Timer.start(),
        };
    }

    /// Read elapsed time in milliseconds
    pub fn readMs(self: *Timer) f64 {
        const ns = self.timer.read();
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }

    /// Read elapsed time in microseconds
    pub fn readUs(self: *Timer) f64 {
        const ns = self.timer.read();
        return @as(f64, @floatFromInt(ns)) / 1_000.0;
    }
};

/// Result of a benchmark operation
pub const BenchmarkReport = struct {
    operation: []const u8,
    iterations: usize,
    total_ms: f64,
    avg_ms: f64,
    min_ms: f64,
    max_ms: f64,
    passes_10ms_rule: bool,

    pub fn format(self: BenchmarkReport, writer: anytype) !void {
        try writer.print("{s: <30} | it: {d: >5} | avg: {d: >8.3}ms | {s}\n", .{
            self.operation,
            self.iterations,
            self.avg_ms,
            if (self.passes_10ms_rule) "✅ PASS" else "❌ FAIL",
        });
    }
};

/// Benchmark runner
pub const Benchmark = struct {
    name: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) Benchmark {
        return Benchmark{
            .allocator = allocator,
            .name = name,
        };
    }

    /// Run a function for multiple iterations and collect stats
    pub fn run(_: Benchmark, operation_name: []const u8, iterations: usize, func: anytype, args: anytype) !BenchmarkReport {
        var total_ms: f64 = 0;
        var min_ms: f64 = std.math.floatMax(f64);
        var max_ms: f64 = 0;

        for (0..iterations) |_| {
            var timer = try Timer.start();
            _ = try @call(.auto, func, args);
            const ms = timer.readMs();

            total_ms += ms;
            if (ms < min_ms) min_ms = ms;
            if (ms > max_ms) max_ms = ms;
        }

        const avg_ms = total_ms / @as(f64, @floatFromInt(iterations));

        return BenchmarkReport{
            .operation = operation_name,
            .iterations = iterations,
            .total_ms = total_ms,
            .avg_ms = avg_ms,
            .min_ms = min_ms,
            .max_ms = max_ms,
            .passes_10ms_rule = avg_ms < 10.0,
        };
    }
};
