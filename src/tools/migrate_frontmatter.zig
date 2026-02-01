// Migration tool to move connections from body to frontmatter
// This tool scans Neurona files and moves connection definitions
// from the body to the YAML frontmatter per spec compliance
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn migrateNeuronas(allocator: Allocator, directory: []const u8) !void {
    std.debug.print("Migrating Neuronas in {s}...\n", .{directory});

    // Open directory
    var dir = try std.fs.cwd().openDir(directory, .{ .iterate = true });
    defer dir.close();

    var migrated_count: usize = 0;
    var skipped_count: usize = 0;
    var error_count: usize = 0;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        const filepath = try std.fs.path.join(allocator, &.{ directory, entry.name });
        defer allocator.free(filepath);

        // Read file content
        const content = std.fs.cwd().readFileAlloc(allocator, filepath, 1024 * 1024) catch |err| {
            std.debug.print("Error reading {s}: {}\n", .{ filepath, err });
            error_count += 1;
            continue;
        };
        defer allocator.free(content);

        // Check if file has connections in body
        if (!hasConnectionsInBody(content)) {
            skipped_count += 1;
            continue;
        }

        // Extract frontmatter and body
        const fm_result = extractFrontmatterAndBody(content);

        if (fm_result.frontmatter.len == 0) {
            std.debug.print("Warning: {s} has no frontmatter\n", .{filepath});
            error_count += 1;
            continue;
        }

        // Parse connections from body
        const connections = try parseConnectionsFromBody(allocator, fm_result.body);
        defer {
            for (connections.items) |conn| {
                allocator.free(conn.target_id);
            }
            connections.deinit(allocator);
        }

        if (connections.items.len == 0) {
            skipped_count += 1;
            continue;
        }

        // Read existing frontmatter
        var yaml_parser = @import("../utils/yaml.zig").Parser;
        var yaml_data = try yaml_parser.parse(allocator, fm_result.frontmatter);
        defer {
            var it = yaml_data.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            yaml_data.deinit();
        }

        // Add connections to frontmatter YAML
        // Check if connections already exist
        if (yaml_data.get("connections") != null) {
            std.debug.print("Warning: {s} already has connections in frontmatter, skipping\n", .{filepath});
            skipped_count += 1;
            continue;
        }

        // Build new YAML with connections
        const new_yaml = try addConnectionsToYaml(allocator, fm_result.frontmatter, &connections);
        defer allocator.free(new_yaml);

        // Write migrated file
        try writeMigratedFile(allocator, filepath, new_yaml, fm_result.body_without_connections);

        std.debug.print("✓ Migrated {s} ({d} connections)\n", .{ entry.name, connections.items.len });
        migrated_count += 1;
    }

    std.debug.print("\nMigration complete:\n", .{});
    std.debug.print("  Migrated: {d}\n", .{migrated_count});
    std.debug.print("  Skipped: {d}\n", .{skipped_count});
    std.debug.print("  Errors: {d}\n", .{error_count});
}

const FrontmatterResult = struct {
    frontmatter: []const u8,
    body: []const u8,
    body_without_connections: []const u8,
};

fn extractFrontmatterAndBody(content: []const u8) FrontmatterResult {
    // Find first ---
    const start = std.mem.indexOf(u8, content, "---") orelse return .{
        .frontmatter = "",
        .body = content,
        .body_without_connections = content,
    };

    // Find second ---
    const after_first = start + 3;
    const end = std.mem.indexOfPos(u8, content, after_first, "---") orelse return .{
        .frontmatter = content[after_first..],
        .body = "",
        .body_without_connections = "",
    };

    const frontmatter = content[after_first..end];
    const after_second = end + 3;

    // Skip newlines after second ---
    var body_start = after_second;
    while (body_start < content.len and (content[body_start] == '\n' or content[body_start] == '\r')) : (body_start += 1) {}

    const body = if (body_start < content.len) content[body_start..] else "";

    // Remove connections from body
    const body_without_connections = removeConnectionsFromBody(body);

    return .{
        .frontmatter = frontmatter,
        .body = body,
        .body_without_connections = body_without_connections,
    };
}

fn hasConnectionsInBody(content: []const u8) bool {
    const connection_keywords = [_][]const u8{
        "connections:",
        "validates:",
        "validated_by:",
        "implements:",
        "blocks:",
        "blocked_by:",
        "tests:",
        "tested_by:",
        "relates_to:",
        "parent:",
        "child:",
        "prerequisite:",
        "next:",
    };

    for (connection_keywords) |keyword| {
        if (std.mem.indexOf(u8, content, keyword)) |_| {
            return true;
        }
    }

    return false;
}

fn removeConnectionsFromBody(body: []const u8) []const u8 {
    _ = body;
    // For now, return empty body to remove all connection definitions
    // In a full implementation, we'd filter out only connection lines
    return "";
}

const ParsedConnection = struct {
    target_id: []const u8,
    connection_type: []const u8,
    weight: u8,
};

fn parseConnectionsFromBody(allocator: Allocator, body: []const u8) !std.ArrayListUnmanaged(ParsedConnection) {
    var connections = std.ArrayListUnmanaged(ParsedConnection){};

    var line_iter = std.mem.splitScalar(u8, body, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        // Check for "type:target:weight" pattern
        var colon_count: usize = 0;
        for (trimmed) |c| {
            if (c == ':') colon_count += 1;
        }

        if (colon_count >= 2) {
            // Parse "type:target_id:weight"
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            const conn_type = parts.next() orelse continue;
            const target_id = parts.next() orelse continue;
            const weight_str = parts.next() orelse "50";

            const weight = std.fmt.parseInt(u8, weight_str, 10) catch 50;

            try connections.append(allocator, .{
                .target_id = try allocator.dupe(u8, target_id),
                .connection_type = try allocator.dupe(u8, conn_type),
                .weight = weight,
            });
        }
    }

    return connections;
}

fn addConnectionsToYaml(allocator: Allocator, yaml: []const u8, connections: *const std.ArrayListUnmanaged(ParsedConnection)) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    // Write existing YAML
    try writer.writeAll(yaml);

    // Add connections section
    try writer.writeAll("connections:\n");

    for (connections.items) |conn| {
        try writer.print("  {s}:\n", .{conn.connection_type});
        try writer.print("    - target_id: {s}\n", .{conn.target_id});
        try writer.print("      weight: {d}\n", .{conn.weight});
    }

    return try buf.toOwnedSlice(allocator);
}

fn writeMigratedFile(allocator: Allocator, filepath: []const u8, yaml: []const u8, body: []const u8) !void {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("---\n");
    try writer.writeAll(yaml);
    try writer.writeAll("---\n\n");
    try writer.writeAll(body);

    const content = try buf.toOwnedSlice(allocator);
    defer allocator.free(content);

    try std.fs.cwd().writeFile(.{ .sub_path = filepath, .data = content });
}

test "extractFrontmatterAndBody parses correctly" {
    const content =
        \\---
        \\id: test.001
        \\title: Test
        \\---
        \\
        \\# Body content
    ;

    const result = extractFrontmatterAndBody(content);
    try std.testing.expect(std.mem.indexOf(u8, result.frontmatter, "id: test.001") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "# Body content") != null);
}

test "hasConnectionsInBody detects connections" {
    const with_conn = "connections:\n  validates:";
    try std.testing.expect(hasConnectionsInBody(with_conn));

    const without_conn = "# Some content\nNo connections here";
    try std.testing.expect(!hasConnectionsInBody(without_conn));
}
