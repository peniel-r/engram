//! JSON output utilities for CLI commands
//! Provides reusable JSON formatting functions to eliminate duplication
//! Pure functions - no side effects, same input = same output

const std = @import("std");

/// Internal JSON escaping
const JsonEscaper = struct {
    /// Write JSON-escaped string to a writer
    fn writeEscaped(writer: anytype, s: []const u8) !void {
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

/// JSON output utilities
pub const JsonOutput = struct {
    /// Begin JSON array
    pub fn beginArray(writer: anytype) !void {
        try writer.writeAll("[");
    }

    /// End JSON array
    pub fn endArray(writer: anytype) !void {
        try writer.writeAll("]");
    }

    /// Begin JSON object
    pub fn beginObject(writer: anytype) !void {
        try writer.writeAll("{");
    }

    /// End JSON object
    pub fn endObject(writer: anytype) !void {
        try writer.writeAll("}");
    }

    /// Write separator between fields
    pub fn separator(writer: anytype, comma: bool) !void {
        if (comma) {
            try writer.writeAll(",");
        }
    }

    /// Write string field with JSON escaping
    pub fn stringField(writer: anytype, name: []const u8, value: []const u8) !void {
        try writer.print("\"{s}\":", .{name});
        try JsonEscaper.writeEscaped(writer, value);
    }

    /// Write enum field (converted to string tag name)
    pub fn enumField(writer: anytype, name: []const u8, value: anytype) !void {
        try writer.print("\"{s}\":\"{s}\"", .{ name, @tagName(value) });
    }

    /// Write number field
    pub fn numberField(writer: anytype, name: []const u8, value: anytype) !void {
        try writer.print("\"{s}\":{}", .{ name, value });
    }

    /// Write boolean field
    pub fn boolField(writer: anytype, name: []const u8, value: bool) !void {
        try writer.print("\"{s}\":{}", .{ name, value });
    }

    /// Write optional string field (null if not provided)
    pub fn optionalStringField(writer: anytype, name: []const u8, value: ?[]const u8) !void {
        try writer.print("\"{s}\":", .{name});
        if (value) |v| {
            try JsonEscaper.writeEscaped(writer, v);
        } else {
            try writer.writeAll("null");
        }
    }
};

// ==================== Tests ====================

test "beginArray writes opening bracket" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.beginArray(fbs.writer());

    try std.testing.expectEqualSlices(u8, "[", fbs.getWritten());
}

test "endArray writes closing bracket" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.endArray(fbs.writer());

    try std.testing.expectEqualSlices(u8, "]", fbs.getWritten());
}

test "beginObject writes opening brace" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.beginObject(fbs.writer());

    try std.testing.expectEqualSlices(u8, "{", fbs.getWritten());
}

test "endObject writes closing brace" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.endObject(fbs.writer());

    try std.testing.expectEqualSlices(u8, "}", fbs.getWritten());
}

test "separator writes comma when true" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.separator(fbs.writer(), true);

    try std.testing.expectEqualSlices(u8, ",", fbs.getWritten());
}

test "separator writes nothing when false" {
    var buffer: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.separator(fbs.writer(), false);

    try std.testing.expectEqualSlices(u8, "", fbs.getWritten());
}

test "stringField writes escaped string" {
    var buffer: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.stringField(fbs.writer(), "name", "test\"value");

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\"name\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
}

test "enumField writes enum as string" {
    const TestEnum = enum { test1, test2 };

    var buffer: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.enumField(fbs.writer(), "field", TestEnum.test1);

    try std.testing.expectEqualSlices(u8, "\"field\":\"test1\"", fbs.getWritten());
}

test "numberField writes number" {
    var buffer: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.numberField(fbs.writer(), "count", 42);

    try std.testing.expectEqualSlices(u8, "\"count\":42", fbs.getWritten());
}

test "boolField writes boolean" {
    var buffer: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.boolField(fbs.writer(), "active", true);

    try std.testing.expectEqualSlices(u8, "\"active\":true", fbs.getWritten());
}

test "optionalStringField writes value when present" {
    var buffer: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.optionalStringField(fbs.writer(), "field", "value");

    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "\"field\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "value") != null);
}

test "optionalStringField writes null when null" {
    var buffer: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try JsonOutput.optionalStringField(fbs.writer(), "field", null);

    try std.testing.expectEqualSlices(u8, "\"field\":null", fbs.getWritten());
}
