// Hybrid Search Implementation (Phase 3.1)
// Test file for hybrid search data structures
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HybridQueryConfig = struct {
    text_query: []const u8,
    vector_query: ?[]const f32 = null,

    bm25_limit: usize = 100,
    vector_limit: usize = 100,
    fusion_limit: usize = 50,

    text_fusion_weight: f32 = 0.6,
    vector_fusion_weight: f32 = 0.4,

    use_activation: bool = true,
    activation_depth: usize = 2,
    activation_decay: f32 = 0.7,

    json_output: bool = false,
};

pub const HybridResult = struct {
    neurona_id: []const u8,
    bm25_score: f32,
    vector_score: f32,
    fused_score: f32,
    activation_score: f32,
    final_score: f32,

    pub fn deinit(self: *HybridResult, allocator: Allocator) void {
        allocator.free(self.neurona_id);
    }
};

// End of test file

test "HybridResult deinit" {
    const allocator = std.testing.allocator;
    var result = HybridResult{
        .neurona_id = try allocator.dupe(u8, "test"),
        .bm25_score = 0.5,
        .vector_score = 0.3,
        .fused_score = 0.4,
        .activation_score = 0.1,
        .final_score = 0.5,
    };
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("test", result.neurona_id);
}
