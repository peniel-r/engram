// File: src/cli/init.zig
// The `engram init` command for initializing a new Cortex
// MIGRATED: Now uses Phase 3 CLI utilities (HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cortex = @import("../core/cortex.zig").Cortex;
const timestamp = @import("../utils/timestamp.zig");

// Import Phase 3 CLI utilities
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Cortex types supported
pub const CortexType = enum {
    notes,
    alm,
    knowledge,

    pub fn fromString(s: []const u8) ?CortexType {
        if (std.mem.eql(u8, s, "notes")) return .notes;
        if (std.mem.eql(u8, s, "alm")) return .alm;
        if (std.mem.eql(u8, s, "knowledge")) return .knowledge;
        return null;
    }

    pub fn toString(self: CortexType) []const u8 {
        return switch (self) {
            .notes => "notes",
            .alm => "alm",
            .knowledge => "knowledge",
        };
    }
};

/// Configuration for Cortex initialization
pub const InitConfig = struct {
    /// Cortex name (required)
    name: []const u8,

    /// Cortex type (default: alm)
    cortex_type: CortexType = .alm,

    /// Default language (default: en)
    default_language: []const u8 = "en",

    /// Force overwrite existing Cortex (default: false)
    force: bool = false,

    /// Verbose output (default: false)
    verbose: bool = false,
};

/// Directory structure for a Cortex
const DirectoryStructure = struct {
    root: []const u8,
    neuronas: []const u8,
    activations: []const u8,
    cache: []const u8,
    assets: []const u8,

    pub fn deinit(self: *DirectoryStructure, allocator: Allocator) void {
        allocator.free(self.root);
        allocator.free(self.neuronas);
        allocator.free(self.activations);
        allocator.free(self.cache);
        allocator.free(self.assets);
    }
};

/// Initialize a new Cortex
pub fn execute(allocator: Allocator, config: InitConfig) !void {
    // Step 1: Validate and prepare directory structure
    var dirs = try prepareDirectoryStructure(allocator, config.name);
    defer dirs.deinit(allocator);

    // Step 2: Check if Cortex already exists
    try validateExistingCortex(&dirs, config.force);

    // Step 3: Create directory structure
    try createDirectoryStructure(&dirs, config.verbose);

    // Step 4: Generate and write cortex.json
    try writeCortexConfig(allocator, &dirs, config, config.verbose);

    // Step 5: Create README.md
    try writeReadme(allocator, &dirs, config, config.verbose);

    // Step 6: Create .gitignore for activations
    try writeGitignore(&dirs, config.verbose);

    // Step 7: Output success message
    try outputSuccess(&dirs, config);
}

/// Prepare directory paths based on Cortex name
fn prepareDirectoryStructure(allocator: Allocator, name: []const u8) !DirectoryStructure {
    const root = try allocator.dupe(u8, name);
    errdefer allocator.free(root);

    const neuronas = try std.fs.path.join(allocator, &.{ name, "neuronas" });
    errdefer allocator.free(neuronas);

    const activations = try std.fs.path.join(allocator, &.{ name, ".activations" });
    errdefer allocator.free(activations);

    const cache = try std.fs.path.join(allocator, &.{ name, ".activations", "cache" });
    errdefer allocator.free(cache);

    const assets = try std.fs.path.join(allocator, &.{ name, "assets" });
    errdefer allocator.free(assets);

    return DirectoryStructure{
        .root = root,
        .neuronas = neuronas,
        .activations = activations,
        .cache = cache,
        .assets = assets,
    };
}

/// Validate that we're not overwriting an existing Cortex
fn validateExistingCortex(dirs: *const DirectoryStructure, force: bool) !void {
    // Check if root directory exists
    var root_dir = std.fs.cwd().openDir(dirs.root, .{}) catch {
        // Directory doesn't exist, which is good
        return;
    };
    defer root_dir.close();

    // Root directory exists, check if it's a Cortex
    _ = root_dir.access("cortex.json", .{}) catch {
        // File doesn't exist
        return;
    };

    // This looks like an existing Cortex
    if (force) {
        // Overwriting is allowed
    } else {
        return error.CortexAlreadyExists;
    }
}

/// Create directory structure
fn createDirectoryStructure(dirs: *const DirectoryStructure, verbose: bool) !void {
    if (verbose) {
        try HumanOutput.printInfo("Creating directory structure...");
    }

    // Create root directory
    try std.fs.cwd().makeDir(dirs.root);

    // Create neuronas directory
    try std.fs.cwd().makePath(dirs.neuronas);

    // Create .activations directory
    try std.fs.cwd().makePath(dirs.activations);

    // Create cache directory
    try std.fs.cwd().makePath(dirs.cache);

    // Create assets directory
    try std.fs.cwd().makePath(dirs.assets);

    // Create assets subdirectories
    const diagrams_path = try std.fs.path.join(std.heap.page_allocator, &.{ dirs.assets, "diagrams" });
    defer std.heap.page_allocator.free(diagrams_path);
    try std.fs.cwd().makePath(diagrams_path);

    const pdfs_path = try std.fs.path.join(std.heap.page_allocator, &.{ dirs.assets, "pdfs" });
    defer std.heap.page_allocator.free(pdfs_path);
    try std.fs.cwd().makePath(pdfs_path);

    if (verbose) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("  ✓ {s}/\n", .{dirs.root});
        try stdout.print("  ✓ {s}/\n", .{dirs.neuronas});
        try stdout.print("  ✓ {s}/\n", .{dirs.activations});
        try stdout.print("  ✓ {s}/\n", .{dirs.cache});
        try stdout.print("  ✓ {s}/\n", .{dirs.assets});
        try stdout.flush();
    }
}

/// Generate and write cortex.json configuration
fn writeCortexConfig(allocator: Allocator, dirs: *const DirectoryStructure, config: InitConfig, verbose: bool) !void {
    if (verbose) {
        try HumanOutput.printInfo("Generating cortex.json...");
    }

    // Create default Cortex configuration
    var cortex = try Cortex.default(allocator, generateCortexId(config.name), config.name);
    defer cortex.deinit(allocator);

    // Override type if specified
    allocator.free(cortex.capabilities.type);
    cortex.capabilities.type = try allocator.dupe(u8, config.cortex_type.toString());

    // Override default language if specified
    allocator.free(cortex.capabilities.default_language);
    cortex.capabilities.default_language = try allocator.dupe(u8, config.default_language);

    // For ALM type, enable semantic search and LLM integration
    if (config.cortex_type == .alm) {
        cortex.capabilities.semantic_search = true;
        cortex.capabilities.llm_integration = true;

        allocator.free(cortex.indices.embedding_model);
        cortex.indices.embedding_model = try allocator.dupe(u8, "text-embedding-ada-002");
    }

    // Validate configuration
    try cortex.validate();

    // Write to file
    const cortex_json_path = try std.fs.path.join(allocator, &.{ dirs.root, "cortex.json" });
    defer allocator.free(cortex_json_path);

    const file = try std.fs.cwd().createFile(cortex_json_path, .{ .truncate = true });
    defer file.close();

    // Build JSON content
    const semantic_search_str = if (cortex.capabilities.semantic_search) "true" else "false";
    const llm_integration_str = if (cortex.capabilities.llm_integration) "true" else "false";

    const json_content = try std.fmt.allocPrint(allocator, "{{\n" ++
        "  \"id\": \"{s}\",\n" ++
        "  \"name\": \"{s}\",\n" ++
        "  \"version\": \"{s}\",\n" ++
        "  \"spec_version\": \"{s}\",\n" ++
        "  \"capabilities\": {{\n" ++
        "    \"type\": \"{s}\",\n" ++
        "    \"semantic_search\": {s},\n" ++
        "    \"llm_integration\": {s},\n" ++
        "    \"default_language\": \"{s}\"\n" ++
        "  }},\n" ++
        "  \"indices\": {{\n" ++
        "    \"strategy\": \"{s}\",\n" ++
        "    \"embedding_model\": \"{s}\"\n" ++
        "  }}\n" ++
        "}}\n", .{ cortex.id, cortex.name, cortex.version, cortex.spec_version, cortex.capabilities.type, semantic_search_str, llm_integration_str, cortex.capabilities.default_language, cortex.indices.strategy, cortex.indices.embedding_model });
    defer allocator.free(json_content);

    try file.writeAll(json_content);

    if (verbose) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("  ✓ {s}\n", .{cortex_json_path});
        try stdout.flush();
    }
}

/// Generate a cortex ID from name
fn generateCortexId(name: []const u8) []const u8 {
    // For now, just use name as-is
    // In a real implementation, this would sanitize name
    return name;
}

/// Create README.md with Cortex overview
fn writeReadme(allocator: Allocator, dirs: *const DirectoryStructure, config: InitConfig, verbose: bool) !void {
    if (verbose) {
        try HumanOutput.printInfo("Creating README.md...");
    }

    const readme_path = try std.fs.path.join(allocator, &.{ dirs.root, "README.md" });
    defer allocator.free(readme_path);

    const file = try std.fs.cwd().createFile(readme_path, .{ .truncate = true });
    defer file.close();

    // Build README content based on type
    const type_details = switch (config.cortex_type) {
        .notes =>
        \\This is a **Notes** Cortex, optimized for:
        \\- Personal knowledge management
        \\- Connected note-taking
        \\- Concept linking and discovery
        \\
        ,
        .alm =>
        \\This is an **ALM (Application Lifecycle Management)** Cortex, optimized for:
        \\- Requirements management
        \\- Test case tracking
        \\- Issue and defect management
        \\- Traceability and impact analysis
        \\
        \\### ALM-Specific Commands
        \\
        \\```bash
        \\# Create a requirement
        \\engram new requirement "User Authentication"
        \\
        \\# Create a test case
        \\engram new test_case "Auth Test" --validates req.auth.oauth2
        \\
        \\# Create an issue
        \\engram new issue "Login bug" --priority 1
        \\
        \\# Trace dependencies
        \\engram trace req.auth.oauth2
        \\
        \\# Check release readiness
        \\engram release-status
        \\```
        \\
        ,
        .knowledge =>
        \\This is a **Knowledge** Cortex, optimized for:
        \\- Documentation repositories
        \\- Technical knowledge bases
        \\- API and specification documents
        \\
        ,
    };

    const ts = try timestamp.getCurrentTimestamp(allocator);
    defer allocator.free(ts);

    const readme_content = try std.fmt.allocPrint(allocator, "# {s}\n\n" ++
        "This Cortex is managed by **Engram** - a high-performance CLI tool implementing Neurona Knowledge Protocol.\n\n" ++
        "## Overview\n\n" ++
        "**Type**: {s}\n\n" ++
        "**Language**: {s}\n\n" ++
        "## Directory Structure\n\n" ++
        "```\n{s}/\n" ++
        "├── cortex.json              # Cortex configuration and DNA\n" ++
        "├── README.md                # This file\n" ++
        "├── neuronas/                # Your Neuronas (knowledge nodes)\n" ++
        "├── .activations/            # System-generated indices (Git-ignored)\n" ++
        "│   ├── graph.idx            # Graph adjacency list\n" ++
        "│   ├── vectors.bin          # Vector embeddings (if semantic search enabled)\n" ++
        "│   └── cache/               # Cached computations\n" ++
        "└── assets/                  # Static files (diagrams, PDFs, etc.)\n" ++
        "```\n\n" ++
        "## Getting Started\n\n" ++
        "### Create a Neurona\n\n" ++
        "```bash\ncd {s}\n" ++
        "engram new concept \"My First Note\"\n" ++
        "```\n\n" ++
        "### View a Neurona\n\n" ++
        "```bash\n" ++
        "engram show my.first.note\n" ++
        "```\n\n" ++
        "### List All Neuronas\n\n" ++
        "```bash\n" ++
        "engram status\n" ++
        "```\n\n" ++
        "## Cortex Type Details\n\n" ++
        "{s}\n" ++
        "## Learn More\n\n" ++
        "- [Neurona Spec](https://github.com/modelcontextprotocol/)\n" ++
        "- [Engram Documentation](https://github.com/yourusername/Engram)\n\n" ++
        "---\n\n" ++
        "Created with Engram on {s}\n\n", .{ config.name, config.cortex_type.toString(), config.default_language, config.name, config.name, type_details, ts });
    defer allocator.free(readme_content);

    try file.writeAll(readme_content);

    if (verbose) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("  ✓ {s}\n", .{readme_path});
        try stdout.flush();
    }
}

/// Create .gitignore for .activations directory
fn writeGitignore(dirs: *const DirectoryStructure, verbose: bool) !void {
    if (verbose) {
        try HumanOutput.printInfo("Creating .gitignore...");
    }

    const gitignore_path = try std.fs.path.join(std.heap.page_allocator, &.{ dirs.activations, ".gitignore" });
    defer std.heap.page_allocator.free(gitignore_path);

    const file = try std.fs.cwd().createFile(gitignore_path, .{ .truncate = true });
    defer file.close();

    const gitignore_content = "*\n!.gitignore\n";
    try file.writeAll(gitignore_content);

    if (verbose) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("  ✓ {s}\n", .{gitignore_path});
        try stdout.flush();
    }
}

/// Output success message
fn outputSuccess(dirs: *const DirectoryStructure, config: InitConfig) !void {
    try HumanOutput.printSuccess("Cortex initialized successfully!");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("\n  Name: {s}\n", .{config.name});
    try stdout.print("  Type: {s}\n", .{config.cortex_type.toString()});
    try stdout.print("  Location: {s}/\n\n", .{dirs.root});

    try stdout.print("Next steps:\n", .{});
    try stdout.print("  cd {s}\n", .{dirs.root});
    try stdout.print("  engram new concept \"Hello World\"\n", .{});
    try stdout.print("  engram show hello.world\n\n", .{});
    try stdout.flush();
}

// Unit tests

test "CortexType fromString" {
    try std.testing.expectEqual(CortexType.notes, CortexType.fromString("notes").?);
    try std.testing.expectEqual(CortexType.alm, CortexType.fromString("alm").?);
    try std.testing.expectEqual(CortexType.knowledge, CortexType.fromString("knowledge").?);
    try std.testing.expectEqual(null, CortexType.fromString("invalid"));
}

test "CortexType toString" {
    try std.testing.expectEqualStrings("notes", CortexType.notes.toString());
    try std.testing.expectEqualStrings("alm", CortexType.alm.toString());
    try std.testing.expectEqualStrings("knowledge", CortexType.knowledge.toString());
}

test "validateExistingCortex returns error when Cortex exists" {
    const allocator = std.testing.allocator;

    // Clean up from previous runs
    std.fs.cwd().deleteTree("test_existing_cortex") catch {};
    defer std.fs.cwd().deleteTree("test_existing_cortex") catch {};

    // Create a temporary Cortex
    const test_config = InitConfig{
        .name = "test_existing_cortex",
        .cortex_type = .notes,
        .force = false,
        .verbose = false,
    };

    var dirs = try prepareDirectoryStructure(allocator, test_config.name);
    defer dirs.deinit(allocator);

    // Create Cortex
    try createDirectoryStructure(&dirs, false);

    // Create a simple cortex.json to mark it as a Cortex
    const cortex_json_path = try std.fs.path.join(allocator, &.{ dirs.root, "cortex.json" });
    defer allocator.free(cortex_json_path);

    const file = try std.fs.cwd().createFile(cortex_json_path, .{});
    defer file.close();

    // Try to validate - should return error
    try std.testing.expectError(error.CortexAlreadyExists, validateExistingCortex(&dirs, false));
}

test "validateExistingCortex succeeds when force is true" {
    const allocator = std.testing.allocator;

    // Clean up from previous runs
    std.fs.cwd().deleteTree("test_force_cortex") catch {};
    defer std.fs.cwd().deleteTree("test_force_cortex") catch {};

    // Create a temporary Cortex
    const test_config = InitConfig{
        .name = "test_force_cortex",
        .cortex_type = .notes,
        .force = true,
        .verbose = false,
    };

    var dirs = try prepareDirectoryStructure(allocator, test_config.name);
    defer dirs.deinit(allocator);

    // Create Cortex
    try createDirectoryStructure(&dirs, false);

    // Create a simple cortex.json
    const cortex_json_path = try std.fs.path.join(allocator, &.{ dirs.root, "cortex.json" });
    defer allocator.free(cortex_json_path);

    const file = try std.fs.cwd().createFile(cortex_json_path, .{});
    defer file.close();

    // Try to validate with force=true - should succeed
    try validateExistingCortex(&dirs, true);
}
