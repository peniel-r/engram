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

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |*arr| {
                for (arr.items) |*v| {
                    v.deinit(allocator);
                }
                arr.deinit(allocator);
            },
            .object => |*obj_opt| {
                if (obj_opt.*) |*obj| {
                    var it = obj.iterator();
                    while (it.next()) |entry| {
                        // Free the key first
                        allocator.free(entry.key_ptr.*);

                        const value = entry.value_ptr.*;
                        switch (value) {
                            .string => |s| allocator.free(s),
                            .array => |arr| {
                                for (arr.items) |*v| {
                                    v.deinit(allocator);
                                }
                                var mut_arr = arr;
                                mut_arr.deinit(allocator);
                            },
                            .object => |nested_opt| {
                                if (nested_opt) |nested_obj| {
                                    var nit = nested_obj.iterator();
                                    while (nit.next()) |nentry| {
                                        // Free nested object keys
                                        allocator.free(nentry.key_ptr.*);
                                        nentry.value_ptr.deinit(allocator);
                                    }
                                    var mut_nested = nested_obj;
                                    mut_nested.deinit();
                                }
                            },
                            else => {},
                        }
                    }
                    obj.deinit();
                }
            },
            else => {},
        }
    }
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
            const line = parser.readLine() orelse break;
            if (line.len == 0) continue;

            // Skip comment lines
            if (line[0] == '#') continue;

            // Skip fully empty/whitespace lines
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len == 0) continue;

            try parser.parseLine(line, &result);
        }

        return result;
    }

    /// Parse a single line (key: value or key: [array])
    fn parseLine(self: *Parser, line: []const u8, result: *std.StringHashMap(Value)) !void {
        // Find colon separator
        const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return;
        if (colon_idx == 0) return;

        // Extract key (trim whitespace and duplicate for HashMap ownership)
        const key_slice = std.mem.trim(u8, line[0..colon_idx], " \t\r");
        const key = try self.allocator.dupe(u8, key_slice);
        errdefer self.allocator.free(key);

        // Extract value (without trimming, to detect empty properly)
        const value_part = line[colon_idx + 1 ..];
        const value_str = std.mem.trim(u8, value_part, " \t\r");

        // Check if value is empty after trimming (indented object start)
        if (value_str.len == 0) {
            // Look ahead to parse indented block as nested object
            const nested_obj = try self.parseNestedObject();
            const gop = try result.getOrPut(key);
            if (gop.found_existing) {
                // Free old key and value before replacing
                self.allocator.free(gop.key_ptr.*);
                gop.value_ptr.deinit(self.allocator);
            }
            gop.key_ptr.* = key;
            gop.value_ptr.* = Value{ .object = nested_obj };
            return;
        }

        // Parse value
        const value = try self.parseValue(value_str);
        const gop = try result.getOrPut(key);
        if (gop.found_existing) {
            // Free old key and value before replacing
            self.allocator.free(gop.key_ptr.*);
            gop.value_ptr.deinit(self.allocator);
        }
        gop.key_ptr.* = key;
        gop.value_ptr.* = value;
    }

    /// Parse nested object from indented lines
    fn parseNestedObject(self: *Parser) !?std.StringHashMap(Value) {
        // Save position before reading
        const save_pos = self.pos;

        // Read first indented line (position is currently after the colon line)
        var line = self.readLine() orelse {
            self.pos = save_pos;
            return null;
        };

        // Skip blank lines
        while (line.len == 0 and self.pos < self.input.len) {
            line = self.readLine() orelse {
                self.pos = save_pos;
                return null;
            };
        }

        if (line.len == 0) {
            self.pos = save_pos;
            return null;
        }

        // Calculate base indentation
        var base_indent: usize = 0;
        while (base_indent < line.len and (line[base_indent] == ' ' or line[base_indent] == '\t')) : (base_indent += 1) {}

        if (base_indent == 0) {
            // No indentation, treat as empty object
            return null;
        }

        // Parse nested lines
        var nested_result = std.StringHashMap(Value).init(self.allocator);
        errdefer {
            var it = nested_result.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            nested_result.deinit();
        }

        // Process first line (already read)
        {
            const content = line[base_indent..];
            const colon_idx = std.mem.indexOfScalar(u8, content, ':');

            // Skip lines without colon
            if (colon_idx == null or colon_idx.? == 0) return null;

            const key_slice = std.mem.trim(u8, content[0..colon_idx.?], " \t");
            const key = try self.allocator.dupe(u8, key_slice);
            errdefer self.allocator.free(key);
            const value_str = std.mem.trim(u8, content[colon_idx.? + 1 ..], " \t\r");

            if (value_str.len == 0) {
                const nested_nested = try self.parseNestedObject();
                const gop = try nested_result.getOrPut(key);
                if (gop.found_existing) {
                    // Free old key and value before replacing
                    self.allocator.free(gop.key_ptr.*);
                    gop.value_ptr.deinit(self.allocator);
                }
                gop.key_ptr.* = key;
                gop.value_ptr.* = Value{ .object = nested_nested };
            } else {
                const value = try self.parseValue(value_str);
                const gop = try nested_result.getOrPut(key);
                if (gop.found_existing) {
                    // Free old key and value before replacing
                    self.allocator.free(gop.key_ptr.*);
                    gop.value_ptr.deinit(self.allocator);
                }
                gop.key_ptr.* = key;
                gop.value_ptr.* = value;
            }
        }

        while (self.pos < self.input.len) {
            const check_line = self.readLine() orelse break;

            // Skip blank lines and comments
            if (check_line.len == 0) continue;
            if (check_line[0] == '#') continue;

            // Check indentation
            var indent: usize = 0;
            while (indent < check_line.len and (check_line[indent] == ' ' or check_line[indent] == '\t')) : (indent += 1) {}

            // If indentation is less than base, we're done
            if (indent < base_indent) {
                // This line belongs to parent, put it back
                self.pos -= (check_line.len + 1); // +1 for newline
                break;
            }

            // Remove base indentation from line
            const content = if (indent >= base_indent) check_line[base_indent..] else check_line;

            // Parse key: value
            const colon_idx = std.mem.indexOfScalar(u8, content, ':');

            // Skip lines without colon
            if (colon_idx == null or colon_idx.? == 0) continue;

            const key_slice = std.mem.trim(u8, content[0..colon_idx.?], " \t");
            const key = try self.allocator.dupe(u8, key_slice);
            errdefer self.allocator.free(key);
            const value_str = std.mem.trim(u8, content[colon_idx.? + 1 ..], " \t\r");

            // Handle nested objects within nested objects
            if (value_str.len == 0) {
                const nested_nested = try self.parseNestedObject();
                const gop = try nested_result.getOrPut(key);
                if (gop.found_existing) {
                    // Free old key and value before replacing
                    self.allocator.free(gop.key_ptr.*);
                    gop.value_ptr.deinit(self.allocator);
                }
                gop.key_ptr.* = key;
                gop.value_ptr.* = Value{ .object = nested_nested };
                continue;
            }

            // Parse value
            const value = try self.parseValue(value_str);
            const gop = try nested_result.getOrPut(key);
            if (gop.found_existing) {
                // Free old key and value before replacing
                self.allocator.free(gop.key_ptr.*);
                gop.value_ptr.deinit(self.allocator);
            }
            gop.key_ptr.* = key;
            gop.value_ptr.* = value;
        }

        return nested_result;
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
        if (self.pos >= self.input.len) return null;

        const start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '\n') : (self.pos += 1) {}

        const line = self.input[start..self.pos];

        if (self.pos < self.input.len and self.input[self.pos] == '\n') {
            self.pos += 1; // Skip newline
        }

        return line;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) : (self.pos += 1) {}
    }
};

/// Helper to get string from Value (with default)
/// Allocates memory for the returned string using the provided allocator.
/// Caller must free the returned string.
pub fn getString(allocator: Allocator, value: Value, default: []const u8) ![]const u8 {
    return switch (value) {
        .string => |s| try allocator.dupe(u8, s),
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .boolean => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        else => try allocator.dupe(u8, default),
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
/// NOTE: For integer/float array items, we use the provided allocator directly to avoid page_allocator leaks.
/// This is a known limitation of the simple YAML parser that was fixed for _llm metadata support.
pub fn getArray(value: Value, allocator: Allocator, default: []const []const u8) ![]const []const u8 {
    return switch (value) {
        .array => |arr| {
            var result = try allocator.alloc([]const u8, arr.items.len);
            for (arr.items, 0..) |item, idx| {
                // Direct dupe for string items to avoid page_allocator leaks
                switch (item) {
                    .string => |s| {
                        result[idx] = try allocator.dupe(u8, s);
                    },
                    .integer => |i| {
                        const str = try std.fmt.allocPrint(allocator, "{d}", .{i});
                        result[idx] = str;
                    },
                    .float => |f| {
                        const str = try std.fmt.allocPrint(allocator, "{d}", .{f});
                        result[idx] = str;
                    },
                    .boolean => |b| {
                        const str = if (b) "true" else "false";
                        result[idx] = try allocator.dupe(u8, str);
                    },
                    else => {
                        const str = try getString(allocator, item, "");
                        result[idx] = str;
                    },
                }
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
            entry.value_ptr.deinit(allocator);
        }
        result.deinit();
    }

    const id = result.get("id") orelse return error.NotFound;
    const str = try getString(allocator, id, "");
    try std.testing.expectEqualStrings("test.neurona", str);
    allocator.free(str);
}

test "parse boolean values" {
    const allocator = std.testing.allocator;

    const input = "active: true\nvalid: false";
    var result = try Parser.parse(allocator, input);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
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
            entry.value_ptr.deinit(allocator);
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
            entry.value_ptr.deinit(allocator);
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
            entry.value_ptr.deinit(allocator);
        }
        result.deinit();
    }

    try std.testing.expectEqual(@as(usize, 5), result.count());
}
