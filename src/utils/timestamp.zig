// ISO 8601 timestamp utilities for Neurona Knowledge Protocol
///
/// This module provides functions for generating ISO 8601 compliant timestamps
/// using UTC timezone. All timestamps follow the format: YYYY-MM-DDTHH:MM:SSZ
///
/// Timezone Handling:
/// - All functions use UTC (Coordinated Universal Time)
/// - UTC is indicated by the 'Z' suffix in timestamps
/// - No local time conversions are performed
/// - This ensures consistent timestamps across all systems and timezones
///
/// Functions:
///   - nowDate(): Current date (YYYY-MM-DD)
///   - nowDateTime(): Current datetime (YYYY-MM-DDTHH:MM:SSZ)
///   - getCurrentTimestamp(): Current datetime (same as nowDateTime)
///   - fromEpoch(): Convert epoch seconds to date
///
/// Memory Management:
/// - All functions that return `[]const u8` allocate using the provided allocator
/// - Caller is responsible for freeing the returned memory
/// - Use `defer allocator.free(timestamp)` pattern for safety
///
/// Example:
///   ```zig
///   const allocator = std.testing.allocator;
///   const timestamp = try getCurrentTimestamp(allocator);
///   defer allocator.free(timestamp);
///   // timestamp: "2026-01-23T05:44:48Z"
///   ```
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generate current timestamp in ISO 8601 date format
/// Format: YYYY-MM-DD (UTC)
///
/// Uses std.time.timestamp() to get current epoch time and extracts
/// the date component in ISO 8601 format.
///
/// This function allocates memory using the provided allocator.
/// Caller is responsible for freeing the returned string.
///
/// Returns:
///   - ISO 8601 formatted date string (YYYY-MM-DD)
///   - Error if allocation fails
///
/// Example:
///   ```zig
///   const date = try nowDate(allocator);
///   defer allocator.free(date);
///   // date: "2026-01-23"
///   ```
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
/// Format: YYYY-MM-DDTHH:MM:SSZ (UTC)
///
/// Uses std.time.timestamp() to get current epoch time and converts to
/// ISO 8601 format with UTC timezone indicator 'Z'.
///
/// This function allocates memory using the provided allocator.
/// Caller is responsible for freeing the returned string.
///
/// Returns:
///   - ISO 8601 formatted timestamp string
///   - Error if allocation fails
///
/// Example:
///   ```zig
///   const datetime = try nowDateTime(allocator);
///   defer allocator.free(datetime);
///   // datetime: "2026-01-23T05:44:48Z"
///   ```
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

/// Get current timestamp in ISO 8601 format with timezone
/// Format: YYYY-MM-DDTHH:MM:SSZ (UTC)
///
/// This function allocates memory using the provided allocator.
/// Caller is responsible for freeing the returned string.
///
/// Returns:
///   - ISO 8601 formatted timestamp string
///   - Error if allocation fails
pub fn getCurrentTimestamp(allocator: Allocator) ![]const u8 {
    return try nowDateTime(allocator);
}

/// Generate timestamp for a given epoch seconds
/// Format: YYYY-MM-DD (UTC)
///
/// Converts Unix epoch seconds (seconds since 1970-01-01 00:00:00 UTC)
/// to ISO 8601 date format. Handles leap years and month boundaries
/// correctly.
///
/// This function allocates memory using the provided allocator.
/// Caller is responsible for freeing the returned string.
///
/// Parameters:
///   - epoch_seconds: Unix epoch time in seconds (can be negative)
///
/// Returns:
///   - ISO 8601 formatted date string (YYYY-MM-DD)
///   - Error if allocation fails
///
/// Example:
///   ```zig
///   const date = try fromEpoch(allocator, 1609459200);
///   defer allocator.free(date);
///   // date: "2021-01-01"
///   ```
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

test "getCurrentTimestamp generates valid format" {
    const allocator = std.testing.allocator;

    const timestamp = try getCurrentTimestamp(allocator);
    defer allocator.free(timestamp);

    // Check format YYYY-MM-DDTHH:MM:SSZ
    try std.testing.expectEqual(@as(usize, 20), timestamp.len);
    try std.testing.expectEqual('-', timestamp[4]);
    try std.testing.expectEqual('-', timestamp[7]);
    try std.testing.expectEqual('T', timestamp[10]);
    try std.testing.expectEqual(':', timestamp[13]);
    try std.testing.expectEqual(':', timestamp[16]);
    try std.testing.expectEqual('Z', timestamp[19]);
}

test "getCurrentTimestamp includes UTC timezone marker" {
    const allocator = std.testing.allocator;

    const timestamp = try getCurrentTimestamp(allocator);
    defer allocator.free(timestamp);

    // Verify 'Z' suffix for UTC timezone
    try std.testing.expectEqual('Z', timestamp[timestamp.len - 1]);
}

test "getCurrentTimestamp and nowDateTime are consistent" {
    const allocator = std.testing.allocator;

    const ts1 = try getCurrentTimestamp(allocator);
    defer allocator.free(ts1);

    const ts2 = try nowDateTime(allocator);
    defer allocator.free(ts2);

    // Both should have same length
    try std.testing.expectEqual(ts1.len, ts2.len);

    // Both should have same format (Z at end, T in middle)
    try std.testing.expectEqual('Z', ts1[ts1.len - 1]);
    try std.testing.expectEqual('Z', ts2[ts2.len - 1]);
    try std.testing.expectEqual('T', ts1[10]);
    try std.testing.expectEqual('T', ts2[10]);
}

test "nowDateTime uses UTC timezone" {
    const allocator = std.testing.allocator;

    const datetime = try nowDateTime(allocator);
    defer allocator.free(datetime);

    // Verify format ends with Z (UTC timezone indicator)
    try std.testing.expectEqual(@as(usize, 20), datetime.len);
    try std.testing.expectEqual('Z', datetime[19]);
}

test "fromEpoch handles leap years" {
    const allocator = std.testing.allocator;

    // 2020 is a leap year: Feb 29, 2020 00:00:00 UTC = 1582934400
    const date = try fromEpoch(allocator, 1582934400);
    defer allocator.free(date);

    try std.testing.expectEqualStrings("2020-02-29", date);
}

test "fromEpoch handles month boundaries" {
    const allocator = std.testing.allocator;

    // Jan 31, 2020 00:00:00 UTC = 1580304000
    const date1 = try fromEpoch(allocator, 1580304000);
    defer allocator.free(date1);
    try std.testing.expectEqualStrings("2020-01-31", date1);

    // Feb 1, 2020 00:00:00 UTC = 1580476800
    const date2 = try fromEpoch(allocator, 1580476800);
    defer allocator.free(date2);
    try std.testing.expectEqualStrings("2020-02-01", date2);

    // Dec 31, 2020 00:00:00 UTC = 1609372800
    const date3 = try fromEpoch(allocator, 1609372800);
    defer allocator.free(date3);
    try std.testing.expectEqualStrings("2020-12-31", date3);
}

test "nowDate components are in valid ranges" {
    const allocator = std.testing.allocator;

    const date = try nowDate(allocator);
    defer allocator.free(date);

    // Parse year (YYYY)
    const year = try std.fmt.parseInt(u16, date[0..4], 10);
    try std.testing.expect(year >= 2000 and year <= 2100); // Reasonable range

    // Parse month (MM)
    const month = try std.fmt.parseInt(u8, date[5..7], 10);
    try std.testing.expect(month >= 1 and month <= 12);

    // Parse day (DD)
    const day = try std.fmt.parseInt(u8, date[8..10], 10);
    try std.testing.expect(day >= 1 and day <= 31);
}

test "nowDateTime components are in valid ranges" {
    const allocator = std.testing.allocator;

    const datetime = try nowDateTime(allocator);
    defer allocator.free(datetime);

    // Parse hour (HH)
    const hour = try std.fmt.parseInt(u8, datetime[11..13], 10);
    try std.testing.expect(hour <= 23);

    // Parse minute (MM)
    const minute = try std.fmt.parseInt(u8, datetime[14..16], 10);
    try std.testing.expect(minute <= 59);

    // Parse second (SS)
    const second = try std.fmt.parseInt(u8, datetime[17..19], 10);
    try std.testing.expect(second <= 59);
}
