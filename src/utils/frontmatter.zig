// Simple frontmatter parser for Neurona files
// Extracts YAML content between --- delimiters
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Frontmatter = struct {
    content: []const u8,
    body: []const u8,

    /// Extract frontmatter from Markdown file
    /// Returns error if no frontmatter found
    pub fn parse(allocator: Allocator, input: []const u8) !Frontmatter {
        // Check if file starts with ---
        if (!std.mem.startsWith(u8, std.mem.trimLeft(u8, input, " \t\n\r"), "---")) {
            return error.NoFrontmatterFound;
        }

        // Find first ---
        var start_idx = (std.mem.indexOf(u8, input, "---") orelse return error.NoFrontmatterFound) + 3; // Skip ---

        // Skip whitespace after first ---
        while (start_idx < input.len and std.ascii.isWhitespace(input[start_idx])) : (start_idx += 1) {}

        // Find second ---
        const end_idx = std.mem.indexOfPos(u8, input, start_idx, "\n---") orelse {
            return error.NoFrontmatterEnd;
        };

        // Extract YAML content
        const yaml_content = std.mem.trim(u8, input[start_idx..end_idx], " \t\n\r");

        // Extract body content (after second ---)
        var body_start = end_idx + 4; // Skip \n---
        while (body_start < input.len and std.ascii.isWhitespace(input[body_start])) : (body_start += 1) {}
        const body = input[body_start..];

        return Frontmatter{
            .content = try allocator.dupe(u8, yaml_content),
            .body = try allocator.dupe(u8, body),
        };
    }

    /// Free allocated memory
    pub fn deinit(self: Frontmatter, allocator: Allocator) void {
        allocator.free(self.content);
        allocator.free(self.body);
    }
};

test "frontmatter parsing" {
    const allocator = std.testing.allocator;

    const input =
        \\---
        \\id: test.neurona
        \\title: Test Neurona
        \\---
        \\
        \\# Content
        \\Some markdown content here
    ;

    const result = try Frontmatter.parse(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("id: test.neurona\ntitle: Test Neurona", result.content);
    try std.testing.expectEqualStrings("# Content\nSome markdown content here", result.body);
}

test "no frontmatter" {
    const allocator = std.testing.allocator;

    const input = "# Just content";

    const result = Frontmatter.parse(allocator, input);
    try std.testing.expectError(error.NoFrontmatterFound, result);
}

test "frontmatter with whitespace" {
    const allocator = std.testing.allocator;

    const input =
        \\---
        \\id: test.neurona
        \\---
        \\
        \\# Content
    ;

    const result = try Frontmatter.parse(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("id: test.neurona", result.content);
}
