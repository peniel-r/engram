//! String utilities for library use
//! Provides common string operations including JSON escaping

const std = @import("std");
const Allocator = std.mem.Allocator;

/// JSON string utilities
pub const Json = struct {
    /// Print a string as JSON-escaped value to stdout
    /// Escapes: " \ \n \r \t
    pub fn printEscapedString(s: []const u8) void {
        std.debug.print("\"", .{});
        for (s) |c| {
            switch (c) {
                '"' => std.debug.print("\\\"", .{}),
                '\\' => std.debug.print("\\\\", .{}),
                '\n' => std.debug.print("\\n", .{}),
                '\r' => std.debug.print("\\r", .{}),
                '\t' => std.debug.print("\\t", .{}),
                else => std.debug.print("{c}", .{c}),
            }
        }
        std.debug.print("\"", .{});
    }

    /// Format a string as JSON-escaped, allocating result
    /// Caller must free returned string with allocator.free()
    pub fn formatEscaped(s: []const u8, allocator: Allocator) ![]const u8 {
        // Worst case: every character is escaped (2x)
        var result = try std.ArrayListUnmanaged(u8).initCapacity(allocator, s.len * 2);
        defer result.deinit(allocator);

        try result.append(allocator, '"');
        for (s) |c| {
            switch (c) {
                '"' => try result.appendSlice(allocator, "\\\""),
                '\\' => try result.appendSlice(allocator, "\\\\"),
                '\n' => try result.appendSlice(allocator, "\\n"),
                '\r' => try result.appendSlice(allocator, "\\r"),
                '\t' => try result.appendSlice(allocator, "\\t"),
                else => try result.append(allocator, c),
            }
        }
        try result.append(allocator, '"');

        return result.toOwnedSlice(allocator);
    }

    /// Write JSON-escaped string to a writer
    pub fn writeEscaped(writer: anytype, s: []const u8) !void {
        try writer.writeAll("\"");
        for (s) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("\"");
    }
};

test "Json.printEscapedString escapes special characters" {
    Json.printEscapedString("simple");
    Json.printEscapedString("with\"quote");
    Json.printEscapedString("with\\backslash");
    Json.printEscapedString("with\nnewline");
    Json.printEscapedString("all\\\"\n\r\t");
}

test "Json.formatEscaped allocates escaped string" {
    const allocator = std.testing.allocator;

    const input = "test\"string\\with\nchars";
    const result = try Json.formatEscaped(input, allocator);
    defer allocator.free(result);

    try std.testing.expect(result.len > input.len);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
}

test "Json.writeEscaped writes to writer" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const input = "test\"value";
    try Json.writeEscaped(writer, input);

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
}
