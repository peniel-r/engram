// URI parser for Neurona system
// Handles neurona://<cortex-id>/<neurona-id> URIs
const std = @import("std");
const Allocator = std.mem.Allocator;

const SchemeError = error{
    InvalidScheme,
    MalformedURI,
    MissingComponent,
    OutOfMemory,
};

/// Parsed URI structure
pub const URI = struct {
    scheme: []const u8,
    cortex_id: []const u8,
    neurona_id: []const u8,

    /// Free all allocated strings
    pub fn deinit(self: *URI, allocator: Allocator) void {
        allocator.free(self.scheme);
        allocator.free(self.cortex_id);
        allocator.free(self.neurona_id);
    }

    /// Parse URI string into URI struct
    /// Format: neurona://<cortex-id>/<neurona-id>
    pub fn parse(allocator: Allocator, uri_str: []const u8) !URI {
        const expected_scheme = "neurona://";

        if (uri_str.len < expected_scheme.len) {
            return SchemeError.MalformedURI;
        }

        const scheme_str = uri_str[0..expected_scheme.len];
        if (!std.mem.eql(u8, scheme_str, expected_scheme)) {
            return SchemeError.InvalidScheme;
        }

        const rest = uri_str[expected_scheme.len..];

        const slash_idx = std.mem.indexOfScalar(u8, rest, '/') orelse {
            return SchemeError.MissingComponent;
        };

        const cortex_id = try allocator.dupe(u8, rest[0..slash_idx]);
        errdefer allocator.free(cortex_id);

        const neurona_id = try allocator.dupe(u8, rest[slash_idx + 1 ..]);
        errdefer allocator.free(neurona_id);

        if (cortex_id.len == 0 or neurona_id.len == 0) {
            return SchemeError.MissingComponent;
        }

        return URI{
            .scheme = try allocator.dupe(u8, expected_scheme),
            .cortex_id = cortex_id,
            .neurona_id = neurona_id,
        };
    }

    /// Check if string looks like a Neurona URI
    pub fn isURI(s: []const u8) bool {
        return std.mem.startsWith(u8, s, "neurona://");
    }
};

/// Find cortex.json by searching up the directory tree
pub fn findCortexDir(allocator: Allocator) ![]const u8 {
    var current_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_path);

    while (current_path.len > 0) {
        const cortex_path = try std.fs.path.join(allocator, &.{ current_path, "cortex.json" });
        defer allocator.free(cortex_path);

        if (std.fs.cwd().access(cortex_path, .{})) |_| {
            return try allocator.dupe(u8, current_path);
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }

        const parent_path = std.fs.path.dirname(current_path);
        if (parent_path) |p| {
            allocator.free(current_path);
            current_path = try allocator.dupe(u8, p);
        } else {
            break;
        }
    }

    return error.CortexNotFound;
}

/// Resolve URI to Neurona file path
/// Uses cortex.json for directory location and graph.idx for lookup
pub fn resolveURI(allocator: Allocator, uri: *const URI, neuronas_dir: []const u8) ![]const u8 {
    const cortex_dir = try findCortexDir(allocator);
    defer allocator.free(cortex_dir);

    const graph_index_path = try std.fs.path.join(allocator, &.{ cortex_dir, ".activations", "graph.idx" });
    defer allocator.free(graph_index_path);

    const index_module = @import("../storage/index.zig");

    var graph = index_module.Graph.init();
    defer graph.deinit(allocator);

    if (std.fs.cwd().access(graph_index_path, .{})) |_| {
        const data = try std.fs.cwd().readFileAlloc(allocator, graph_index_path, 100 * 1024 * 1024);
        defer allocator.free(data);

        graph = try index_module.Graph.deserialize(data, allocator);
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }

    if (graph.adjacency_list.contains(uri.neurona_id)) {
        const neurona_path = try std.fs.path.join(allocator, &.{ neuronas_dir, uri.neurona_id });
        const neurona_path_md = try std.fmt.allocPrint(allocator, "{s}.md", .{neurona_path});
        allocator.free(neurona_path);

        if (std.fs.cwd().access(neurona_path_md, .{})) |_| {
            return neurona_path_md;
        } else |err| {
            if (err != error.FileNotFound) {
                allocator.free(neurona_path_md);
                return err;
            }
            allocator.free(neurona_path_md);
        }
    }

    return error.NeuronaNotFound;
}

/// Parse and resolve URI to file path in one step
pub fn resolveURIStr(allocator: Allocator, uri_str: []const u8, neuronas_dir: []const u8) ![]const u8 {
    var uri = try URI.parse(allocator, uri_str);
    defer uri.deinit(allocator);

    return resolveURI(allocator, &uri, neuronas_dir);
}

/// Try to resolve URI, return direct ID if not a URI
pub fn resolveOrFallback(allocator: Allocator, input: []const u8, neuronas_dir: []const u8) ![]const u8 {
    if (URI.isURI(input)) {
        return resolveURIStr(allocator, input, neuronas_dir);
    }
    return allocator.dupe(u8, input);
}

// ==================== Tests ====================

test "URI parse valid URI" {
    const allocator = std.testing.allocator;

    const uri_str = "neurona://my_cortex/req.auth.001";
    var uri = try URI.parse(allocator, uri_str);
    defer uri.deinit(allocator);

    try std.testing.expectEqualStrings("neurona://", uri.scheme);
    try std.testing.expectEqualStrings("my_cortex", uri.cortex_id);
    try std.testing.expectEqualStrings("req.auth.001", uri.neurona_id);
}

test "URI parse rejects invalid scheme" {
    const allocator = std.testing.allocator;

    const uri_str = "http://example.com/test";
    const result = URI.parse(allocator, uri_str);
    try std.testing.expectError(SchemeError.InvalidScheme, result);
}

test "URI parse rejects malformed URI" {
    const allocator = std.testing.allocator;

    const uri_str = "neurona:/incomplete";
    const result = URI.parse(allocator, uri_str);
    try std.testing.expectError(SchemeError.InvalidScheme, result);
}

test "URI parse rejects missing neurona ID" {
    const allocator = std.testing.allocator;

    const uri_str = "neurona://my_cortex/";
    const result = URI.parse(allocator, uri_str);
    try std.testing.expectError(SchemeError.MissingComponent, result);
}

test "URI isURI detects URIs" {
    try std.testing.expect(URI.isURI("neurona://ctx1/n1"));
    try std.testing.expect(URI.isURI("neurona://test/req.001"));
    try std.testing.expect(!URI.isURI("req.001"));
    try std.testing.expect(!URI.isURI("http://example.com"));
}

test "resolveOrFallback returns URI path for URI" {
    const allocator = std.testing.allocator;

    const input = "neurona://ctx1/n1";
    const result = resolveOrFallback(allocator, input, "neuronas");

    if (result) |path| {
        defer allocator.free(path);
        try std.testing.expect(path.len > 0);
    } else |_| {}
}

test "resolveOrFallback returns direct ID for non-URI" {
    const allocator = std.testing.allocator;

    const input = "req.001";
    const result = try resolveOrFallback(allocator, input, "neuronas");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("req.001", result);
}
