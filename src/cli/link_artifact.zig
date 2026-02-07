// File: src/cli/link_artifact.zig
// The `engram link-artifact` command for linking source files to requirements
// Automatically creates artifact Neuronas and links them to implementing requirements

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Connection = @import("../core/neurona.zig").Connection;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const Context = @import("../core/neurona.zig").Context;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const writeNeurona = @import("../storage/filesystem.zig").writeNeurona;
const findNeuronaPath = @import("../storage/filesystem.zig").findNeuronaPath;
const generateId = @import("../utils/id_generator.zig").generateId;
const getCurrentTimestamp = @import("../utils/timestamp.zig").getCurrentTimestamp;
const uri_parser = @import("../utils/uri_parser.zig");

/// Link artifact configuration
pub const LinkArtifactConfig = struct {
    requirement_id: []const u8,
    source_files: std.ArrayListUnmanaged([]const u8),
    runtime: []const u8,
    auto_create: bool = true,
    language_version: ?[]const u8 = null,
    safe_to_exec: bool = false,
    verbose: bool = false,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Artifact link result
pub const LinkResult = struct {
    artifact_id: []const u8,
    source_file: []const u8,
    requirement_id: []const u8,
    created: bool,

    pub fn deinit(self: *LinkResult, allocator: Allocator) void {
        allocator.free(self.artifact_id);
        allocator.free(self.source_file);
        allocator.free(self.requirement_id);
    }
};

/// Main command handler
pub fn execute(allocator: Allocator, config: LinkArtifactConfig) !void {
    // Determine neuronas directory
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            std.debug.print("Error: No cortex found in current directory or within 3 directory levels.\n", .{});
            std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
            std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
            std.process.exit(1);
        }
        return err;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // Step 1: Verify requirement exists
    const req_filepath = try findNeuronaPath(allocator, neuronas_dir, config.requirement_id);
    defer allocator.free(req_filepath);

    var requirement = try readNeurona(allocator, req_filepath);
    defer requirement.deinit(allocator);

    if (requirement.type != .requirement) {
        std.debug.print("Error: '{s}' is not a requirement\n", .{config.requirement_id});
        return error.InvalidNeuronaType;
    }

    // Step 2: Process each source file
    var results = std.ArrayListUnmanaged(LinkResult){};
    defer {
        for (results.items) |*r| r.deinit(allocator);
        results.deinit(allocator);
    }

    for (config.source_files.items) |source_file| {
        const result = try linkArtifactFile(allocator, config, source_file, neuronas_dir);
        try results.append(allocator, result);
    }

    // Step 3: Update requirement's connections
    for (results.items) |result| {
        if (!result.created) continue;

        const conn = Connection{
            .target_id = try allocator.dupe(u8, result.artifact_id),
            .connection_type = .implemented_by,
            .weight = 100,
        };
        try requirement.addConnection(allocator, conn);
    }

    if (results.items.len > 0) {
        // Update requirement timestamp
        allocator.free(requirement.updated);
        requirement.updated = try getCurrentTimestamp(allocator);

        // Write updated requirement
        try writeNeurona(allocator, requirement, req_filepath, false);

        if (config.verbose) {
            std.debug.print("Updated requirement {s}\n", .{config.requirement_id});
        }
    }

    // Step 4: Output results
    if (config.json_output) {
        try outputJson(results.items);
    } else {
        try outputResults(results.items, config.verbose);
    }
}

/// Link a single source file to requirement
fn linkArtifactFile(allocator: Allocator, config: LinkArtifactConfig, source_file: []const u8, neuronas_dir: []const u8) !LinkResult {
    // Extract filename from path
    const filename = std.fs.path.basename(source_file);

    // Check if artifact already exists
    const artifact_id = try generateArtifactId(allocator, filename);
    const existing_path = findNeuronaPath(allocator, neuronas_dir, artifact_id) catch |err| {
        if (err == error.NeuronaNotFound) {
            // Create new artifact
            var artifact = try createArtifact(allocator, config, source_file, artifact_id);
            defer artifact.deinit(allocator);

            const filename_with_ext = try std.fmt.allocPrint(allocator, "{s}.md", .{artifact_id});
            defer allocator.free(filename_with_ext);

            const artifact_filepath = try std.fs.path.join(allocator, &.{ neuronas_dir, filename_with_ext });
            defer allocator.free(artifact_filepath);

            try writeNeurona(allocator, artifact, artifact_filepath, false);

            // Add reverse connection to artifact
            const conn = Connection{
                .target_id = try allocator.dupe(u8, config.requirement_id),
                .connection_type = .implements,
                .weight = 100,
            };
            try artifact.addConnection(allocator, conn);

            // Write artifact with connection
            try writeNeurona(allocator, artifact, artifact_filepath, false);

            return LinkResult{
                .artifact_id = try allocator.dupe(u8, artifact_id),
                .source_file = try allocator.dupe(u8, source_file),
                .requirement_id = try allocator.dupe(u8, config.requirement_id),
                .created = true,
            };
        }
        return err;
    };
    defer allocator.free(existing_path);

    // Artifact already exists, just return existing
    return LinkResult{
        .artifact_id = try allocator.dupe(u8, artifact_id),
        .source_file = try allocator.dupe(u8, source_file),
        .requirement_id = try allocator.dupe(u8, config.requirement_id),
        .created = false,
    };
}

/// Create a new artifact Neurona
fn createArtifact(allocator: Allocator, config: LinkArtifactConfig, source_file: []const u8, artifact_id: []const u8) !Neurona {
    var neurona = try Neurona.init(allocator);
    errdefer neurona.deinit(allocator);

    // Set ID
    allocator.free(neurona.id);
    neurona.id = try allocator.dupe(u8, artifact_id);

    // Set title from filename
    allocator.free(neurona.title);
    const filename = std.fs.path.basename(source_file);
    neurona.title = try allocator.dupe(u8, filename);

    // Set type to artifact
    neurona.type = .artifact;

    // Add artifact-related tag
    try neurona.tags.append(allocator, try allocator.dupe(u8, "source"));

    // Set updated timestamp
    allocator.free(neurona.updated);
    neurona.updated = try getCurrentTimestamp(allocator);

    // Initialize artifact context
    neurona.context = Context{
        .artifact = .{
            .runtime = try allocator.dupe(u8, config.runtime),
            .file_path = try allocator.dupe(u8, source_file),
            .safe_to_exec = config.safe_to_exec,
            .language_version = if (config.language_version) |v|
                try allocator.dupe(u8, v)
            else
                null,
            .last_modified = try getCurrentTimestamp(allocator),
        },
    };

    // Add connection to requirement
    const conn = Connection{
        .target_id = try allocator.dupe(u8, config.requirement_id),
        .connection_type = .implements,
        .weight = 100,
    };
    try neurona.addConnection(allocator, conn);

    return neurona;
}

/// Generate artifact ID from filename
fn generateArtifactId(allocator: Allocator, filename: []const u8) ![]const u8 {
    // Sanitize: replace dots and spaces with dashes
    var sanitized = std.ArrayListUnmanaged(u8){};
    defer sanitized.deinit(allocator);

    for (filename) |c| {
        if (c == '.' or c == ' ') {
            try sanitized.append(allocator, '-');
        } else if (std.ascii.isAlphanumeric(c)) {
            try sanitized.append(allocator, c);
        }
    }

    // Generate artifact ID: art-<sanitized-filename>
    return std.fmt.allocPrint(allocator, "art-{s}", .{sanitized.items});
}

/// Output results in human-readable format
fn outputResults(results: []const LinkResult, verbose: bool) !void {
    _ = verbose;

    std.debug.print("\n🔗 Artifact Linking Results\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    var created_count: usize = 0;
    var existing_count: usize = 0;

    for (results) |r| {
        const status = if (r.created) "✓ Created" else "⊘ Existing";
        if (r.created) created_count += 1 else existing_count += 1;

        std.debug.print("  {s}: {s} → {s}\n", .{ status, r.source_file, r.artifact_id });
        std.debug.print("         Implements: {s}\n", .{r.requirement_id});
        std.debug.print("\n", .{});
    }

    std.debug.print("Summary: {d} created, {d} existing\n", .{ created_count, existing_count });
}

/// JSON output for AI parsing
fn outputJson(results: []const LinkResult) !void {
    std.debug.print("[", .{});
    for (results, 0..) |r, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{\"artifact_id\":\"{s}\",", .{r.artifact_id});
        std.debug.print("\"source_file\":\"{s}\",", .{r.source_file});
        std.debug.print("\"requirement_id\":\"{s}\",", .{r.requirement_id});
        const created_val: u32 = if (r.created) 1 else 0;
        std.debug.print("\"created\":{d}}}", .{created_val});
    }
    std.debug.print("]\n", .{});
}

// ==================== Tests ====================

test "LinkArtifactConfig creates correctly" {
    const allocator = std.testing.allocator;

    var source_files = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (source_files.items) |f| allocator.free(f);
        source_files.deinit(allocator);
    }

    try source_files.append(allocator, try allocator.dupe(u8, "src/main.zig"));

    const config = LinkArtifactConfig{
        .requirement_id = "req.auth",
        .source_files = source_files,
        .runtime = "zig",
        .auto_create = true,
        .language_version = null,
        .safe_to_exec = false,
        .verbose = false,
        .cortex_dir = "neuronas",
    };

    try std.testing.expectEqualStrings("req.auth", config.requirement_id);
    try std.testing.expectEqual(@as(usize, 1), config.source_files.items.len);
}

test "generateArtifactId generates valid ID" {
    const allocator = std.testing.allocator;

    const id1 = try generateArtifactId(allocator, "main.zig");
    defer allocator.free(id1);
    try std.testing.expectEqualStrings("art-main-zig", id1);

    const id2 = try generateArtifactId(allocator, "auth.oauth2.ts");
    defer allocator.free(id2);
    try std.testing.expectEqualStrings("art-auth-oauth2-ts", id2);

    const id3 = try generateArtifactId(allocator, "test file.py");
    defer allocator.free(id3);
    try std.testing.expectEqualStrings("art-test-file-py", id3);
}

test "LinkResult stores correctly" {
    const allocator = std.testing.allocator;

    var result = LinkResult{
        .artifact_id = try allocator.dupe(u8, "art.main-zig"),
        .source_file = try allocator.dupe(u8, "src/main.zig"),
        .requirement_id = try allocator.dupe(u8, "req.auth"),
        .created = true,
    };
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("art.main-zig", result.artifact_id);
    try std.testing.expectEqualStrings("src/main.zig", result.source_file);
    try std.testing.expectEqualStrings("req.auth", result.requirement_id);
    try std.testing.expectEqual(true, result.created);
}
