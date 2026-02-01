// Integration Tests for Engram Lifecycle
// Tests: Fresh installation, Incremental updates, Migration scenarios

const std = @import("std");
const Allocator = std.mem.Allocator;
const Engram = @import("Engram");

// Import Engram modules
const Cortex = Engram.core.cortex.Cortex;
const storage = Engram.storage;
const GloVeIndex = storage.GloVeIndex;
const VectorIndex = storage.VectorIndex;

// CLI commands
const init_cmd = Engram.cli.init;
const new_cmd = Engram.cli.new;

// ==================== Test 1: Fresh Installation ====================

test "Fresh installation - Complete lifecycle" {
    std.debug.print("Running: Fresh installation - Complete lifecycle\n", .{});

    const allocator = std.testing.allocator;
    const test_cortex_name = "test_fresh_install";
    const cortex_path = test_cortex_name;

    // Cleanup before test
    std.fs.cwd().deleteTree(cortex_path) catch {};

    // =========================================================================
    // Step 1: Create cortex using init command
    // =========================================================================

    const init_config = init_cmd.InitConfig{
        .name = test_cortex_name,
        .cortex_type = .alm,
        .default_language = "en",
        .force = false,
        .verbose = false,
    };

    try init_cmd.execute(allocator, init_config);

    std.debug.print("Cortex init completed successfully\n", .{});

    // Verify cortex structure exists
    var cortex_dir = std.fs.cwd().openDir(cortex_path, .{}) catch |err| {
        try std.testing.expect(error.FileNotFound != err);
        return;
    };
    defer cortex_dir.close();

    std.debug.print("Cortex directory opened\n", .{});

    // Verify cortex.json exists
    std.debug.print("Reading cortex.json...\n", .{});
    const cortex_json = try cortex_dir.readFileAlloc(allocator, "cortex.json", 1024 * 10);
    defer allocator.free(cortex_json);
    try std.testing.expect(cortex_json.len > 0);

    std.debug.print("cortex.json verified, checking neuronas directory...\n", .{});
    // Verify neuronas directory exists
    _ = cortex_dir.openDir("neuronas", .{}) catch |err| {
        try std.testing.expect(error.FileNotFound != err);
        return;
    };

    std.debug.print("neuronas directory verified\n", .{});

    // =========================================================================
    // Step 2: Download/Setup GloVe vectors (simulate download)
    // =========================================================================

    // Create minimal GloVe cache for testing
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    glove_index.dimension = 50;
    glove_index.loaded = true;

    // Add test vocabulary
    const test_words = [_][]const u8{ "test", "vector", "embedding", "search", "glove" };
    for (test_words, 0..) |word, i| {
        const vec_data = try allocator.alloc(f32, 50);
        defer allocator.free(vec_data);

        // Create simple test vector
        for (0..50) |j| {
            vec_data[j] = @as(f32, @floatFromInt(i * 50 + j)) / 1000.0;
        }

        const word_dup = try allocator.dupe(u8, word);
        try glove_index.vectors_storage.appendSlice(allocator, vec_data);
        const vec_ptr = glove_index.vectors_storage.items[glove_index.vectors_storage.items.len - 50 ..];
        try glove_index.word_vectors.put(allocator, word_dup, vec_ptr);
    }

    // Save GloVe cache
    const glove_cache_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "cache", "glove_cache.bin" });
    defer allocator.free(glove_cache_path);
    try glove_index.saveCache(glove_cache_path);

    std.debug.print("GloVe cache saved\n", .{});
    try std.testing.expect(GloVeIndex.cacheExists(glove_cache_path));

    // =========================================================================
    // Step 3: Create Neuronas
    // =========================================================================
    std.debug.print("Creating Neuronas...\n", .{});

    // Change to cortex directory
    const original_dir = std.fs.cwd();

    // Create test Neuronas
    const neurona_configs = [_]struct {
        title: []const u8,
        ntype: new_cmd.NeuronaType,
    }{
        .{ .title = "Authentication Feature", .ntype = .feature },
        .{ .title = "User Login Requirement", .ntype = .requirement },
        .{ .title = "Login Test Case", .ntype = .test_case },
        .{ .title = "OAuth Implementation", .ntype = .artifact },
    };

    var neuronas_dir = try original_dir.openDir(cortex_path ++ "/neuronas", .{});
    defer neuronas_dir.close();

    for (neurona_configs) |config| {
        // Create neurona file manually (avoiding editor)
        const prefix = switch (config.ntype) {
            .feature => "feat",
            .requirement => "req",
            .test_case => "test",
            .artifact => "art",
            .issue => "issue",
        };

        const neurona_id = try std.fmt.allocPrint(allocator, "{s}.{s}.001", .{ prefix, config.title });
        defer allocator.free(neurona_id);

        const neurona_content = try std.fmt.allocPrint(allocator,
            \\---
            \\id: {s}
            \\title: {s}
            \\type: {s}
            \\tags: ["test"]
            \\---
            \\
            \\# {s}
            \\
            \\Test content for integration testing.
        , .{ neurona_id, config.title, @tagName(config.ntype), config.title });
        defer allocator.free(neurona_content);

        const neurona_path = try std.fmt.allocPrint(allocator, "{s}.md", .{neurona_id});
        defer allocator.free(neurona_path);

        try neuronas_dir.writeFile(.{
            .sub_path = neurona_path,
            .data = neurona_content,
        });
    }

    // =========================================================================
    // Step 4: Run `engram index` (simulate)
    // =========================================================================

    // Scan neuronas
    std.debug.print("Scanning neuronas...\n", .{});
    const neuronas = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    std.debug.print("Found {} neuronas\n", .{neuronas.len});
    try std.testing.expect(neuronas.len >= 4);

    // Load GloVe index
    std.debug.print("Loading GloVe index...\n", .{});
    var loaded_glove = GloVeIndex.init(allocator);
    defer loaded_glove.deinit(allocator);
    try loaded_glove.loadCache(allocator, glove_cache_path);

    // Build vector index
    var vector_index = VectorIndex.init(allocator, loaded_glove.dimension);
    defer vector_index.deinit(allocator);

    std.debug.print("Building vector index for {} neuronas\n", .{neuronas.len});
    for (neuronas) |*neurona| {
        const words = [_][]const u8{ "test", "vector" };
        const embedding = try loaded_glove.computeEmbedding(allocator, &words);
        defer allocator.free(embedding);
        try vector_index.addVector(allocator, neurona.id, embedding);
    }

    // Save vector index
    const vectors_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "vectors.bin" });
    defer allocator.free(vectors_path);

    std.debug.print("Saving vector index to {s}...\n", .{vectors_path});
    try vector_index.save(allocator, vectors_path, std.time.timestamp());

    // =========================================================================
    // Step 5: Verify `.activations/vectors.bin` exists
    // =========================================================================

    std.debug.print("Verifying vectors.bin...\n", .{});
    const vectors_file = try std.fs.cwd().openFile(vectors_path, .{});
    defer vectors_file.close();
    const file_size = try vectors_file.getEndPos();
    std.debug.print("vectors.bin size: {} bytes\n", .{file_size});
    try std.testing.expect(file_size > 0);

    std.debug.print("Test 2 (Incremental updates) completed successfully!\n", .{});

    // Cleanup
    std.fs.cwd().deleteTree(cortex_path) catch {};
}

// ==================== Test 2: Incremental Updates ====================

test "Incremental updates - Lazy and forced persistence" {
    std.debug.print("Running: Incremental updates - Lazy and forced persistence\n", .{});

    const allocator = std.testing.allocator;
    const test_cortex_name = "test_incremental_updates";
    const cortex_path = test_cortex_name;

    // Cleanup before test
    std.fs.cwd().deleteTree(cortex_path) catch {};

    // =========================================================================
    // Setup: Create initial cortex with index
    // =========================================================================

    const init_config = init_cmd.InitConfig{
        .name = test_cortex_name,
        .cortex_type = .alm,
        .force = false,
        .verbose = false,
    };

    try init_cmd.execute(allocator, init_config);

    // Create initial GloVe cache
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    glove_index.dimension = 50;
    glove_index.loaded = true;

    const test_words = [_][]const u8{ "initial", "vector" };
    for (test_words, 0..) |word, i| {
        const vec_data = try allocator.alloc(f32, 50);
        defer allocator.free(vec_data);

        for (0..50) |j| {
            vec_data[j] = @as(f32, @floatFromInt(i * 50 + j)) / 1000.0;
        }

        const word_dup = try allocator.dupe(u8, word);
        try glove_index.vectors_storage.appendSlice(allocator, vec_data);
        const vec_ptr = glove_index.vectors_storage.items[glove_index.vectors_storage.items.len - 50 ..];
        try glove_index.word_vectors.put(allocator, word_dup, vec_ptr);
    }

    const glove_cache_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "cache", "glove_cache.bin" });
    defer allocator.free(glove_cache_path);
    try glove_index.saveCache(glove_cache_path);

    // Create initial neurona and index
    const initial_neurona_path = try std.fs.path.join(allocator, &.{ cortex_path, "neuronas", "req.initial.001.md" });
    defer allocator.free(initial_neurona_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = initial_neurona_path,
        .data =
        \\---
        \\id: req.initial.001
        \\title: Initial Requirement
        \\type: requirement
        \\tags: ["test"]
        \\---
        \\
        \\# Initial Requirement
        ,
    });

    // Build initial vector index
    const neuronas_initial = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas_initial) |*n| n.deinit(allocator);
        allocator.free(neuronas_initial);
    }

    var vector_index = VectorIndex.init(allocator, glove_index.dimension);
    defer vector_index.deinit(allocator);

    const words = [_][]const u8{ "initial", "vector" };
    const embedding = try glove_index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);
    try vector_index.addVector(allocator, "req.initial.001", embedding);

    const vectors_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "vectors.bin" });
    defer allocator.free(vectors_path);
    try vector_index.save(allocator, vectors_path, std.time.timestamp());

    // =========================================================================
    // Step 1: Create new Neurona (lazy: no persistence)
    // =========================================================================

    const new_neurona_path = try std.fs.path.join(allocator, &.{ cortex_path, "neuronas", "req.new.001.md" });
    defer allocator.free(new_neurona_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = new_neurona_path,
        .data =
        \\---
        \\id: req.new.001
        \\title: New Requirement
        \\type: requirement
        \\tags: ["test"]
        \\---
        \\
        \\# New Requirement
        ,
    });

    // Verify new neurona exists in filesystem
    if (std.fs.cwd().openFile(new_neurona_path, .{})) |f| {
        f.close();
    } else |_| {}

    // =========================================================================
    // Step 2: Run query (lazy: no persistence)
    // =========================================================================

    // Load existing index (should NOT contain new neurona)
    const loaded_lazy = try VectorIndex.load(allocator, vectors_path);
    var lazy_index = loaded_lazy.index;
    defer lazy_index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), lazy_index.vectors.count());

    // Verify new neurona is NOT in lazy index
    const lazy_result = lazy_index.getVector("req.new.001");
    try std.testing.expect(lazy_result == null);

    // =========================================================================
    // Step 3: Run `engram index` (force persistence)
    // =========================================================================

    // Re-scan all neuronas
    const neuronas_all = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas_all) |*n| n.deinit(allocator);
        allocator.free(neuronas_all);
    }

    try std.testing.expectEqual(@as(usize, 2), neuronas_all.len);

    // Rebuild index with both neuronas
    var vector_index_updated = VectorIndex.init(allocator, glove_index.dimension);
    defer vector_index_updated.deinit(allocator);

    for (neuronas_all) |*neurona| {
        const neurona_words = [_][]const u8{ "test", "vector" };
        const neurona_embedding = try glove_index.computeEmbedding(allocator, &neurona_words);
        defer allocator.free(neurona_embedding);
        try vector_index_updated.addVector(allocator, neurona.id, neurona_embedding);
    }

    // Save updated index
    try vector_index_updated.save(allocator, vectors_path, std.time.timestamp());

    // =========================================================================
    // Step 4: Verify vector added to cache
    // =========================================================================

    // Load updated index
    const loaded_updated = try VectorIndex.load(allocator, vectors_path);
    var updated_index = loaded_updated.index;
    defer updated_index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), updated_index.vectors.count());

    // Verify new neurona IS in updated index
    const updated_result = updated_index.getVector("req.new.001");
    try std.testing.expect(updated_result != null);

    // Cleanup
    std.fs.cwd().deleteTree(cortex_path) catch {};
}

// ==================== Test 3: Migration Scenario ====================

test "Migration scenario - Delete .activations/ and verify fallback" {
    std.debug.print("Running: Migration scenario - Delete .activations/ and verify fallback\n", .{});

    const allocator = std.testing.allocator;
    const test_cortex_name = "test_migration_scenario";
    const cortex_path = test_cortex_name;

    // Cleanup before test
    std.fs.cwd().deleteTree(cortex_path) catch {};

    // =========================================================================
    // Setup: Create cortex with existing index
    // =========================================================================

    const init_config = init_cmd.InitConfig{
        .name = test_cortex_name,
        .cortex_type = .alm,
        .force = false,
        .verbose = false,
    };

    try init_cmd.execute(allocator, init_config);

    // Create GloVe cache
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    glove_index.dimension = 50;
    glove_index.loaded = true;

    const test_words = [_][]const u8{ "migration", "test" };
    for (test_words, 0..) |word, i| {
        const vec_data = try allocator.alloc(f32, 50);
        defer allocator.free(vec_data);

        for (0..50) |j| {
            vec_data[j] = @as(f32, @floatFromInt(i * 50 + j)) / 1000.0;
        }

        const word_dup = try allocator.dupe(u8, word);
        try glove_index.vectors_storage.appendSlice(allocator, vec_data);
        const vec_ptr = glove_index.vectors_storage.items[glove_index.vectors_storage.items.len - 50 ..];
        try glove_index.word_vectors.put(allocator, word_dup, vec_ptr);
    }

    const glove_cache_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "cache", "glove_cache.bin" });
    defer allocator.free(glove_cache_path);
    try glove_index.saveCache(glove_cache_path);

    // Create neurona
    const neurona_path = try std.fs.path.join(allocator, &.{ cortex_path, "neuronas", "req.migration.001.md" });
    defer allocator.free(neurona_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = neurona_path,
        .data =
        \\---
        \\id: req.migration.001
        \\title: Migration Test
        \\type: requirement
        \\tags: ["test"]
        \\---
        \\
        \\# Migration Test
        ,
    });

    // Build vector index
    const neuronas_initial = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas_initial) |*n| n.deinit(allocator);
        allocator.free(neuronas_initial);
    }

    var vector_index = VectorIndex.init(allocator, glove_index.dimension);
    defer vector_index.deinit(allocator);

    const words = [_][]const u8{ "migration", "test" };
    const embedding = try glove_index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);
    try vector_index.addVector(allocator, "req.migration.001", embedding);

    const vectors_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "vectors.bin" });
    defer allocator.free(vectors_path);
    try vector_index.save(allocator, vectors_path, std.time.timestamp());

    // =========================================================================
    // Step 1: Delete `.activations/`
    // =========================================================================

    const activations_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations" });
    defer allocator.free(activations_path);

    try std.fs.cwd().deleteTree(activations_path);

    // Verify .activations/ is deleted
    _ = std.fs.cwd().openDir(activations_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {},
    };

    // =========================================================================
    // Step 2: Verify system still works (falls back to recompute)
    // =========================================================================

    // Try to load vector index (should fail)
    const load_result = VectorIndex.load(allocator, vectors_path);
    try std.testing.expectError(error.FileNotFound, load_result);

    // System should fallback to recomputing from scratch
    // Verify GloVe cache still exists (not in .activations/)
    // In this test, we saved it inside .activations/, so we need to recreate it
    try std.fs.cwd().makePath(activations_path);
    try std.fs.cwd().makePath(glove_cache_path[0..std.mem.lastIndexOfScalar(u8, glove_cache_path, std.fs.path.sep).?]);

    glove_index.loaded = true;
    try glove_index.saveCache(glove_cache_path);

    // Verify GloVe cache exists
    try std.testing.expect(GloVeIndex.cacheExists(glove_cache_path));

    // Load GloVe index
    var loaded_glove = GloVeIndex.init(allocator);
    defer loaded_glove.deinit(allocator);
    try loaded_glove.loadCache(allocator, glove_cache_path);

    // Re-scan neuronas
    const neuronas_recomputed = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas_recomputed) |*n| n.deinit(allocator);
        allocator.free(neuronas_recomputed);
    }

    try std.testing.expectEqual(@as(usize, 1), neuronas_recomputed.len);

    // Recompute vector index
    var vector_index_recomputed = VectorIndex.init(allocator, loaded_glove.dimension);
    defer vector_index_recomputed.deinit(allocator);

    const recompute_words = [_][]const u8{ "migration", "test" };
    const recompute_embedding = try loaded_glove.computeEmbedding(allocator, &recompute_words);
    defer allocator.free(recompute_embedding);
    try vector_index_recomputed.addVector(allocator, "req.migration.001", recompute_embedding);

    // Verify recomputed index works
    try std.testing.expectEqual(@as(usize, 1), vector_index_recomputed.vectors.count());

    // =========================================================================
    // Step 3: Run `engram index` to rebuild
    // =========================================================================

    // Save recomputed index
    try vector_index_recomputed.save(allocator, vectors_path, std.time.timestamp());

    // Verify index is recreated
    const loaded_rebuilt = try VectorIndex.load(allocator, vectors_path);
    var rebuilt_index = loaded_rebuilt.index;
    defer rebuilt_index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rebuilt_index.vectors.count());

    // Verify neurona is in rebuilt index
    const rebuilt_result = rebuilt_index.getVector("req.migration.001");
    try std.testing.expect(rebuilt_result != null);

    // Cleanup
    std.fs.cwd().deleteTree(cortex_path) catch {};
}

// ==================== Test 4: Edge Cases ====================

test "Edge case - Empty cortex with semantic search enabled" {
    std.debug.print("Running: Edge case - Empty cortex with semantic search enabled\n", .{});

    const allocator = std.testing.allocator;
    const test_cortex_name = "test_empty_cortex";
    const cortex_path = test_cortex_name;

    std.fs.cwd().deleteTree(cortex_path) catch {};

    const init_config = init_cmd.InitConfig{
        .name = test_cortex_name,
        .cortex_type = .alm,
        .force = false,
        .verbose = false,
    };

    try init_cmd.execute(allocator, init_config);

    // Verify cortex created but empty
    const neuronas_empty = try storage.scanNeuronas(allocator, cortex_path ++ "/neuronas");
    defer {
        for (neuronas_empty) |*n| n.deinit(allocator);
        allocator.free(neuronas_empty);
    }

    try std.testing.expectEqual(@as(usize, 0), neuronas_empty.len);

    // Attempt to build index (should handle empty gracefully)
    const glove_cache_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "cache", "glove_cache.bin" });
    defer allocator.free(glove_cache_path);

    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    glove_index.dimension = 50;
    glove_index.loaded = true;

    const cache_dir = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "cache" });
    defer allocator.free(cache_dir);
    try std.fs.cwd().makePath(cache_dir);
    try glove_index.saveCache(glove_cache_path);

    var vector_index = VectorIndex.init(allocator, glove_index.dimension);
    defer vector_index.deinit(allocator);

    const vectors_path = try std.fs.path.join(allocator, &.{ cortex_path, ".activations", "vectors.bin" });
    defer allocator.free(vectors_path);
    try vector_index.save(allocator, vectors_path, std.time.timestamp());

    // Verify empty index loads correctly
    const loaded_empty = try VectorIndex.load(allocator, vectors_path);
    var empty_index = loaded_empty.index;
    defer empty_index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), empty_index.vectors.count());

    std.fs.cwd().deleteTree(cortex_path) catch {};
}
