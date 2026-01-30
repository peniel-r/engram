// Token counting helper for LLM optimization
const std = @import("std");
const Allocator = std.mem.Allocator;
const tfidf = @import("../storage/tfidf.zig");

const llm_cache = @import("../storage/llm_cache.zig");

pub fn countTokens(allocator: Allocator, text: []const u8, cache: ?*llm_cache.LLMCache, neurona_id: ?[]const u8) !u32 {
    if (cache) |c| {
        if (neurona_id) |id| {
            // For now, we trust the caller passes text matching the neurona's current content
            // In a better version, we'd pass a content hash here too.
            if (c.getTokenCount(id, "", 0)) |cached| return cached;
        }
    }

    const tokens = try tfidf.tokenize(text, allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    const count = std.math.cast(u32, tokens.len) orelse std.math.maxInt(u32);

    if (cache) |c| {
        if (neurona_id) |id| {
            try c.setTokenCount(id, count);
        }
    }

    return count;
}

test "countTokens basic" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "Hello world!", null, null);
    try std.testing.expectEqual(@as(u32, 2), n);
}

test "countTokens empty" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "", null, null);
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "countTokens multiple" {
    const allocator = std.testing.allocator;
    const n = try countTokens(allocator, "Multiple words here with punctuation.", null, null);
    try std.testing.expectEqual(@as(u32, 5), n);
}
