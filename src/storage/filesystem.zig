// Filesystem operations for Neurona files
// Handles reading, writing, and scanning Neurona Markdown files
const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Connection = @import("../core/neurona.zig").Connection;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const frontmatter = @import("../utils/frontmatter.zig").Frontmatter;
const yaml = @import("../utils/yaml.zig");
const getString = yaml.getString;
const getInt = yaml.getInt;
const getBool = yaml.getBool;
const getArray = yaml.getArray;

pub const StorageError = error{
    FileNotFound,
    InvalidNeuronaFormat,
    MissingRequiredField,
    InvalidYaml,
    IoError,
    OutOfMemory,
};

/// Check if a file is a valid Neurona file
pub fn isNeuronaFile(filename: []const u8) bool {
    const ext = std.fs.path.extension(filename);
    return std.mem.eql(u8, ext, ".md");
}

/// Read a Neurona file and return a Neurona struct
pub fn readNeurona(allocator: Allocator, filepath: []const u8) !Neurona {
    // Read file content
    const content = std.fs.cwd().readFileAlloc(allocator, filepath, 10 * 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => return StorageError.FileNotFound,
            else => return StorageError.IoError,
        }
    };
    defer allocator.free(content);

    // Extract frontmatter
    const fm = try frontmatter.parse(allocator, content);
    defer fm.deinit(allocator);

    // Parse YAML
    const yaml_data = try yaml.Parser.parse(allocator, fm.content);
    defer {
        var it = yaml_data.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                .array => |*arr| arr.deinit(allocator),
                .object => |_| {}, // Skip object cleanup (not used)
                else => {},
            }
        }
        yaml_data.deinit();
    }

    // Convert YAML to Neurona
    return try yamlToNeurona(allocator, yaml_data, fm.body);
}

/// Convert parsed YAML frontmatter to Neurona struct
fn yamlToNeurona(allocator: Allocator, yaml_data: std.StringHashMap(yaml.Value), body: []const u8) !Neurona {
    _ = body; // TODO: Use body content for full Neurona

    var neurona = try Neurona.init(allocator);
    errdefer neurona.deinit(allocator);

    // Required fields: id, title
    const id_val = yaml_data.get("id") orelse return StorageError.MissingRequiredField;
    neurona.id = try allocator.dupe(u8, getString(id_val, ""));

    const title_val = yaml_data.get("title") orelse return StorageError.MissingRequiredField;
    neurona.title = try allocator.dupe(u8, getString(title_val, ""));

    // Tier 2 field: type
    if (yaml_data.get("type")) |type_val| {
        const type_str = getString(type_val, "concept");
        neurona.type = parseNeuronaType(type_str) catch .concept;
    }

    // Tier 2 field: updated
    if (yaml_data.get("updated")) |updated_val| {
        neurona.updated = try allocator.dupe(u8, getString(updated_val, ""));
    }

    // Tier 2 field: language
    if (yaml_data.get("language")) |lang_val| {
        neurona.language = try allocator.dupe(u8, getString(lang_val, "en"));
    }

    // Tier 1 field: tags
    if (yaml_data.get("tags")) |tags_val| {
        const tags = try getArray(tags_val, allocator, &[_][]const u8{});
        for (tags) |tag| {
            try neurona.tags.append(allocator, tag);
        }
        allocator.free(tags);
    }

    // Tier 2 field: connections
    if (yaml_data.get("connections")) |conn_val| {
        // TODO: Parse connection groups by type
        _ = conn_val;
    }

    // Tier 3 field: hash (optional)
    if (yaml_data.get("hash")) |hash_val| {
        neurona.hash = try allocator.dupe(u8, getString(hash_val, ""));
    }

    return neurona;
}

/// Parse Neurona type from string
fn parseNeuronaType(type_str: []const u8) !NeuronaType {
    if (std.mem.eql(u8, type_str, "concept")) return .concept;
    if (std.mem.eql(u8, type_str, "reference")) return .reference;
    if (std.mem.eql(u8, type_str, "artifact")) return .artifact;
    if (std.mem.eql(u8, type_str, "state_machine")) return .state_machine;
    if (std.mem.eql(u8, type_str, "lesson")) return .lesson;
    if (std.mem.eql(u8, type_str, "requirement")) return .requirement;
    if (std.mem.eql(u8, type_str, "test_case")) return .test_case;
    if (std.mem.eql(u8, type_str, "issue")) return .issue;
    if (std.mem.eql(u8, type_str, "feature")) return .feature;
    return error.UnknownType;
}

// ==================== Writing Functions ====================

/// Write a Neurona struct to a Markdown file
pub fn writeNeurona(allocator: Allocator, neurona: Neurona, filepath: []const u8) !void {
    // Generate YAML frontmatter
    const yaml_content = try neuronaToYaml(allocator, neurona);
    defer allocator.free(yaml_content);

    // Generate complete Markdown content
    const content = try generateMarkdown(allocator, yaml_content, "");
    defer allocator.free(content);

    // Write to file
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Convert Neurona struct to YAML frontmatter string
fn neuronaToYaml(allocator: Allocator, neurona: Neurona) ![]u8 {
    var yaml_buf = std.ArrayList(u8).init(allocator);
    errdefer yaml_buf.deinit();
    const writer = yaml_buf.writer();

    // Tier 1 fields
    try writer.print("id: {s}\n", .{neurona.id});
    try writer.print("title: {s}\n", .{neurona.title});

    // Tags (Tier 1)
    if (neurona.tags.items.len > 0) {
        try writer.writeAll("tags: [");
        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s}", .{tag});
        }
        try writer.writeAll("]\n");
    }

    // Tier 2 fields
    if (neurona.type != .concept) {
        try writer.print("type: {s}\n", .{@tagName(neurona.type)});
    }

    if (neurona.updated.len > 0) {
        try writer.print("updated: \"{s}\"\n", .{neurona.updated});
    }

    if (!std.mem.eql(u8, neurona.language, "en")) {
        try writer.print("language: {s}\n", .{neurona.language});
    }

    // Tier 3 fields (optional)
    if (neurona.hash) |hash| {
        try writer.print("hash: {s}\n", .{hash});
    }

    return yaml_buf.toOwnedSlice();
}

/// Generate complete Markdown file content from Neurona
fn generateMarkdown(allocator: Allocator, yaml_content: []const u8, body: []const u8) ![]u8 {
    var content = std.ArrayList(u8).init(allocator);
    errdefer content.deinit();
    const writer = content.writer();

    // Write frontmatter delimiters
    try writer.writeAll("---\n");
    try writer.writeAll(yaml_content);
    try writer.writeAll("---\n\n");

    // Write body
    if (body.len > 0) {
        try writer.writeAll(body);
    }

    return content.toOwnedSlice();
}

// ==================== Directory Scanning Functions ====================

/// List all Neurona file paths in a directory
pub fn listNeuronaFiles(allocator: Allocator, directory: []const u8) ![][]const u8 {
    var dir = try std.fs.cwd().openDir(directory, .{ .iterate = true });
    defer dir.close();

    var files = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (files.items) |file| allocator.free(file);
        files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (isNeuronaFile(entry.name)) {
            const path = try std.fs.path.join(allocator, &.{ directory, entry.name });
            try files.append(allocator, path);
        }
    }

    return files.toOwnedSlice();
}

/// Scan directory and load all Neurona files
pub fn scanNeuronas(allocator: Allocator, directory: []const u8) ![]Neurona {
    const filepaths = try listNeuronaFiles(allocator, directory);
    defer {
        for (filepaths) |path| allocator.free(path);
        allocator.free(filepaths);
    }

    var neuronas = std.ArrayList(Neurona).init(allocator);
    errdefer {
        for (neuronas.items) |*n| n.deinit(allocator);
        neuronas.deinit(allocator);
    }

    for (filepaths) |filepath| {
        const neurona = readNeurona(allocator, filepath) catch |err| {
            // Skip invalid files but continue scanning
            std.debug.print("Warning: Skipping {s}: {}\n", .{ filepath, err });
            continue;
        };
        try neuronas.append(allocator, neurona);
    }

    return neuronas.toOwnedSlice();
}

// ==================== Tests ====================

test "isNeuronaFile identifies .md files" {
    try std.testing.expect(isNeuronaFile("test.md"));
    try std.testing.expect(isNeuronaFile("neurona.md"));
    try std.testing.expect(isNeuronaFile("2026-01-22.md"));
}

test "isNeuronaFile rejects non-.md files" {
    try std.testing.expect(!isNeuronaFile("test.txt"));
    try std.testing.expect(!isNeuronaFile("test.json"));
    try std.testing.expect(!isNeuronaFile("neurona"));
}

test "isNeuronaFile handles empty strings" {
    try std.testing.expect(!isNeuronaFile(""));
    try std.testing.expect(!isNeuronaFile("   "));
}

test "readNeurona parses valid Tier 1 file" {
    const allocator = std.testing.allocator;

    // Create test fixture
    const test_path = "test_neurona_tier1.md";
    const test_content =
        \\---
        \\id: test.001
        \\title: Test Neurona
        \\tags: [test, example]
        \\---
        \\
        \\# Test Content
        \\This is test content.
    ;

    std.fs.cwd().writeFile(test_path, test_content) catch |err| {
        std.debug.print("Error writing test file: {}\n", .{err});
        return error.TestSetupFailed;
    };
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const neurona = try readNeurona(allocator, test_path);
    defer neurona.deinit(allocator);

    try std.testing.expectEqualStrings("test.001", neurona.id);
    try std.testing.expectEqualStrings("Test Neurona", neurona.title);
    try std.testing.expectEqual(@as(usize, 2), neurona.tags.items.len);
    try std.testing.expectEqualStrings("test", neurona.tags.items[0]);
    try std.testing.expectEqualStrings("example", neurona.tags.items[1]);
}

test "readNeurona returns error for missing frontmatter" {
    const allocator = std.testing.allocator;

    const test_path = "test_no_frontmatter.md";
    const test_content = "# Just content";

    std.fs.cwd().writeFile(test_path, test_content) catch |err| {
        std.debug.print("Error writing test file: {}\n", .{err});
        return error.TestSetupFailed;
    };
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const result = readNeurona(allocator, test_path);
    try std.testing.expectError(StorageError.InvalidNeuronaFormat, result);
}

test "readNeurona returns error for missing required fields" {
    const allocator = std.testing.allocator;

    const test_path = "test_missing_fields.md";
    const test_content =
        \\---
        \\tags: [test]
        \\---
        \\
        \\# Content
    ;

    std.fs.cwd().writeFile(test_path, test_content) catch |err| {
        std.debug.print("Error writing test file: {}\n", .{err});
        return error.TestSetupFailed;
    };
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const result = readNeurona(allocator, test_path);
    try std.testing.expectError(StorageError.MissingRequiredField, result);
}

test "readNeurona returns error for file not found" {
    const allocator = std.testing.allocator;

    const result = readNeurona(allocator, "nonexistent.md");
    try std.testing.expectError(StorageError.FileNotFound, result);
}

test "writeNeurona writes valid Tier 1 file" {
    const allocator = std.testing.allocator;

    // Create test Neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    neurona.id = try allocator.dupe(u8, "test.001");
    defer allocator.free(neurona.id);
    neurona.title = try allocator.dupe(u8, "Test Neurona");
    defer allocator.free(neurona.title);

    const tag1 = try allocator.dupe(u8, "test");
    defer allocator.free(tag1);
    try neurona.tags.append(allocator, tag1);

    // Write to file
    const test_path = "test_write_tier1.md";
    try writeNeurona(allocator, neurona, test_path);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Verify file exists and has correct content
    const content = try std.fs.cwd().readFileAlloc(allocator, test_path, 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "id: test.001") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "title: Test Neurona") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "---") != null);
}

test "writeNeurona write and read roundtrip Tier 2" {
    const allocator = std.testing.allocator;

    // Create test Neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    neurona.id = try allocator.dupe(u8, "test.002");
    defer allocator.free(neurona.id);
    neurona.title = try allocator.dupe(u8, "Test Requirement");
    defer allocator.free(neurona.title);
    neurona.type = .requirement;
    neurona.updated = try allocator.dupe(u8, "2026-01-22");
    defer allocator.free(neurona.updated);

    // Write to file
    const test_path = "test_write_tier2.md";
    try writeNeurona(allocator, neurona, test_path);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Read back
    const loaded = try readNeurona(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqualStrings(neurona.id, loaded.id);
    try std.testing.expectEqualStrings(neurona.title, loaded.title);
    try std.testing.expectEqual(.requirement, loaded.type);
}

test "listNeuronaFiles lists .md files" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_neuronas_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    try std.fs.cwd().writeFile(try std.fs.path.join(allocator, &.{ test_dir, "test1.md" }), "content");
    try std.fs.cwd().writeFile(try std.fs.path.join(allocator, &.{ test_dir, "test2.md" }), "content");
    try std.fs.cwd().writeFile(try std.fs.path.join(allocator, &.{ test_dir, "not_md.txt" }), "content");

    // List files
    const files = try listNeuronaFiles(allocator, test_dir);
    defer {
        for (files) |file| allocator.free(file);
        allocator.free(files);
    }

    try std.testing.expectEqual(@as(usize, 2), files.len);
}

test "scanNeuronas loads all valid Neuronas" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_scan_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona files
    const path1 = try std.fs.path.join(allocator, &.{ test_dir, "test1.md" });
    const path2 = try std.fs.path.join(allocator, &.{ test_dir, "test2.md" });

    try std.fs.cwd().writeFile(path1,
        \\---
        \\id: test.001
        \\title: Test One
        \\tags: [test]
        \\---
        \\
        \\# Content
    );
    try std.fs.cwd().writeFile(path2,
        \\---
        \\id: test.002
        \\title: Test Two
        \\tags: [test]
        \\---
        \\
        \\# Content
    );

    // Scan directory
    const neuronas = try scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 2), neuronas.len);
}

test "scanNeuronas skips invalid files" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_invalid_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create valid and invalid files
    const valid_path = try std.fs.path.join(allocator, &.{ test_dir, "valid.md" });
    const invalid_path = try std.fs.path.join(allocator, &.{ test_dir, "invalid.md" });

    try std.fs.cwd().writeFile(valid_path,
        \\---
        \\id: test.001
        \\title: Valid
        \\---
        \\# Content
    );
    try std.fs.cwd().writeFile(invalid_path, "No frontmatter");

    // Scan directory
    const neuronas = try scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 1), neuronas.len);
    try std.testing.expectEqualStrings("test.001", neuronas[0].id);
}
