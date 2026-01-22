// File: src/cli/show.zig
// The `engram show` command for displaying Neuronas
// Displays Neurona content with connections

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;

/// Display configuration
pub const ShowConfig = struct {
    id: []const u8,
    show_connections: bool = true,
    show_body: bool = true,
    json_output: bool = false,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: ShowConfig) !void {
    // Step 1: Find and read Neurona file
    const filepath = try findNeuronaPath(allocator, config.id);
    defer allocator.free(filepath);

    const neurona = try readNeurona(allocator, filepath);
    defer neurona.deinit(allocator);

    // Step 2: Read body content
    const body = try readBodyContent(allocator, filepath);
    defer allocator.free(body);

    // Step 3: Output
    if (config.json_output) {
        try outputJson(&neurona, filepath);
    } else {
        try outputHuman(&neurona, body, config.show_connections, config.show_body);
    }
}

/// Find Neurona file by ID
fn findNeuronaPath(allocator: Allocator, id: []const u8) ![]const u8 {
    // Check for .md file directly
    const direct_path = try std.fmt.allocPrint(allocator, "neuronas/{s}.md", .{id});
    defer allocator.free(direct_path);

    if (std.fs.cwd().openFile(direct_path, .{})) |_| {
        return direct_path;
    } else |err| {
        // File doesn't exist, search for files starting with ID prefix
        if (err != error.FileNotFound) return err;
    }

    // Search in neuronas directory
    var dir = try std.fs.cwd().openDir("neuronas", .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        // Check if ID is in filename (before .md)
        const base_name = entry.name[0 .. entry.name.len - 3]; // Remove .md
        if (std.mem.indexOf(u8, base_name, id) != null) {
            return try std.fs.path.join(allocator, &.{ "neuronas", entry.name });
        }
    }

    return error.NeuronaNotFound;
}

/// Read file body content (markdown after frontmatter)
fn readBodyContent(allocator: Allocator, filepath: []const u8) ![]const u8 {
    const content = try std.fs.cwd().readFileAlloc(allocator, filepath, 10 * 1024 * 1024);

    // Find end of frontmatter (second ---)
    const second_delim = std.mem.indexOfPos(u8, content, 0, "\n---") orelse return error.InvalidFormat;

    // Skip past second delimiter and any newlines
    var body_start = second_delim + 4;
    while (body_start < content.len and std.ascii.isWhitespace(content[body_start])) : (body_start += 1) {}

    return try allocator.dupe(u8, content[body_start..]);
}

/// Human-friendly output
fn outputHuman(neurona: *const Neurona, body: []const u8, show_connections: bool, show_body: bool) !void {
    const stdout = std.io.getStdOut().writer();

    // Header
    try stdout.writeAll("\n");
    try stdout.print("  ID: {s}\n", .{neurona.id});
    try stdout.print("  Title: {s}\n", .{neurona.title});
    try stdout.print("  Type: {s}\n", .{@tagName(neurona.type)});

    // Tags
    if (neurona.tags.items.len > 0) {
        try stdout.writeAll("  Tags: ");
        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) try stdout.writeAll(", ");
            try stdout.print("{s}", .{tag});
        }
        try stdout.writeAll("\n");
    }

    // Connections
    if (show_connections) {
        var conn_it = neurona.connections.iterator();
        if (conn_it.next()) |_| {
            try stdout.writeAll("  Connections:\n");
            conn_it = neurona.connections.iterator(); // Reset iterator
            while (conn_it.next()) |entry| {
                try stdout.print("    {s}: {d} connection(s)\n", .{ entry.key_ptr.*, entry.value_ptr.connections.items.len });
            }
        }
    }

    // Metadata
    try stdout.print("  Updated: {s}\n", .{neurona.updated});
    try stdout.print("  Language: {s}\n", .{neurona.language});

    // Body
    if (show_body) {
        try stdout.writeAll("\n");
        try stdout.writeByteNTimes('=', 50);
        try stdout.writeAll("\n");
        try stdout.writeAll(body);
        try stdout.writeAll("\n");
        try stdout.writeByteNTimes('=', 50);
        try stdout.writeAll("\n");
    }
}

/// JSON output for AI
fn outputJson(neurona: *const Neurona, filepath: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("{");
    try stdout.print("\"success\":true,", .{});
    try stdout.print("\"id\":\"{s}\", .{neurona.id});
    try stdout.print("\"title\":\"{s}\", .{neurona.title});
    try stdout.print("\"type\":\"{s}\", .{@tagName(neurona.type)});
    try stdout.print("\"filepath\":\"{s}\", .{filepath});
    try stdout.print("\"tags\":{d},", .{neurona.tags.items.len});
    try stdout.print("\"connections\":{d}", .{neurona.connections.count()});
    try stdout.writeAll("}\n");
}

// Example CLI usage:
//
//   engram show test.001
//   → Displays test.001.md with all information
//
//   engram show req.auth.oauth2 --no-body
//   → Displays without body content
//
//   engram show test.oauth.001 --json
//   → Returns JSON for AI parsing
