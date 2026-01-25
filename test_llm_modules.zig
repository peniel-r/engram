// Test file to verify LLM modules compile and work
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import from the module (this works when part of the build)
const token_counter = @import("src/utils/token_counter.zig");
const summary = @import("src/utils/summary.zig");
const llm_cache = @import("src/storage/llm_cache.zig");

test "token_counter module works" {
    const allocator = std.testing.allocator;
    const n = try token_counter.countTokens(allocator, "Hello world!");
    try std.testing.expectEqual(@as(u32, 2), n);
}

test "summary module works" {
    const allocator = std.testing.allocator;
    const txt = "This is a test. Second sentence.";
    const out = try summary.generateSummary(allocator, txt, "full", 0);
    defer allocator.free(out);
    try std.testing.expectEqualStrings(txt, out);
}

test "llm_cache module works" {
    const allocator = std.testing.allocator;
    const id = "test_module";
    const hash = "sha:1";
    const summary_text = "Test summary.";
    try llm_cache.saveSummary(allocator, id, hash, summary_text);
    try std.testing.expect(llm_cache.summaryExists(allocator, id));
    try llm_cache.invalidateSummary(allocator, id);
}
