// ID generation utilities for Neurona
// Creates slugs from titles with prefix support
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generate slug from title (kebab-case, lowercase)
/// "OAuth 2.0" -> "oauth-2.0"
pub fn fromTitle(allocator: Allocator, title: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(allocator);

    const title_lower = try allocator.dupe(u8, title);
    defer allocator.free(title_lower);

    // Convert to lowercase
    for (title_lower, 0..) |c, i| {
        title_lower[i] = std.ascii.toLower(c);
    }

    // Build slug: alphanumeric and hyphens only
    var prev_was_space = false;
    for (title_lower) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (prev_was_space) {
                try result.append(allocator, '-');
            }
            try result.append(allocator, c);
            prev_was_space = false;
        } else if (std.ascii.isWhitespace(c) or c == '_' or c == '.') {
            prev_was_space = true;
        }
        // Skip other characters (punctuation, etc.)
    }

    return result.toOwnedSlice(allocator);
}

/// Generate slug with prefix
/// "req" + "OAuth 2.0" -> "req.oauth-2.0"
pub fn fromTitleWithPrefix(allocator: Allocator, prefix: []const u8, title: []const u8) ![]const u8 {
    const slug = try fromTitle(allocator, title);
    defer allocator.free(slug);

    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, slug });
}

/// Generate unique ID (UUID-like format)
/// Returns 16-character hex string
pub fn generateUID(allocator: Allocator) ![]const u8 {
    const random = std.crypto.random;
    var bytes: [8]u8 = undefined;
    random.bytes(&bytes);

    return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
    });
}

/// Generate unique ID with prefix
/// "req" + UID -> "req.1a2b3c4d..."
pub fn generateUIDWithPrefix(allocator: Allocator, prefix: []const u8) ![]const u8 {
    const uid = try generateUID(allocator);
    defer allocator.free(uid);

    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, uid });
}

/// Validate ID format (basic check)
/// Returns true if ID looks valid (alphanumeric, dots, hyphens)
pub fn isValidId(id: []const u8) bool {
    if (id.len == 0) return false;

    for (id) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_') {
            return false;
        }
    }

    return true;
}

/// Extract prefix from ID (everything before first dot)
/// "req.auth.oauth" -> "req"
pub fn extractPrefix(id: []const u8) ?[]const u8 {
    const dot_idx = std.mem.indexOfScalar(u8, id, '.') orelse return null;
    if (dot_idx == 0) return null;
    return id[0..dot_idx];
}

test "fromTitle generates valid slugs" {
    const allocator = std.testing.allocator;

    // Simple title
    const slug1 = try fromTitle(allocator, "OAuth 2.0");
    defer allocator.free(slug1);
    try std.testing.expectEqualStrings("oauth-2-0", slug1);

    // Title with underscores
    const slug2 = try fromTitle(allocator, "test_case_name");
    defer allocator.free(slug2);
    try std.testing.expectEqualStrings("test-case-name", slug2);

    // Title with mixed case
    const slug3 = try fromTitle(allocator, "Support OAuth 2.0 Authentication");
    defer allocator.free(slug3);
    try std.testing.expectEqualStrings("support-oauth-2-0-authentication", slug3);
}

test "fromTitle handles punctuation" {
    const allocator = std.testing.allocator;

    // Title with special chars
    const slug1 = try fromTitle(allocator, "Hello, World!");
    defer allocator.free(slug1);
    try std.testing.expectEqualStrings("hello-world", slug1);

    // Title with multiple spaces
    const slug2 = try fromTitle(allocator, "Multiple   Spaces");
    defer allocator.free(slug2);
    try std.testing.expectEqualStrings("multiple-spaces", slug2);
}

test "fromTitleWithPrefix adds prefix correctly" {
    const allocator = std.testing.allocator;

    const slug1 = try fromTitleWithPrefix(allocator, "req", "OAuth 2.0");
    defer allocator.free(slug1);
    try std.testing.expectEqualStrings("req.oauth-2-0", slug1);

    const slug2 = try fromTitleWithPrefix(allocator, "test", "Case Name");
    defer allocator.free(slug2);
    try std.testing.expectEqualStrings("test.case-name", slug2);
}

test "generateUID produces valid format" {
    const allocator = std.testing.allocator;

    const uid = try generateUID(allocator);
    defer allocator.free(uid);

    // Should be 16 hex characters
    try std.testing.expectEqual(@as(usize, 16), uid.len);

    // All characters should be hex
    for (uid) |c| {
        try std.testing.expect(std.ascii.isHex(c));
    }
}

test "generateUID produces different values" {
    const allocator = std.testing.allocator;

    const uid1 = try generateUID(allocator);
    defer allocator.free(uid1);

    const uid2 = try generateUID(allocator);
    defer allocator.free(uid2);

    // UIDs should be different (extremely unlikely to be same)
    try std.testing.expect(!std.mem.eql(u8, uid1, uid2));
}

test "generateUIDWithPrefix adds prefix" {
    const allocator = std.testing.allocator;

    const uid = try generateUIDWithPrefix(allocator, "temp");
    defer allocator.free(uid);

    // Should have prefix
    try std.testing.expect(std.mem.startsWith(u8, uid, "temp."));

    // Should be prefix + 16 hex chars
    try std.testing.expectEqual(@as(usize, 21), uid.len);
}

test "isValidId validates correctly" {
    // Valid IDs
    try std.testing.expect(isValidId("oauth-2.0"));
    try std.testing.expect(isValidId("req.auth.oauth"));
    try std.testing.expect(isValidId("test_case"));
    try std.testing.expect(isValidId("simple"));

    // Invalid IDs
    try std.testing.expect(!isValidId(""));
    try std.testing.expect(!isValidId("test@id"));
    try std.testing.expect(!isValidId("test#id"));
    try std.testing.expect(!isValidId("test id"));
}

test "extractPrefix extracts prefix correctly" {
    const id1 = "req.auth.oauth";
    try std.testing.expectEqualStrings("req", extractPrefix(id1).?);

    const id2 = "test.case.name";
    try std.testing.expectEqualStrings("test", extractPrefix(id2).?);

    const id3 = "simple";
    try std.testing.expect(extractPrefix(id3) == null);

    const id4 = ".leading.dot";
    try std.testing.expect(extractPrefix(id4) == null);
}
