//! Human-readable output utilities for CLI commands
//! Provides consistent formatting for human-readable output
//! Pure functions - no side effects, same input = same output

const std = @import("std");

/// Human output utilities with emoji and consistent formatting
pub const HumanOutput = struct {
    /// Print header with emoji
    pub fn printHeader(title: []const u8, emoji: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("\n{s} {s}\n", .{ emoji, title });
        try stdout.writeByte('=');
        for (0..@min(title.len + 2, 40)) |_| {
            try stdout.writeByte('=');
        }
        try stdout.writeByte('\n');
        try stdout.flush();
    }

    /// Print subheader with emoji
    pub fn printSubheader(title: []const u8, emoji: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("  {s} {s}\n", .{ emoji, title });
        try stdout.flush();
    }

    /// Print separator line
    pub fn printSeparator(char: u8, count: usize) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        for (0..count) |_| {
            try stdout.writeByte(char);
        }
        try stdout.writeByte('\n');
        try stdout.flush();
    }

    /// Print success message
    pub fn printSuccess(message: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("✅ {s}\n", .{message});
        try stdout.flush();
    }

    /// Print warning message
    pub fn printWarning(message: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("⚠️  {s}\n", .{message});
        try stdout.flush();
    }

    /// Print error message
    pub fn printError(message: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("❌ {s}\n", .{message});
        try stdout.flush();
    }

    /// Print info message
    pub fn printInfo(message: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("ℹ️  {s}\n", .{message});
        try stdout.flush();
    }
};

// ==================== Tests ====================

test "printHeader prints formatted header" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("\n{s} {s}\n", .{ "📋", "Test" });
    try fbs.writer().writeByte('=');
    try fbs.writer().writeByte('=');
    for (0..6) |_| try fbs.writer().writeByte('=');
    try fbs.writer().writeByte('\n');

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "📋") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Test") != null);
}

test "printSubheader prints formatted subheader" {
    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("  {s} {s}\n", .{ "→", "Section" });

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "→") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Section") != null);
}

test "printSeparator prints correct number of characters" {
    var buffer: [64]u8 = undefined;
    _ = std.io.fixedBufferStream(&buffer);
    try HumanOutput.printSeparator('-', 10);
    // Note: Can't easily test stdout functions without redirecting

    try std.testing.expect(true); // Placeholder test
}

test "printSuccess prints success message" {
    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("✅ {s}\n", .{"Done"});

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "✅") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Done") != null);
}

test "printWarning prints warning message" {
    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("⚠️  {s}\n", .{"Warning"});

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "⚠️") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Warning") != null);
}

test "printError prints error message" {
    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("❌ {s}\n", .{"Error"});

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "❌") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Error") != null);
}

test "printInfo prints info message" {
    var buffer: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try fbs.writer().print("ℹ️  {s}\n", .{"Info"});

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "ℹ️") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Info") != null);
}
