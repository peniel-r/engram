// File: src/utils/help_generator.zig
// Help text generation from command metadata

const std = @import("std");
const command_metadata = @import("command_metadata.zig");

/// Help text generator using command metadata
pub const HelpGenerator = struct {
    const FlagMetadata = command_metadata.FlagMetadata;
    const CommandMetadata = command_metadata.CommandMetadata;

    /// Generate formatted help text for a command
    pub fn generate(allocator: std.mem.Allocator, metadata: CommandMetadata) ![]const u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(allocator);

        // Description
        try buffer.writer(allocator).print("{s}\n\n", .{metadata.description});

        // Usage
        try buffer.writer(allocator).print("Usage:\n  {s}\n\n", .{metadata.usage});

        // Arguments (if any positional args expected)
        if (metadata.min_args > 0) {
            try buffer.writer(allocator).print("Arguments:\n", .{});
            // Note: Detailed argument descriptions would need to be added to metadata
            try buffer.writer(allocator).writeAll("  (see examples below)\n\n");
        }

        // Options/Flags
        if (metadata.flags.len > 0) {
            try buffer.writer(allocator).print("Options:\n", .{});
            for (metadata.flags) |flag| {
                const flag_line = try formatFlag(allocator, flag);
                defer allocator.free(flag_line);
                try buffer.writer(allocator).print("{s}\n", .{flag_line});
            }
            try buffer.writer(allocator).writeByte('\n');
        }

        // Examples
        if (metadata.examples.len > 0) {
            try buffer.writer(allocator).print("Examples:\n", .{});
            for (metadata.examples) |example| {
                try buffer.writer(allocator).print("  {s}\n", .{example});
            }
            try buffer.writer(allocator).writeByte('\n');
        }

        return buffer.toOwnedSlice(allocator);
    }

    /// Print help text to stdout
    pub fn print(allocator: std.mem.Allocator, metadata: CommandMetadata) !void {
        const text = try generate(allocator, metadata);
        defer allocator.free(text);
        std.debug.print("{s}", .{text});
    }

    /// Format a single flag for display
    fn formatFlag(allocator: std.mem.Allocator, flag: FlagMetadata) ![]const u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(allocator);

        // Flag name(s)
        if (flag.short) |short| {
            try buffer.writer(allocator).print("  {s}, {s}", .{ short, flag.name });
        } else {
            try buffer.writer(allocator).print("  {s}", .{flag.name});
        }

        // Value type indicator
        if (flag.value_type != .bool) {
            const type_str = switch (flag.value_type) {
                .string => "<string>",
                .number => "<number>",
                .@"enum" => "<enum>",
                .bool => unreachable, // Handled by the if condition above
            };
            try buffer.writer(allocator).print(" {s}", .{type_str});
        }

        // Required indicator
        if (flag.required) {
            try buffer.writer(allocator).print(" (required)", .{});
        }

        // Default value
        if (flag.default_value) |default| {
            try buffer.writer(allocator).print(" (default: {s})", .{default});
        }

        // Description
        try buffer.writer(allocator).print("    {s}", .{flag.description});

        // Enum values (if applicable)
        if (flag.value_type == .@"enum") {
            if (flag.enum_values) |values| {
                try buffer.writer(allocator).print("\n    Options: ", .{});
                for (values, 0..) |val, i| {
                    try buffer.writer(allocator).print("{s}", .{val});
                    if (i < values.len - 1) {
                        try buffer.writer(allocator).print(", ", .{});
                    }
                }
            }
        }

        return buffer.toOwnedSlice(allocator);
    }

    /// Generate brief help for command list
    pub fn generateBrief(allocator: std.mem.Allocator, metadata: CommandMetadata) ![]const u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(allocator);

        try buffer.writer(allocator).print("  {s:<12} {s}", .{ metadata.name, metadata.description });
        return buffer.toOwnedSlice(allocator);
    }
};

// Tests
test "HelpGenerator - generate basic help" {
    const allocator = std.testing.allocator;

    const metadata = command_metadata.CommandMetadata{
        .name = "test",
        .description = "Test command",
        .usage = "engram test <arg>",
        .examples = &[_][]const u8{
            "engram test arg1",
        },
        .flags = &[_]command_metadata.FlagMetadata{
            .{
                .name = "verbose",
                .short = "-v",
                .description = "Verbose output",
                .value_type = .bool,
            },
        },
        .min_args = 1,
        .max_args = 1,
    };

    const help_text = try HelpGenerator.generate(allocator, metadata);
    defer allocator.free(help_text);

    try std.testing.expectStringStartsWith(help_text, "Test command\n\n");
    try std.testing.expectStringContains(help_text, "Usage:\n  engram test <arg>");
    try std.testing.expectStringContains(help_text, "Options:\n");
    try std.testing.expectStringContains(help_text, "  -v, verbose    Verbose output");
    try std.testing.expectStringContains(help_text, "Examples:\n");
}

test "HelpGenerator - format flag with enum" {
    const allocator = std.testing.allocator;

    const flag = command_metadata.FlagMetadata{
        .name = "type",
        .short = "-t",
        .description = "Type of thing",
        .value_type = .@"enum",
        .enum_values = &[_][]const u8{ "type1", "type2", "type3" },
        .default_value = "type1",
        .required = false,
    };

    const flag_text = try HelpGenerator.formatFlag(allocator, flag);
    defer allocator.free(flag_text);

    try std.testing.expectStringContains(flag_text, "-t, type");
    try std.testing.expectStringContains(flag_text, "(default: type1)");
    try std.testing.expectStringContains(flag_text, "Options:");
    try std.testing.expectStringContains(flag_text, "type1, type2, type3");
}

test "HelpGenerator - format required flag" {
    const allocator = std.testing.allocator;

    const flag = command_metadata.FlagMetadata{
        .name = "input",
        .short = "-i",
        .description = "Input file",
        .value_type = .string,
        .required = true,
    };

    const flag_text = try HelpGenerator.formatFlag(allocator, flag);
    defer allocator.free(flag_text);

    try std.testing.expectStringContains(flag_text, "(required)");
}

test "HelpGenerator - generate brief help" {
    const allocator = std.testing.allocator;

    const metadata = command_metadata.CommandMetadata{
        .name = "test",
        .description = "Test command for testing",
        .usage = "engram test",
        .examples = &[_][]const u8{},
        .flags = &[_]command_metadata.FlagMetadata{},
        .min_args = 0,
        .max_args = 0,
    };

    const brief = try HelpGenerator.generateBrief(allocator, metadata);
    defer allocator.free(brief);

    try std.testing.expectStringStartsWith(brief, "  test        Test command for testing");
}

test "HelpGenerator - multiple flags" {
    const allocator = std.testing.allocator;

    const metadata = command_metadata.CommandMetadata{
        .name = "multi",
        .description = "Command with multiple flags",
        .usage = "engram multi <id>",
        .examples = &[_][]const u8{},
        .flags = &[_]command_metadata.FlagMetadata{
            .{
                .name = "verbose",
                .short = "-v",
                .description = "Verbose output",
                .value_type = .bool,
            },
            .{
                .name = "output",
                .short = "-o",
                .description = "Output file",
                .value_type = .string,
                .required = true,
            },
            .{
                .name = "count",
                .short = "-c",
                .description = "Count of items",
                .value_type = .number,
                .default_value = "10",
            },
        },
        .min_args = 1,
        .max_args = 1,
    };

    const help_text = try HelpGenerator.generate(allocator, metadata);
    defer allocator.free(help_text);

    // Check all flags are present
    try std.testing.expectStringContains(help_text, "-v, verbose");
    try std.testing.expectStringContains(help_text, "-o, output <string> (required)");
    try std.testing.expectStringContains(help_text, "-c, count <number> (default: 10)");
}
