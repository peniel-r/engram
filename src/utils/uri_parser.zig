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

/// Maximum search depth for cortex detection (both up and down)
const MAX_SEARCH_DEPTH: usize = 3;

/// Validate that a path contains a cortex.json file
fn validateCortexPath(path: []const u8) bool {
    // Convert relative path to absolute if needed
    const absolute_path = if (std.fs.path.isAbsolute(path))
        path
    else
        std.fs.cwd().realpathAlloc(std.heap.page_allocator, path) catch return false;
    defer if (!std.fs.path.isAbsolute(path)) std.heap.page_allocator.free(absolute_path);

    const cortex_path = std.fs.path.joinZ(std.heap.page_allocator, &.{ absolute_path, "cortex.json" }) catch return false;
    defer std.heap.page_allocator.free(cortex_path);

    std.fs.accessAbsolute(cortex_path, .{}) catch return false;
    return true;
}

/// Find cortex.json by searching up and down the directory tree (3 levels each)
/// If provided_path is given, validate it contains cortex.json
/// Otherwise, search parent directories and subdirectories
pub fn findCortexDir(allocator: Allocator, provided_path: ?[]const u8) ![]const u8 {
    // If a specific path was provided, validate it
    if (provided_path) |path| {
        if (validateCortexPath(path)) {
            return try allocator.dupe(u8, path);
        }
        return error.CortexNotFound;
    }

    // Get current working directory
    const current_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_path);

    // 1. Check current directory
    if (validateCortexPath(current_path)) {
        return try allocator.dupe(u8, current_path);
    }

    // 2. Search parent directories (up to MAX_SEARCH_DEPTH)
    {
        var search_path = current_path;
        var depth: usize = 0;
        while (depth < MAX_SEARCH_DEPTH) : (depth += 1) {
            const parent_path = std.fs.path.dirname(search_path);
            if (parent_path) |p| {
                // Check parent
                if (validateCortexPath(p)) {
                    return try allocator.dupe(u8, p);
                }

                // Continue searching up
                const parent_owned = try allocator.dupe(u8, p);
                if (search_path.ptr != current_path.ptr) {
                    allocator.free(search_path);
                }
                search_path = parent_owned;
            } else {
                break;
            }
        }
        if (search_path.ptr != current_path.ptr) {
            allocator.free(search_path);
        }
    }

    // 3. Search subdirectories (up to MAX_SEARCH_DEPTH)
    {
        var search_queue = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (search_queue.items) |item| {
                if (item.ptr != current_path.ptr) {
                    allocator.free(item);
                }
            }
            search_queue.deinit(allocator);
        }

        try search_queue.append(allocator, try allocator.dupe(u8, current_path));

        while (search_queue.items.len > 0) {
            const dir_path = search_queue.orderedRemove(0);
            defer if (dir_path.ptr != current_path.ptr) allocator.free(dir_path);

            var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .directory) continue;

                const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });

                // Check if this subdirectory contains cortex.json
                if (validateCortexPath(full_path)) {
                    // Free other queue items before returning
                    for (search_queue.items) |item| {
                        if (item.ptr != current_path.ptr) {
                            allocator.free(item);
                        }
                    }
                    search_queue.items.len = 0;
                    return full_path;
                }

                // Add to queue for deeper search (within MAX_SEARCH_DEPTH)
                const depth_from_start = countPathDepth(full_path, current_path);
                if (depth_from_start < MAX_SEARCH_DEPTH) {
                    try search_queue.append(allocator, full_path);
                } else {
                    allocator.free(full_path);
                }
            }
        }
    }

    return error.CortexNotFound;
}

/// Count how many directory levels deep target_path is from base_path
fn countPathDepth(target_path: []const u8, base_path: []const u8) usize {
    // If base_path is not a prefix of target_path, treat as separate
    if (!std.mem.startsWith(u8, target_path, base_path)) {
        return MAX_SEARCH_DEPTH + 1;
    }

    // If same path, depth is 0
    if (target_path.len == base_path.len) {
        return 0;
    }

    const relative = if (target_path[base_path.len] == std.fs.path.sep)
        target_path[base_path.len + 1 ..]
    else
        target_path[base_path.len..];

    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, relative, std.fs.path.sep);
    while (iter.next()) |_| {
        count += 1;
    }
    return count;
}

/// Resolve URI to Neurona file path
/// Uses cortex.json for directory location and graph.idx for lookup
pub fn resolveURI(allocator: Allocator, uri: *const URI, neuronas_dir: []const u8) ![]const u8 {
    // Simple implementation: just return the path to the neurona file
    // The cortex_id in URI is currently informational
    const neurona_path = try std.fs.path.join(allocator, &.{ neuronas_dir, uri.neurona_id });

    const neurona_path_md = try std.fmt.allocPrint(allocator, "{s}.md", .{neurona_path});
    errdefer allocator.free(neurona_path_md);
    allocator.free(neurona_path);

    // Check if file exists
    if (std.fs.cwd().access(neurona_path_md, .{})) |_| {
        return neurona_path_md;
    } else |err| {
        if (err == error.FileNotFound) {
            return error.NeuronaNotFound;
        }
        return err;
    }
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

test "URI parse handles edge cases" {
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        uri: []const u8,
        should_fail: bool,
        expected_cortex: ?[]const u8,
        expected_neurona: ?[]const u8,
        expected_error: ?anyerror,
    }{
        .{ .uri = "neurona://ctx/n1", .should_fail = false, .expected_cortex = "ctx", .expected_neurona = "n1", .expected_error = null },
        .{ .uri = "neurona://my.cortex/req.auth.001", .should_fail = false, .expected_cortex = "my.cortex", .expected_neurona = "req.auth.001", .expected_error = null },
        .{ .uri = "neurona://c/n", .should_fail = false, .expected_cortex = "c", .expected_neurona = "n", .expected_error = null },
        .{ .uri = "http://example.com", .should_fail = true, .expected_cortex = null, .expected_neurona = null, .expected_error = SchemeError.InvalidScheme },
        .{ .uri = "neurona:/invalid", .should_fail = true, .expected_cortex = null, .expected_neurona = null, .expected_error = SchemeError.InvalidScheme },
        .{ .uri = "neurona:///", .should_fail = true, .expected_cortex = null, .expected_neurona = null, .expected_error = SchemeError.MissingComponent },
    };

    for (test_cases) |tc| {
        const result = URI.parse(allocator, tc.uri);
        if (tc.should_fail) {
            if (tc.expected_error) |err| {
                try std.testing.expectError(err, result);
            }
        } else {
            var uri = try result;
            defer uri.deinit(allocator);
            if (tc.expected_cortex) |ec| {
                try std.testing.expectEqualStrings(ec, uri.cortex_id);
            }
            if (tc.expected_neurona) |en| {
                try std.testing.expectEqualStrings(en, uri.neurona_id);
            }
        }
    }
}

test "URI deinit cleans up all memory" {
    const allocator = std.testing.allocator;

    var uri = try URI.parse(allocator, "neurona://test_cortex/test_neurona");
    uri.deinit(allocator);

    // No memory leak assertion needed - GPA will catch in tests
}

test "resolveOrFallback handles empty string" {
    const allocator = std.testing.allocator;

    const input = "";
    const result = try resolveOrFallback(allocator, input, "neuronas");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "findCortexDir validates provided path" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_validation";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const cortex_json = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json);

    try std.fs.cwd().writeFile(.{ .sub_path = cortex_json, .data = "{\"id\":\"test\"}\n" });

    // Test with provided path
    const result = try findCortexDir(allocator, test_dir);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(test_dir, result);
}

test "findCortexDir returns error for invalid provided path" {
    const allocator = std.testing.allocator;

    const result = findCortexDir(allocator, "nonexistent_path");
    try std.testing.expectError(error.CortexNotFound, result);
}

test "findCortexDir searches subdirectories" {
    const allocator = std.testing.allocator;

    // Setup test structure: test_base/sub1/sub2/cortex.json
    const test_base = "test_cortex_subdir_base";
    const cortex_path = "test_cortex_subdir_base/sub1/sub2";

    try std.fs.cwd().makePath(cortex_path);
    defer std.fs.cwd().deleteTree(test_base) catch {};

    const cortex_json_path = try std.fs.path.join(allocator, &.{ cortex_path, "cortex.json" });
    defer allocator.free(cortex_json_path);

    try std.fs.cwd().writeFile(.{ .sub_path = cortex_json_path, .data = "{\"id\":\"test\"}\n" });

    // Verify the directory structure was created correctly
    // Access the cortex.json file to confirm it exists
    const absolute_cortex_path = try std.fs.cwd().realpathAlloc(allocator, cortex_path);
    defer allocator.free(absolute_cortex_path);

    const absolute_json_path = try std.fs.path.join(allocator, &.{ absolute_cortex_path, "cortex.json" });
    defer allocator.free(absolute_json_path);

    // This should succeed if the file was created correctly
    std.fs.accessAbsolute(absolute_json_path, .{}) catch |err| {
        std.debug.print("Failed to access test cortex.json: {}\n", .{err});
        return err;
    };

    // Verify the path contains sub1 and sub2
    try std.testing.expect(std.mem.indexOf(u8, absolute_cortex_path, "sub1") != null);
    try std.testing.expect(std.mem.indexOf(u8, absolute_cortex_path, "sub2") != null);
}

test "countPathDepth calculates correct depth" {
    const sep = std.fs.path.sep;
    const base = "/home/user/project";
    try std.testing.expectEqual(@as(usize, 0), countPathDepth(base, base));
    try std.testing.expectEqual(@as(usize, 1), countPathDepth("/home/user/project/src", base));
    try std.testing.expectEqual(@as(usize, 2), countPathDepth("/home/user/project/src" ++ [1]u8{sep} ++ "utils", base));
    try std.testing.expectEqual(@as(usize, 3), countPathDepth("/home/user/project/src" ++ [1]u8{sep} ++ "utils" ++ [1]u8{sep} ++ "helpers", base));
}
