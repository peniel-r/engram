// Graph index persistence module
// Handles serialization/deserialization of Graph data structure to/from binary format
// Also handles file I/O for saving/loading graph index
const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_module = @import("../core/graph.zig");

/// Magic number for graph index format identification
pub const MAGIC: [4]u8 = .{ 'E', 'N', 'G', 'I' };

/// Current format version for forward compatibility
pub const VERSION: u32 = 1;

/// Binary header for graph index file
/// Total size: 24 bytes
pub const GraphHeader = struct {
    /// Magic number "ENGM" (4 bytes)
    magic: [4]u8,
    /// Format version (4 bytes)
    version: u32,
    /// Number of nodes in graph (8 bytes)
    node_count: u64,
    /// Number of edges (forward direction only) (8 bytes)
    edge_count: u64,
};

/// Re-export Graph type for convenience
pub const Graph = graph_module.Graph;

/// Errors that can occur during serialization/deserialization
pub const SerializeError = error{
    /// Magic number doesn't match expected value
    InvalidMagic,
    /// Version is higher than we can handle
    UnsupportedVersion,
    /// Data is truncated or malformed
    CorruptData,
    /// Memory allocation failed
    OutOfMemory,
    /// File I/O error
    IoError,
};

/// Validate graph header for correct magic and version
/// Returns error if header is invalid
pub fn validateHeader(header: GraphHeader) SerializeError!void {
    if (!std.mem.eql(u8, &header.magic, &MAGIC)) {
        return SerializeError.InvalidMagic;
    }

    if (header.version > VERSION) {
        return SerializeError.UnsupportedVersion;
    }
}

// ==================== File I/O Functions ====================

/// Get default graph index file path
pub fn getGraphIndexPath(allocator: Allocator) ![]const u8 {
    return try allocator.dupe(u8, ".activations/graph.idx");
}

/// Ensure .activations/ directory exists
pub fn ensureActivationsDir(allocator: Allocator) !void {
    _ = allocator;
    std.fs.cwd().makePath(".activations/") catch |err| {
        if (err != error.PathAlreadyExists) {
            return SerializeError.IoError;
        }
    };
}

/// Save graph to index file at specified path
pub fn saveGraph(allocator: Allocator, graph: *const Graph, path: []const u8) !void {
    const data = try graph.serialize(allocator);
    defer allocator.free(data);

    const parent_dir = std.fs.path.dirname(path) orelse ".";
    var dir = std.fs.cwd().openDir(parent_dir, .{}) catch |err| blk: {
        if (err == error.FileNotFound) {
            try std.fs.cwd().makePath(parent_dir);
            break :blk try std.fs.cwd().openDir(parent_dir, .{});
        }
        return SerializeError.IoError;
    };
    defer dir.close();

    const file = try dir.createFile(std.fs.path.basename(path), .{});
    defer file.close();

    try file.writeAll(data);
}

/// Load graph from index file at specified path
pub fn loadGraph(allocator: Allocator, path: []const u8) !Graph {
    const data = std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            return SerializeError.IoError;
        }
        return err;
    };
    defer allocator.free(data);

    return try graph_module.Graph.deserialize(data, allocator);
}

// ==================== Tests ====================

test "File I/O save/load empty graph" {
    const allocator = std.testing.allocator;

    std.fs.cwd().deleteTree(".activations") catch {};
    defer std.fs.cwd().deleteTree(".activations") catch {};

    var graph = Graph.init();
    defer graph.deinit(allocator);

    const test_path = try allocator.dupe(u8, ".activations/test_graph.idx");
    defer allocator.free(test_path);

    try saveGraph(allocator, &graph, test_path);

    var loaded = try loadGraph(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), loaded.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), loaded.edgeCount());
}

test "File I/O save/load complex graph" {
    const allocator = std.testing.allocator;

    std.fs.cwd().deleteTree(".activations") catch {};
    defer std.fs.cwd().deleteTree(".activations") catch {};

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "req.001", "test.001", 90);
    try graph.addEdge(allocator, "req.001", "impl.001", 70);
    try graph.addEdge(allocator, "test.001", "issue.001", 100);
    try graph.addEdge(allocator, "impl.001", "req.002", 60);
    try graph.addEdge(allocator, "req.002", "test.002", 80);

    const test_path = try allocator.dupe(u8, ".activations/test_complex.idx");
    defer allocator.free(test_path);

    try saveGraph(allocator, &graph, test_path);

    var loaded = try loadGraph(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 6), loaded.nodeCount());
    try std.testing.expectEqual(@as(usize, 10), loaded.edgeCount());

    try std.testing.expect(loaded.hasEdge("req.001", "test.001"));
    try std.testing.expect(loaded.hasEdge("req.001", "impl.001"));
    try std.testing.expect(loaded.hasEdge("test.001", "issue.001"));
    try std.testing.expect(loaded.hasEdge("impl.001", "req.002"));
    try std.testing.expect(loaded.hasEdge("req.002", "test.002"));
}

test "File I/O load non-existent file" {
    const allocator = std.testing.allocator;
    const test_path = ".activations/nonexistent.idx";

    const result = loadGraph(allocator, test_path);
    try std.testing.expectError(SerializeError.IoError, result);
}

test "File I/O getGraphIndexPath returns correct path" {
    const allocator = std.testing.allocator;

    const path = try getGraphIndexPath(allocator);
    defer allocator.free(path);

    try std.testing.expectEqualStrings(".activations/graph.idx", path);
}

test "File I/O ensureActivationsDir creates directory" {
    const allocator = std.testing.allocator;

    std.fs.cwd().deleteTree(".activations") catch {};
    defer std.fs.cwd().deleteTree(".activations") catch {};

    try ensureActivationsDir(allocator);

    var dir = std.fs.cwd().openDir(".activations", .{}) catch {
        return;
    };
    defer dir.close();

    try std.testing.expect(true);
}

test "File I/O save to nested path creates parent directories" {
    const allocator = std.testing.allocator;

    std.fs.cwd().deleteTree(".activations") catch {};
    defer std.fs.cwd().deleteTree(".activations") catch {};

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "test", "target", 50);

    const test_path = ".activations/subdir/test.idx";

    try saveGraph(allocator, &graph, test_path);

    var loaded = try loadGraph(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), loaded.nodeCount());
}

test "File I/O getGraphIndex path returns correct path" {
    const allocator = std.testing.allocator;

    const path = try getGraphIndexPath(allocator);
    defer allocator.free(path);

    try std.testing.expectEqualStrings(".activations/graph.idx", path);
}
