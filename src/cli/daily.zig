// File: src/cli/daily.zig
// The `engram daily` command for creating daily notes
// Creates daily notes with date-based IDs and automatic linking

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = @import("../storage/filesystem.zig");
const neurona_factory = @import("../core/neurona_factory.zig");
const Neurona = @import("../root.zig").Neurona;
const NeuronaType = @import("../root.zig").NeuronaType;
const Connection = @import("../root.zig").Connection;
const ConnectionType = @import("../root.zig").ConnectionType;
const uri_parser = @import("../utils/uri_parser.zig");
const timestamp = @import("../utils/timestamp.zig");

// Import Phase 3 CLI utilities
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Configuration for daily notes command
pub const DailyConfig = struct {
    /// Date in YYYY-MM-DD format (default: today)
    date: ?[]const u8 = null,
    /// Whether to create bidirectional links with adjacent days
    bidirectional: bool = true,
    /// Custom title for the daily note
    title: ?[]const u8 = null,
    /// Verbose output
    verbose: bool = false,
    /// Custom cortex directory
    cortex_dir: ?[]const u8 = null,
};

/// Execute daily notes command
pub fn execute(allocator: Allocator, config: DailyConfig) !void {
    // Determine cortex directory
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            try HumanOutput.printError("No cortex found in current directory or within 3 directory levels.");
            try HumanOutput.printInfo("Navigate to a cortex directory or use --cortex <path> to specify location.");
            try HumanOutput.printInfo("Run 'engram init <name>' to create a new cortex.");
            std.process.exit(1);
        }
        return err;
    };
    defer allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // Determine date
    const date = if (config.date) |d| 
        try validateDate(allocator, d)
    else
        try getCurrentDate(allocator);
    defer allocator.free(date);

    // Generate ID
    const id = try allocator.dupe(u8, date);
    defer allocator.free(id);

    // Check if daily note already exists
    if (try checkDailyExists(allocator, neuronas_dir, id)) {
        try HumanOutput.printWarning("Daily note already exists for {s}", .{date});
        const filepath = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ neuronas_dir, id });
        defer allocator.free(filepath);
        try HumanOutput.printInfo("To edit existing note, run: engram show {s}", .{id});
        return;
    }

    // Find adjacent daily notes
    const adjacent = try findAdjacentDailyNotes(allocator, neuronas_dir, date);
    defer {
        if (adjacent.previous) |p| allocator.free(p);
        if (adjacent.next) |n| allocator.free(n);
    }

    // Generate content
    const title = if (config.title) |t| 
        try allocator.dupe(u8, t)
    else
        try allocator.dupe(u8, date);
    defer allocator.free(title);

    const content = try generateDailyNoteContent(allocator, date, title, adjacent);
    defer allocator.free(content);

    // Create neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    
    allocator.free(neurona.id);
    neurona.id = try allocator.dupe(u8, id);
    
    allocator.free(neurona.title);
    neurona.title = try allocator.dupe(u8, title);
    
    neurona.type = .concept; // Daily notes are concept type
    
    allocator.free(neurona.updated);
    neurona.updated = try timestamp.getCurrentTimestamp(allocator);
    
    // Add adjacent connections
    if (adjacent.previous) |prev| {
        const conn = Connection{
            .target_id = try allocator.dupe(u8, prev),
            .connection_type = .next,
            .weight = 100,
        };
        try neurona.addConnection(allocator, conn);
    }
    
    if (adjacent.next) |next_| {
        const conn = Connection{
            .target_id = try allocator.dupe(u8, next_),
            .connection_type = .prerequisite,
            .weight = 100,
        };
        try neurona.addConnection(allocator, conn);
    }

    // Write to file
    const filepath = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ neuronas_dir, id });
    defer allocator.free(filepath);

    try fs.writeNeurona(allocator, neurona, filepath, false);

    try HumanOutput.printSuccess("Created daily note: {s}", .{id});

    if (config.verbose) {
        try HumanOutput.printInfo("File: {s}", .{filepath});
        if (adjacent.previous) |prev| {
            try HumanOutput.printInfo("Linked to previous: {s}", .{prev});
        }
        if (adjacent.next) |next_| {
            try HumanOutput.printInfo("Linked to next: {s}", .{next_});
        }
    }

    // Create bidirectional links if requested
    if (config.bidirectional) {
        if (adjacent.previous) |prev| {
            try createBidirectionalLink(allocator, neuronas_dir, id, prev, .next);
        }
        if (adjacent.next) |next_| {
            try createBidirectionalLink(allocator, neuronas_dir, id, next_, .prerequisite);
        }
    }
}

/// Adjacent daily notes information
const AdjacentDailyNotes = struct {
    previous: ?[]const u8,
    next: ?[]const u8,
};

/// Find adjacent daily notes (previous and next days)
fn findAdjacentDailyNotes(allocator: Allocator, neuronas_dir: []const u8, date: []const u8) !AdjacentDailyNotes {
    var result = AdjacentDailyNotes{
        .previous = null,
        .next = null,
    };

    // Parse date parts
    const parts = std.mem.splitScalar(u8, date, '-');
    const year_str = parts.first() orelse return result;
    const month_str = parts.next() orelse return result;
    const day_str = parts.next() orelse return result;

    const year = std.fmt.parseInt(u16, year_str, 10) catch return result;
    const month = std.fmt.parseInt(u8, month_str, 10) catch return result;
    const day = std.fmt.parseInt(u8, day_str, 10) catch return result;

    // Try to find previous day
    if (day > 1) {
        const prev_day = day - 1;
        const prev_date = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, prev_day });
        defer allocator.free(prev_date);
        
        if (try checkDailyExists(allocator, neuronas_dir, prev_date)) {
            result.previous = try allocator.dupe(u8, prev_date);
        }
    } else {
        // Try to go to previous month (simplified - doesn't handle year boundaries)
        if (month > 1) {
            const prev_month = month - 1;
            const prev_day = getDaysInMonth(year, prev_month);
            const prev_date = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, prev_month, prev_day });
            defer allocator.free(prev_date);
            
            if (try checkDailyExists(allocator, neuronas_dir, prev_date)) {
                result.previous = try allocator.dupe(u8, prev_date);
            }
        }
    }

    // Try to find next day
    const days_in_month = getDaysInMonth(year, month);
    if (day < days_in_month) {
        const next_day = day + 1;
        const next_date = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, next_day });
        defer allocator.free(next_date);
        
        if (try checkDailyExists(allocator, neuronas_dir, next_date)) {
            result.next = try allocator.dupe(u8, next_date);
        }
    } else {
        // Try to go to next month (simplified - doesn't handle year boundaries)
        if (month < 12) {
            const next_month = month + 1;
            const next_date = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-01", .{ year, next_month });
            defer allocator.free(next_date);
            
            if (try checkDailyExists(allocator, neuronas_dir, next_date)) {
                result.next = try allocator.dupe(u8, next_date);
            }
        }
    }

    return result;
}

/// Generate daily note content
fn generateDailyNoteContent(allocator: Allocator, date: []const u8, title: []const u8, adjacent: AdjacentDailyNotes) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("---\n");
    try writer.print("id: {s}\n", .{date});
    try writer.print("title: {s}\n", .{title});
    try writer.writeAll("type: concept\n");
    try writer.writeAll("tags: [daily, note]\n");
    
    if (adjacent.previous) |prev| {
        try writer.writeAll("connections:\n");
        try writer.print("  next:\n", .{});
        try writer.print("    - id: {s}\n", .{prev});
        try writer.print("      weight: 100\n", .{});
    }
    
    if (adjacent.next) |next_| {
        if (adjacent.previous == null) {
            try writer.writeAll("connections:\n");
        }
        try writer.print("  prerequisite:\n", .{});
        try writer.print("    - id: {s}\n", .{next_});
        try writer.print("      weight: 100\n", .{});
    }

    try writer.print("updated: \"{s}\"\n", .{try timestamp.getCurrentTimestamp(allocator)});
    try writer.writeAll("language: en\n");
    try writer.writeAll("---\n\n");
    
    try writer.print("# {s}\n\n", .{title});
    try writer.writeAll("## Tasks\n\n- [ ] Task 1\n- [ ] Task 2\n\n");
    try writer.writeAll("## Notes\n\nWrite your daily notes here.\n\n");
    try writer.writeAll("## Ideas\n\nCapture ideas and insights here.\n\n");
    try writer.writeAll("## References\n\n* [[Previous Note]]\n* [[Next Note]]\n");

    return try buf.toOwnedSlice(allocator);
}

/// Validate date format
fn validateDate(allocator: Allocator, date_str: []const u8) ![]const u8 {
    if (date_str.len != 10) {
        try HumanOutput.printError("Invalid date format. Expected YYYY-MM-DD");
        return error.InvalidDateFormat;
    }

    const parts = std.mem.splitScalar(u8, date_str, '-');
    const year_str = parts.first() orelse return error.InvalidDateFormat;
    const month_str = parts.next() orelse return error.InvalidDateFormat;
    const day_str = parts.next() orelse return error.InvalidDateFormat;

    if (year_str.len != 4 or month_str.len != 2 or day_str.len != 2) {
        try HumanOutput.printError("Invalid date format. Expected YYYY-MM-DD");
        return error.InvalidDateFormat;
    }

    const year = std.fmt.parseInt(u16, year_str, 10) catch {
        try HumanOutput.printError("Invalid year: {s}", .{year_str});
        return error.InvalidDateFormat;
    };

    const month = std.fmt.parseInt(u8, month_str, 10) catch {
        try HumanOutput.printError("Invalid month: {s}", .{month_str});
        return error.InvalidDateFormat;
    };

    const day = std.fmt.parseInt(u8, day_str, 10) catch {
        try HumanOutput.printError("Invalid day: {s}", .{day_str});
        return error.InvalidDateFormat;
    };

    if (month < 1 or month > 12) {
        try HumanOutput.printError("Month must be between 1 and 12");
        return error.InvalidDateFormat;
    }

    const days_in_month = getDaysInMonth(year, month);
    if (day < 1 or day > days_in_month) {
        try HumanOutput.printError("Day must be between 1 and {d} for month {d}", .{ days_in_month, month });
        return error.InvalidDateFormat;
    }

    return try allocator.dupe(u8, date_str);
}

/// Get current date in YYYY-MM-DD format
fn getCurrentDate(allocator: Allocator) ![]const u8 {
    const now = std.time.timestamp();
    const tm = std.time.localtime(now);

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        tm.year + 1900,
        tm.mon + 1,
        tm.day,
    });
}

/// Get number of days in a month
fn getDaysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 30,
    };
}

/// Check if year is a leap year
fn isLeapYear(year: u16) bool {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return (year % 400 == 0);
}

/// Check if daily note exists
fn checkDailyExists(allocator: Allocator, neuronas_dir: []const u8, date: []const u8) !bool {
    const filepath = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ neuronas_dir, date });
    defer allocator.free(filepath);
    
    return std.fs.cwd().openFile(filepath, .{}) != null;
}

/// Create bidirectional link between two daily notes
fn createBidirectionalLink(allocator: Allocator, neuronas_dir: []const u8, source_id: []const u8, target_id: []const u8, conn_type: ConnectionType) !void {
    const target_path = try fs.findNeuronaPath(allocator, neuronas_dir, target_id) catch {
        // Target doesn't exist, skip
        return;
    };
    defer allocator.free(target_path);

    var target = try fs.readNeurona(allocator, target_path);
    defer target.deinit(allocator);

    // Check if connection already exists
    for (target.getConnections(conn_type)) |conn| {
        if (std.mem.eql(u8, conn.target_id, source_id)) {
            // Already linked, skip
            return;
        }
    }

    // Add reverse connection
    const reverse_type = switch (conn_type) {
        .next => .prerequisite,
        .prerequisite => .next,
        else => conn_type,
    };

    const conn = Connection{
        .target_id = try allocator.dupe(u8, source_id),
        .connection_type = reverse_type,
        .weight = 100,
    };
    try target.addConnection(allocator, conn);

    // Update timestamp
    allocator.free(target.updated);
    target.updated = try timestamp.getCurrentTimestamp(allocator);

    try fs.writeNeurona(allocator, target, target_path, false);
}

// ==================== Tests ====================

test "validateDate accepts valid date" {
    const allocator = std.testing.allocator;
    
    const result = try validateDate(allocator, "2026-02-14");
    defer allocator.free(result);
    
    try std.testing.expectEqualStrings("2026-02-14", result);
}

test "getCurrentDate returns valid format" {
    const allocator = std.testing.allocator;
    
    const date = try getCurrentDate(allocator);
    defer allocator.free(date);
    
    try std.testing.expectEqual(@as(usize, 10), date.len);
    try std.testing.expect(date[4] == '-');
    try std.testing.expect(date[7] == '-');
}

test "getDaysInMonth returns correct values" {
    try std.testing.expectEqual(@as(u8, 31), getDaysInMonth(2024, 1));
    try std.testing.expectEqual(@as(u8, 29), getDaysInMonth(2024, 2)); // Leap year
    try std.testing.expectEqual(@as(u8, 28), getDaysInMonth(2023, 2)); // Non-leap
    try std.testing.expectEqual(@as(u8, 30), getDaysInMonth(2024, 4));
}

test "isLeapYear detects leap years" {
    try std.testing.expect(isLeapYear(2024));
    try std.testing.expect(isLeapYear(2000));
    try std.testing.expect(!isLeapYear(2023));
    try std.testing.expect(!isLeapYear(1900));
}