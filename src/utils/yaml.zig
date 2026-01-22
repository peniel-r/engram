// Simple YAML parser for Neurona frontmatter
// Supports: key-value, arrays, nested objects
const std = @import("std");
const Allocator = std.mem.Allocator;

const ParseError = error{
    InvalidArrayItem,
    OutOfMemory,
};

/// YAML value types
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    null,
    array: std.ArrayListUnmanaged(Value), // Unmanaged for manual allocator control
    object: ?std.StringHashMap(Value), // Optional object
};

/// Simple YAML parser
pub const Parser = struct {
    allocator: Allocator,
    input: []const u8,
    pos: usize = 0,

    /// Parse YAML input
    pub fn parse(allocator: Allocator, input: []const u8) !std.StringHashMap(Value) {
        var parser = Parser{
            .allocator = allocator,
            .input = input,
        };

        var result = std.StringHashMap(Value).init(allocator);

        // Parse line by line
        while (parser.pos < parser.input.len) {
            parser.skipWhitespace();
            if (parser.pos >= parser.input.len) break;

            const line = parser.readLine() orelse break;
            if (line.len == 0) continue;

            // Skip comment lines
            if (line[0] == '#') continue;

            try parser.parseLine(line, &result);
        }

        return result;
    }

    /// Parse a single line (key: value or key: [array])
    fn parseLine(self: *Parser, line: []const u8, result: *std.StringHashMap(Value)) !void {
        // Find colon separator
        const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return;
        if (colon_idx == 0) return;

        // Extract key
        const key = std.mem.trim(u8, line[0..colon_idx], " \t");

        // Extract value
        const value_str = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

        // Parse value
        const value = try self.parseValue(value_str);
        try result.put(key, value);
    }

    /// Parse a YAML value
    fn parseValue(self: *Parser, value_str: []const u8) !Value {
        // Check for null
        if (std.mem.eql(u8, value_str, "null") or std.mem.eql(u8, value_str, "~")) {
            return Value{ .null = {} };
        }

        // Check for boolean
        if (std.mem.eql(u8, value_str, "true")) return Value{ .boolean = true };
        if (std.mem.eql(u8, value_str, "false")) return Value{ .boolean = false };

        // Check for array start
        if (value_str.len >= 1 and value_str[0] == '[') {
            return try self.parseArray(value_str);
        }

        // Try to parse as integer
        if (self.parseInt(value_str)) |int_val| {
            return Value{ .integer = int_val };
        } else |_| {
            // Try to parse as float
            if (self.parseFloat(value_str)) |float_val| {
                return Value{ .float = float_val };
            } else |_| {
                // Default to string
                // Remove quotes if present
                const unquoted = std.mem.trim(u8, value_str, "\"'");
                return Value{ .string = try self.allocator.dupe(u8, unquoted) };
            }
        }
    }

    /// Parse array value: [item1, item2]
    fn parseArray(self: *Parser, value_str: []const u8) ParseError!Value {
        // Strip brackets
        const inner = std.mem.trim(u8, value_str[1 .. value_str.len - 1], " ");
        if (inner.len == 0) {
            return Value{ .array = .{} };
        }

        var array = std.ArrayListUnmanaged(Value){};
        var iter = std.mem.splitScalar(u8, inner, ',');

        while (iter.next()) |item| {
            const trimmed = std.mem.trim(u8, item, " ");
            const val = self.parseValue(trimmed) catch return error.InvalidArrayItem;
            try array.append(self.allocator, val);
        }

        return Value{ .array = array };
    }

    /// Parse integer value
    fn parseInt(self: *Parser, value_str: []const u8) !i64 {
        _ = self;
        return std.fmt.parseInt(i64, value_str, 10);
    }

    /// Parse float value
    fn parseFloat(self: *Parser, value_str: []const u8) !f64 {
        _ = self;
        return std.fmt.parseFloat(f64, value_str);
    }

    /// Read a line from input
    fn readLine(self: *Parser) ?[]const u8 {
        const start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '\n') : (self.pos += 1) {}

        if (self.pos > start) {
            const line = self.input[start..self.pos];
            if (self.pos < self.input.len and self.input[self.pos] == '\n') {
                self.pos += 1; // Skip newline
            }
            return line;
        }

        return null;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) : (self.pos += 1) {}
    }
};

/// Helper to get string from Value (with default)
pub fn getString(value: Value, default: []const u8) []const u8 {
    return switch (value) {
        .string => |s| s,
        .integer => |i| std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{i}) catch default,
        .float => |f| std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{f}) catch default,
        .boolean => |b| if (b) "true" else "false",
        else => default,
    };
}

/// Helper to get integer from Value (with default)
pub fn getInt(value: Value, default: i64) i64 {
    return switch (value) {
        .integer => |i| i,
        .string => |s| std.fmt.parseInt(i64, s, 10) catch default,
        .boolean => |b| if (b) 1 else 0,
        else => default,
    };
}

/// Helper to get boolean from Value (with default)
pub fn getBool(value: Value, default: bool) bool {
    return switch (value) {
        .boolean => |b| b,
        .string => |s| std.mem.eql(u8, s, "true"),
        .integer => |i| i != 0,
        else => default,
    };
}

/// Helper to get array from Value (with default)
pub fn getArray(value: Value, allocator: Allocator, default: []const []const u8) ![]const []const u8 {
    return switch (value) {
        .array => |arr| {
            var result = try allocator.alloc([]const u8, arr.items.len);
            for (arr.items, 0..) |item, i| {
                result[i] = try allocator.dupe(u8, getString(item, ""));
            }
            return result;
        },
        else => default,
    };
}

test "parse simple key-value" {
    const allocator = std.testing.allocator;

    const input = "id: test.neurona\ntitle: Test";
    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used in tests)
                else => {},
            }
        }
        result.deinit();
    }

    const id = result.get("id") orelse return error.NotFound;
    try std.testing.expectEqualStrings("test.neurona", getString(id, ""));
}

test "parse boolean values" {
    const allocator = std.testing.allocator;

    const input = "active: true\nvalid: false";
    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used in tests)
                else => {},
            }
        }
        result.deinit();
    }

    const active = result.get("active") orelse return error.NotFound;
    try std.testing.expect(getBool(active, false));

    const valid = result.get("valid") orelse return error.NotFound;
    try std.testing.expect(!getBool(valid, true));
}

test "parse integer values" {
    const allocator = std.testing.allocator;

    const input = "count: 42\npriority: 1";
    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used in tests)
                else => {},
            }
        }
        result.deinit();
    }

    const count = result.get("count") orelse return error.NotFound;
    try std.testing.expectEqual(@as(i64, 42), getInt(count, 0));
}

test "parse array values" {
    const allocator = std.testing.allocator;

    const input = "tags: [test, example, yaml]";
    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used in tests)
                else => {},
            }
        }
        result.deinit();
    }

    const tags = result.get("tags") orelse return error.NotFound;
    const arr = try getArray(tags, allocator, &[_][]const u8{});
    defer {
        for (arr) |item| allocator.free(item);
        allocator.free(arr);
    }

    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqualStrings("test", arr[0]);
}

test "parse mixed values" {
    const allocator = std.testing.allocator;

    const input =
        \\id: test.001
        \\title: Test Neurona
        \\tags: [test, example]
        \\priority: 1
        \\active: true
    ;

    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used in tests)
                else => {},
            }
        }
        result.deinit();
    }

    try std.testing.expectEqual(@as(usize, 5), result.count());
}
