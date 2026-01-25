// Neural Activation Implementation
// Propagates signals across graph for context-aware ranking
const std = @import("std");
const Allocator = std.mem.Allocator;
const Graph = @import("graph.zig").Graph;
const BM25Index = @import("../root.zig").storage.BM25Index;
const VectorIndex = @import("../root.zig").storage.VectorIndex;
const storage = @import("../root.zig").storage;
const BM25Result = @import("../root.zig").storage.BM25Result;

/// Activation result with metadata
pub const ActivationResult = struct {
    node_id: []const u8,
    stimulus_score: f32,
    activation_score: f32,
    depth: usize,

    pub fn deinit(self: *ActivationResult, allocator: Allocator) void {
        allocator.free(self.node_id);
    }
};

/// Neural activation for context-aware ranking
pub const NeuralActivation = struct {
    graph: *const Graph,
    bm25_index: *const BM25Index,
    vector_index: *const VectorIndex,

    // Activation parameters
    decay_factor: f32,
    text_weight: f32,
    vector_weight: f32,
    propagation_depth: usize,

    /// Initialize neural activation
    pub fn init(graph: *const Graph, bm25: *const BM25Index, vec: *const VectorIndex) NeuralActivation {
        return NeuralActivation{
            .graph = graph,
            .bm25_index = bm25,
            .vector_index = vec,
            .decay_factor = 0.7,
            .text_weight = 0.6,
            .vector_weight = 0.4,
            .propagation_depth = 2,
        };
    }

    /// Set activation parameters
    pub fn setParams(self: *NeuralActivation, decay: f32, text_w: f32, vec_w: f32, depth: usize) void {
        self.decay_factor = decay;
        self.text_weight = text_w;
        self.vector_weight = vec_w;
        self.propagation_depth = depth;
    }

    /// Main activation function
    pub fn activate(self: *const NeuralActivation, allocator: Allocator, query: []const u8, query_vec: ?[]const f32) ![]ActivationResult {
        // Compute initial stimuli for all nodes
        var initial_stimuli = std.StringHashMap(f32).init(allocator);
        defer initial_stimuli.deinit();

        var it = self.graph.adjacency_list.iterator();
        while (it.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const stimulus = self.computeStimulus(node_id, query, query_vec);

            if (stimulus > 0.0) {
                try initial_stimuli.put(node_id, stimulus);
            }
        }

        // Propagate signal across graph
        var activations = try self.propagateSignal(allocator, &initial_stimuli, self.propagation_depth);
        defer {
            var act_it = activations.iterator();
            while (act_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            activations.deinit();
        }

        // Build results
        var results = std.ArrayList(ActivationResult){};
        try results.ensureTotalCapacity(allocator, 50);

        var act_it = activations.iterator();
        while (act_it.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const activation_score = entry.value_ptr.*;

            if (activation_score > 0.0) {
                try results.append(allocator, .{
                    .node_id = try allocator.dupe(u8, node_id),
                    .stimulus_score = initial_stimuli.get(node_id) orelse 0.0,
                    .activation_score = activation_score,
                    .depth = self.propagation_depth,
                });
            }
        }

        // Sort by activation score (descending)
        std.sort.insertion(ActivationResult, results.items, {}, struct {
            fn lessThan(_: void, a: ActivationResult, b: ActivationResult) bool {
                return a.activation_score > b.activation_score;
            }
        }.lessThan);

        return results.toOwnedSlice(allocator);
    }

    /// Compute stimulus for a node
    fn computeStimulus(self: *const NeuralActivation, node_id: []const u8, query: []const u8, query_vec: ?[]const f32) f32 {
        var stimulus: f32 = 0.0;

        // BM25 score
        if (self.text_weight > 0.0) {
            const bm25_results = self.bm25_index.search(std.heap.page_allocator, query, 10) catch &[_]BM25Result{};
            defer std.heap.page_allocator.free(bm25_results);

            for (bm25_results) |r| {
                if (std.mem.eql(u8, r.doc_id, node_id)) {
                    stimulus += self.text_weight * r.score;
                    break;
                }
            }
        }

        // Vector similarity
        if (self.vector_weight > 0.0) {
            if (query_vec) |qv| {
                if (self.vector_index.getVector(node_id)) |node_vec| {
                    const sim = self.vector_index.cosineSimilarity(qv, node_vec);
                    stimulus += self.vector_weight * sim;
                }
            }
        }

        return stimulus;
    }

    /// Propagate signal across graph
    fn propagateSignal(self: *const NeuralActivation, allocator: Allocator, initial_stimuli: *const std.StringHashMap(f32), depth: usize) !std.StringHashMap(f32) {
        var activations = std.StringHashMap(f32).init(allocator);

        // Initialize with stimuli
        var stim_it = initial_stimuli.iterator();
        while (stim_it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            try activations.put(key, entry.value_ptr.*);
        }

        // Propagate across levels
        var current_depth: usize = 0;
        while (current_depth < depth) : (current_depth += 1) {
            var new_activations = std.StringHashMap(f32).init(allocator);

            var act_it = activations.iterator();
            while (act_it.next()) |entry| {
                const node_id = entry.key_ptr.*;
                const activation = entry.value_ptr.*;

                if (activation <= 0.0) continue;

                // Get outgoing edges (what this node activates)
                const outgoing = self.graph.getAdjacent(node_id);
                for (outgoing) |edge| {
                    const target_id = edge.target_id;

                    // Apply decay
                    const edge_weight = @as(f32, @floatFromInt(edge.weight)) / 100.0;
                    const propagated = activation * edge_weight * self.decay_factor;

                    // Add to new activations (accumulate)
                    const existing = new_activations.getPtr(target_id);
                    if (existing) |val| {
                        val.* += propagated;
                    } else {
                        const key = try allocator.dupe(u8, target_id);
                        try new_activations.put(key, propagated);
                    }
                }
            }

            // Update activations
            var cleanup_it = activations.iterator();
            while (cleanup_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            activations.deinit();

            activations = new_activations;
        }

        return activations;
    }
};

// =============== Tests ===============

test "NeuralActivation init creates with defaults" {
    const allocator = std.testing.allocator;

    // Create mock objects (minimal setup for structure test)
    const graph = Graph.init();
    defer graph.deinit(allocator);

    var bm25_index = BM25Index.init();
    defer bm25_index.deinit(allocator);

    var vector_index = VectorIndex.init(allocator, 128);
    defer vector_index.deinit(allocator);

    const activation = NeuralActivation.init(&graph, &bm25_index, &vector_index);

    try std.testing.expectEqual(@as(f32, 0.7), activation.decay_factor);
    try std.testing.expectEqual(@as(f32, 0.6), activation.text_weight);
    try std.testing.expectEqual(@as(f32, 0.4), activation.vector_weight);
    try std.testing.expectEqual(@as(usize, 2), activation.propagation_depth);
}

test "NeuralActivation setParams updates parameters" {
    const allocator = std.testing.allocator;

    const graph = Graph.init();
    defer graph.deinit(allocator);

    var bm25_index = BM25Index.init();
    defer bm25_index.deinit(allocator);

    var vector_index = VectorIndex.init(allocator, 128);
    defer vector_index.deinit(allocator);

    var activation = NeuralActivation.init(&graph, &bm25_index, &vector_index);

    activation.setParams(0.5, 0.8, 0.2, 3);

    try std.testing.expectEqual(@as(f32, 0.5), activation.decay_factor);
    try std.testing.expectEqual(@as(f32, 0.8), activation.text_weight);
    try std.testing.expectEqual(@as(f32, 0.2), activation.vector_weight);
    try std.testing.expectEqual(@as(usize, 3), activation.propagation_depth);
}

test "ActivationResult deinit cleans up" {
    const allocator = std.testing.allocator;

    var result = ActivationResult{
        .node_id = try allocator.dupe(u8, "test_node"),
        .stimulus_score = 0.5,
        .activation_score = 0.6,
        .depth = 2,
    };
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("test_node", result.node_id);
    try std.testing.expectEqual(@as(f32, 0.5), result.stimulus_score);
    try std.testing.expectEqual(@as(f32, 0.6), result.activation_score);
    try std.testing.expectEqual(@as(usize, 2), result.depth);
}

test "NeuralActivation activate returns empty with no matches" {
    const allocator = std.testing.allocator;

    const graph = Graph.init();
    defer graph.deinit(allocator);

    var bm25_index = BM25Index.init();
    try bm25_index.addDocument(allocator, "doc1", "apple");
    bm25_index.build();
    defer bm25_index.deinit(allocator);

    var vector_index = VectorIndex.init(allocator, 2);
    try vector_index.addVector(allocator, "doc1", &[_]f32{ 1.0, 0.0 });
    defer vector_index.deinit(allocator);

    const activation = NeuralActivation.init(&graph, &bm25_index, &vector_index);

    const results = try activation.activate(allocator, "nonexistent", null);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
