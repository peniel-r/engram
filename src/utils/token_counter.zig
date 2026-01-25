// Token counting helper for LLM optimization
const std = @import("std");
const Allocator = std.mem.Allocator;
const tfidf = @import("../storage/tfidf.zig");

pub fn countTokens(allocator: Allocator, text: []const u8) !u32 {
    const tokens = try tfidf.tokenize(text, allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    return @as(u32, tokens.len);
}

test "countTokens basic" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "Hello world!");
    try std.testing.expectEqual(@as(u32, 2), n);
}

test "countTokens empty" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "");
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "countTokens multiple" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "Multiple words here with punctuation.");
    try std.testing.expectEqual(@as(u32, 6), n);
}