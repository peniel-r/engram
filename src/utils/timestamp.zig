// ISO 8601 timestamp utilities for Neurona
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generate current timestamp in ISO 8601 format
/// Format: YYYY-MM-DD
pub fn nowDate(allocator: Allocator) ![]const u8 {
    const seconds = std.time.timestamp();

    const tm = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(seconds)) };
    const epoch_day = tm.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year_day.year,
        month_day.month,
        month_day.day_index + 1,
    });
}

/// Generate current timestamp with time in ISO 8601 format
/// Format: YYYY-MM-DDTHH:MM:SSZ
pub fn nowDateTime(allocator: Allocator) ![]const u8 {
    const seconds = std.time.timestamp();

    const tm = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(seconds)) };
    const epoch_day = tm.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const day_seconds = tm.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const minutes = day_seconds.getMinutesIntoHour();
    const seconds_into_hour = day_seconds.getSecondsIntoMinute();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month,
        month_day.day_index + 1,
        hours,
        minutes,
        seconds_into_hour,
    });
}

/// Generate timestamp for a given epoch seconds
pub fn fromEpoch(allocator: Allocator, epoch_seconds: i64) ![]const u8 {
    const tm = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch_seconds) };
    const epoch_day = tm.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year_day.year,
        month_day.month,
        month_day.day_index + 1,
    });
}

test "nowDate generates valid format" {
    const allocator = std.testing.allocator;

    const date = try nowDate(allocator);
    defer allocator.free(date);

    // Check format YYYY-MM-DD
    try std.testing.expectEqual(@as(usize, 10), date.len);
    try std.testing.expectEqual('-', date[4]);
    try std.testing.expectEqual('-', date[7]);

    // Verify it's a valid date (all digits and separators)
    for (0..10) |i| {
        if (i == 4 or i == 7) continue;
        try std.testing.expect(std.ascii.isDigit(date[i]));
    }
}

test "nowDateTime generates valid format" {
    const allocator = std.testing.allocator;

    const datetime = try nowDateTime(allocator);
    defer allocator.free(datetime);

    // Check format YYYY-MM-DDTHH:MM:SSZ
    try std.testing.expectEqual(@as(usize, 20), datetime.len);
    try std.testing.expectEqual('-', datetime[4]);
    try std.testing.expectEqual('-', datetime[7]);
    try std.testing.expectEqual('T', datetime[10]);
    try std.testing.expectEqual(':', datetime[13]);
    try std.testing.expectEqual(':', datetime[16]);
    try std.testing.expectEqual('Z', datetime[19]);
}

test "fromEpoch generates correct date" {
    const allocator = std.testing.allocator;

    // Test known epoch: 1609459200 = 2021-01-01 00:00:00 UTC
    const date = try fromEpoch(allocator, 1609459200);
    defer allocator.free(date);

    try std.testing.expectEqualStrings("2021-01-01", date);
}

test "fromEpoch handles different epochs" {
    const allocator = std.testing.allocator;

    // Test 2020-01-01 00:00:00 UTC = 1577836800
    const date1 = try fromEpoch(allocator, 1577836800);
    defer allocator.free(date1);
    try std.testing.expectEqualStrings("2020-01-01", date1);

    // Test 2022-01-01 00:00:00 UTC = 1640995200
    const date2 = try fromEpoch(allocator, 1640995200);
    defer allocator.free(date2);
    try std.testing.expectEqualStrings("2022-01-01", date2);
}

test "timestamp functions produce valid format" {
    const allocator = std.testing.allocator;

    // Multiple calls should all be valid ISO 8601 dates
    const date1 = try nowDate(allocator);
    defer allocator.free(date1);

    const date2 = try nowDate(allocator);
    defer allocator.free(date2);

    // Both should be valid ISO 8601 dates
    try std.testing.expectEqual(@as(usize, 10), date1.len);
    try std.testing.expectEqual(@as(usize, 10), date2.len);
}
