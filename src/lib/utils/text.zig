//! Text processing utilities for tokenization and text manipulation
//! Used for embedding creation and search indexing

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Text processor utilities
pub const TextProcessor = struct {
    /// Tokenize text into words (alphanumeric sequences)
    /// Converts to lowercase, filters words >= 2 characters
    /// Caller must free returned array with allocator.free()
    pub fn tokenizeToWords(allocator: Allocator, text: []const u8) ![][]const u8 {
        // Convert to lowercase
        const lower = try allocator.alloc(u8, text.len);
        defer allocator.free(lower);
        for (text, 0..) |c, i| {
            lower[i] = std.ascii.toLower(c);
        }

        // Extract words
        var words = std.ArrayListUnmanaged([]const u8){};
        defer {
            if (words.items.len == 0) {
                words.deinit(allocator);
            }
        }

        var start: usize = 0;
        var in_word = false;

        for (lower, 0..) |c, i| {
            const is_alpha = std.ascii.isAlphanumeric(c);

            if (is_alpha and !in_word) {
                start = i;
                in_word = true;
            } else if (!is_alpha and in_word) {
                const word = lower[start..i];
                if (word.len >= 2) {
                    const duped = try allocator.dupe(u8, word);
                    try words.append(allocator, duped);
                }
                in_word = false;
            }
        }

        // Handle last word
        if (in_word) {
            const word = lower[start..];
            if (word.len >= 2) {
                const duped = try allocator.dupe(u8, word);
                try words.append(allocator, duped);
            }
        }

        return words.toOwnedSlice(allocator);
    }

    /// Combine title and tags into single text for embeddings
    /// Caller must free returned string with allocator.free()
    pub fn combineTitleAndTags(allocator: Allocator, title: []const u8, tags: []const []const u8) ![]const u8 {
        // Calculate required capacity
        var capacity: usize = title.len;
        for (tags) |tag| {
            capacity += 1 + tag.len; // space + tag
        }

        var result = try std.ArrayListUnmanaged(u8).initCapacity(allocator, capacity);
        defer result.deinit(allocator);

        try result.appendSlice(allocator, title);
        for (tags) |tag| {
            try result.append(allocator, ' ');
            try result.appendSlice(allocator, tag);
        }

        return result.toOwnedSlice(allocator);
    }

    /// Convert string to lowercase
    /// Caller must free returned string with allocator.free()
    pub fn toLower(allocator: Allocator, text: []const u8) ![]const u8 {
        const result = try allocator.alloc(u8, text.len);
        for (text, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return result;
    }

    /// Check if string is alphanumeric
    pub fn isAlphaNum(text: []const u8) bool {
        for (text) |c| {
            if (!std.ascii.isAlphanumeric(c)) return false;
        }
        return true;
    }
};

test "TextProcessor.tokenizeToWords extracts words" {
    const allocator = std.testing.allocator;

    const text = "Hello World Test123";
    const words = try TextProcessor.tokenizeToWords(allocator, text);
    defer {
        for (words) |w| allocator.free(w);
        allocator.free(words);
    }

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expect(std.mem.indexOf(u8, words[0], "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, words[1], "world") != null);
    try std.testing.expect(std.mem.indexOf(u8, words[2], "test123") != null);
}

test "TextProcessor.tokenizeToWords filters short words" {
    const allocator = std.testing.allocator;

    const text = "a bc def ghij";
    const words = try TextProcessor.tokenizeToWords(allocator, text);
    defer {
        for (words) |w| allocator.free(w);
        allocator.free(words);
    }

    try std.testing.expectEqual(@as(usize, 3), words.len); // "bc", "def", "ghij"
}

test "TextProcessor.combineTitleAndTags combines correctly" {
    const allocator = std.testing.allocator;

    const title = "My Title";
    const tags = [_][]const u8{ "tag1", "tag2", "tag3" };

    const result = try TextProcessor.combineTitleAndTags(allocator, title, &tags);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("My Title tag1 tag2 tag3", result);
}

test "TextProcessor.toLower converts to lowercase" {
    const allocator = std.testing.allocator;

    const text = "Hello WORLD";
    const result = try TextProcessor.toLower(allocator, text);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "TextProcessor.isAlphaNum checks alphanumeric" {
    try std.testing.expect(TextProcessor.isAlphaNum("test123"));
    try std.testing.expect(!TextProcessor.isAlphaNum("test 123"));
    try std.testing.expect(!TextProcessor.isAlphaNum("test!"));
}
