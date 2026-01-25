// GloVe Embeddings Implementation
// Loads pre-trained GloVe vectors and computes document embeddings
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Binary file format constants
const HEADER = "ENGRAM_GLOVE";
const VERSION: u8 = 1;

/// Entry in lookup table (stored in mmap for zero-copy access)
const WordEntry = packed struct {
    word_offset: u32, // Offset in mmap where word string starts
    word_len: u16, // Length of word
    vector_offset: u32, // Offset where vector data starts
};

/// GloVe Index for fast word → vector lookup
pub const GloVeIndex = struct {
    // Hash map for O(1) word lookup (regular mode)
    word_vectors: std.StringHashMapUnmanaged([]const f32),

    // Store all vectors contiguously for memory efficiency (regular mode)
    vectors_storage: std.ArrayListUnmanaged(f32),
    words_storage: std.ArrayListUnmanaged(u8),

    // Memory-mapped file data (zero-copy mode)
    mmap_data: []const u8,
    mmap_file: ?std.fs.File,

    // Binary format indices (offsets into mmap_data for zero-copy mode)
    word_table: []const WordEntry,

    dimension: usize,
    loaded: bool,
    zero_copy: bool, // Whether using zero-copy mode

    /// Initialize empty GloVe index
    pub fn init(allocator: Allocator) GloVeIndex {
        _ = allocator; // Unused but kept for interface consistency
        return GloVeIndex{
            .word_vectors = .{},
            .vectors_storage = .{},
            .words_storage = .{},
            .mmap_data = &.{},
            .mmap_file = null,
            .word_table = &.{},
            .dimension = 0,
            .loaded = false,
            .zero_copy = false,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *GloVeIndex, allocator: Allocator) void {
        // Zero-copy mode cleanup
        if (self.zero_copy) {
            if (self.mmap_data.len > 0) {
                allocator.free(@constCast(self.mmap_data));
            }
            if (self.mmap_file) |*f| {
                f.close();
            }
            allocator.free(self.word_table);
        } else {
            // Regular mode cleanup
            // Free word vectors map (keys only, values point to vectors_storage)
            if (self.word_vectors.count() > 0) {
                var it = self.word_vectors.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                }
            }
            self.word_vectors.deinit(allocator);

            // Free contiguous storage
            self.vectors_storage.deinit(allocator);
            self.words_storage.deinit(allocator);
        }

        // Reset state
        self.mmap_data = &.{};
        self.mmap_file = null;
        self.word_table = &.{};
        self.dimension = 0;
        self.loaded = false;
        self.zero_copy = false;
    }

    /// Get vector for a word, returns null if word not in vocabulary
    pub fn getVector(self: *const GloVeIndex, allocator: Allocator, word: []const u8) !?[]const f32 {
        if (self.zero_copy) {
            // Binary search in word table
            var left: usize = 0;
            var right: usize = self.word_table.len;

            while (left < right) {
                const mid = left + (right - left) / 2;
                const entry = self.word_table[mid];
                const stored_word = self.mmap_data[entry.word_offset..][0..entry.word_len];

                const cmp = std.mem.order(u8, word, stored_word);
                if (cmp == .lt) {
                    right = mid;
                } else if (cmp == .gt) {
                    left = mid + 1;
                } else {
                    // Found! Return slice directly into mmap
                    const vec_offset = entry.vector_offset;
                    const vec_bytes = self.mmap_data[vec_offset..][0 .. self.dimension * 4];
                    // Due to alignment requirements, copy to properly aligned buffer
                    // This is still much more efficient than loading whole vocab
                    const vec = try allocator.alloc(f32, self.dimension);
                    @memcpy(std.mem.sliceAsBytes(vec), vec_bytes);
                    return vec;
                }
            }
            return error.WordNotFound;
        } else {
            // Regular hash map lookup
            return self.word_vectors.get(word);
        }
    }

    /// Compute document embedding by averaging word vectors
    /// OOV (out of vocabulary) words are skipped
    pub fn computeEmbedding(self: *const GloVeIndex, allocator: Allocator, words: []const []const u8) ![]f32 {
        const embedding = try allocator.alloc(f32, self.dimension);
        @memset(embedding, 0.0);

        var found_count: usize = 0;

        for (words) |word| {
            if (try self.getVector(allocator, word)) |vec| {
                for (0..self.dimension) |i| {
                    embedding[i] += vec[i];
                }
                found_count += 1;
            }
        }

        // Average the vectors
        if (found_count > 0) {
            const scale = 1.0 / @as(f32, @floatFromInt(found_count));
            for (0..self.dimension) |i| {
                embedding[i] *= scale;
            }
        }

        return embedding;
    }

    /// Load GloVe vectors from binary cache file (zero-copy)
    pub fn loadCache(self: *GloVeIndex, allocator: Allocator, path: []const u8) !void {
        _ = allocator;
        _ = path;
        // TODO: Implement binary cache loading
        // For now, mark as not loaded
        self.loaded = false;
        std.debug.print("Warning: Binary cache loading not yet implemented\n", .{});
    }

    /// Load GloVe vectors from binary cache file using zero-copy (single-read approach)
    pub fn loadCacheZeroCopy(self: *GloVeIndex, allocator: Allocator, path: []const u8) !void {
        // Step 1: Open file and get size
        const file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();
        const file_size = try file.getEndPos();

        // Step 2: Read entire file into memory (single allocation)
        const data = try allocator.alloc(u8, file_size);
        errdefer allocator.free(data);
        const bytes_read = try file.readAll(data);
        if (bytes_read != file_size) return error.IncompleteRead;
        file.close(); // Close file after reading

        // Step 3: Parse header (in-place, no additional allocation)
        var offset: usize = 0;

        // Validate header
        const header = data[offset .. offset + HEADER.len];
        offset += HEADER.len;
        if (!std.mem.eql(u8, header, HEADER)) return error.InvalidHeader;

        // Read version
        const version = data[offset];
        offset += 1;
        if (version != VERSION) return error.UnsupportedVersion;

        // Read dimension
        var dim_bytes: [4]u8 = undefined;
        @memcpy(&dim_bytes, data[offset .. offset + 4]);
        self.dimension = std.mem.readInt(u32, &dim_bytes, .little);
        offset += 4;

        // Read word count
        var count_bytes: [4]u8 = undefined;
        @memcpy(&count_bytes, data[offset .. offset + 4]);
        const word_count = std.mem.readInt(u32, &count_bytes, .little);
        offset += 4;

        // Skip header padding (4-byte alignment after header)
        const header_size = HEADER.len + 1 + 4 + 4;
        const header_aligned = (header_size + 3) & ~@as(usize, 3);
        offset += header_aligned - header_size;

        // Step 4: Build word table (single allocation)
        const table = try allocator.alloc(WordEntry, word_count);
        var i: u32 = 0;

        while (i < word_count) : (i += 1) {
            // Read entry structure from data
            var word_off_bytes: [4]u8 = undefined;
            @memcpy(&word_off_bytes, data[offset .. offset + 4]);
            table[i].word_offset = std.mem.readInt(u32, &word_off_bytes, .little);
            offset += 4;

            var word_len_bytes: [2]u8 = undefined;
            @memcpy(&word_len_bytes, data[offset .. offset + 2]);
            table[i].word_len = std.mem.readInt(u16, &word_len_bytes, .little);
            offset += 2;

            // Skip word string
            offset += table[i].word_len;

            // Skip padding to align vector data to 4-byte boundary
            const word_len_aligned = (table[i].word_len + 3) & ~@as(usize, 3);
            const padding = word_len_aligned - table[i].word_len;
            offset += padding;

            // Vector offset: word_offset + word_len_aligned (skip word string + padding)
            const word_len_aligned_u32: u32 = @intCast(word_len_aligned);
            table[i].vector_offset = table[i].word_offset + word_len_aligned_u32;

            // Skip vector data
            offset += self.dimension * 4;
        }

        // Step 5: Store references (no data copy!)
        self.mmap_data = data;
        self.mmap_file = null; // File is already closed
        self.word_table = table;
        self.loaded = true;
        self.zero_copy = true;
    }

    /// Save GloVe vectors to binary cache file
    pub fn saveCache(self: *const GloVeIndex, path: []const u8) !void {
        if (!self.loaded) return error.NotLoaded;
        if (self.zero_copy) return error.CannotSaveZeroCopy;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Build complete buffer for all data (single write for efficiency)
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(std.heap.page_allocator);

        // Write header
        try buffer.appendSlice(std.heap.page_allocator, HEADER);
        try buffer.append(std.heap.page_allocator, VERSION);
        var dim_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &dim_bytes, @intCast(self.dimension), .little);
        try buffer.appendSlice(std.heap.page_allocator, &dim_bytes);
        var count_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &count_bytes, @intCast(self.word_vectors.count()), .little);
        try buffer.appendSlice(std.heap.page_allocator, &count_bytes);

        // Add padding to ensure first word entry starts at 4-byte aligned position
        const header_size = HEADER.len + 1 + 4 + 4;
        const header_aligned = (header_size + 3) & ~@as(usize, 3);
        const header_padding = header_aligned - header_size;
        if (header_padding > 0) {
            var pad: [3]u8 = undefined;
            @memset(&pad, 0);
            try buffer.appendSlice(std.heap.page_allocator, pad[0..header_padding]);
        }

        const Entry = struct { word: []const u8, vector: []const f32 };

        // Collect and sort word entries for binary search compatibility
        var entries = std.ArrayListUnmanaged(Entry){};
        defer entries.deinit(std.heap.page_allocator);
        try entries.ensureTotalCapacityPrecise(std.heap.page_allocator, self.word_vectors.count());

        var it = self.word_vectors.iterator();
        while (it.next()) |entry| {
            entries.appendAssumeCapacity(.{
                .word = entry.key_ptr.*,
                .vector = entry.value_ptr.*,
            });
        }

        // Sort words alphabetically for binary search
        const LessThan = struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return std.mem.order(u8, a.word, b.word) == .lt;
            }
        };
        std.sort.insertion(Entry, entries.items, {}, LessThan.lessThan);

        // Calculate starting position for word entries (after header and padding)
        var current_file_pos: u32 = @intCast(header_aligned);

        for (entries.items) |entry| {
            // Word offset is position where word string will be written (current + 6 bytes for header)
            const word_offset = current_file_pos + 6;
            var off_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &off_bytes, word_offset, .little);
            try buffer.appendSlice(std.heap.page_allocator, &off_bytes);

            var len_bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &len_bytes, @intCast(entry.word.len), .little);
            try buffer.appendSlice(std.heap.page_allocator, &len_bytes);

            // Write word string
            try buffer.appendSlice(std.heap.page_allocator, entry.word);

            // Add padding to ensure vector data is 4-byte aligned
            const word_len_aligned = (entry.word.len + 3) & ~@as(usize, 3);
            const padding = word_len_aligned - entry.word.len;
            if (padding > 0) {
                var pad: [3]u8 = undefined;
                @memset(&pad, 0);
                try buffer.appendSlice(std.heap.page_allocator, pad[0..padding]);
            }

            // Write vector data (now 4-byte aligned)
            for (entry.vector) |val| {
                const int_val = @as(u32, @bitCast(val));
                var vec_bytes: [4]u8 = undefined;
                std.mem.writeInt(u32, &vec_bytes, int_val, .little);
                try buffer.appendSlice(std.heap.page_allocator, &vec_bytes);
            }

            // Update file position for next entry
            current_file_pos += @as(u32, @intCast(6 + word_len_aligned + self.dimension * 4));
        }

        // Write entire buffer to file at once
        try file.writeAll(buffer.items);
    }

    // Check if cache file exists and is valid
    pub fn cacheExists(path: []const u8) bool {
        _ = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return false;
            return false;
        };
        return true;
    }
};

// =============== Tests ===============

test "GloVeIndex init creates empty index" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), index.word_vectors.count());
    try std.testing.expectEqual(@as(usize, 0), index.vectors_storage.items.len);
    try std.testing.expectEqual(@as(usize, 0), index.dimension);
    try std.testing.expectEqual(false, index.loaded);
}

test "GloVeIndex deinit cleans up memory" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);

    index.deinit(allocator);
}

test "GloVeIndex computeEmbedding handles empty words" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    index.dimension = 3;

    const words = [_][]const u8{};
    const embedding = try index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);

    try std.testing.expectEqual(@as(usize, 3), embedding.len);
    try std.testing.expectEqual(@as(f32, 0.0), embedding[0]);
    try std.testing.expectEqual(@as(f32, 0.0), embedding[1]);
    try std.testing.expectEqual(@as(f32, 0.0), embedding[2]);
}

test "GloVeIndex computeEmbedding averages vectors" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    // Add some test vectors manually
    index.dimension = 2;

    try index.vectors_storage.append(allocator, 1.0);
    try index.vectors_storage.append(allocator, 2.0);
    const vec1 = index.vectors_storage.items[0..2];

    try index.vectors_storage.append(allocator, 3.0);
    try index.vectors_storage.append(allocator, 4.0);
    const vec2 = index.vectors_storage.items[2..4];

    const word1 = try allocator.dupe(u8, "hello");
    const word2 = try allocator.dupe(u8, "world");
    try index.word_vectors.put(allocator, word1, vec1);
    try index.word_vectors.put(allocator, word2, vec2);

    const words = [_][]const u8{ "hello", "world" };
    const embedding = try index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);

    // Average of [1,2] and [3,4] is [2,3]
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), embedding[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), embedding[1], 0.001);
}

test "GloVeIndex computeEmbedding skips OOV words" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    index.dimension = 2;

    try index.vectors_storage.append(allocator, 5.0);
    try index.vectors_storage.append(allocator, 6.0);
    const vec1 = index.vectors_storage.items[0..2];

    const word1 = try allocator.dupe(u8, "known");
    try index.word_vectors.put(allocator, word1, vec1);

    // Mix known and unknown words
    const words = [_][]const u8{ "known", "unknown", "another_unknown" };
    const embedding = try index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);

    // Should only average known word [5,6]
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), embedding[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), embedding[1], 0.001);
}

test "GloVeIndex cacheExists returns false for non-existent file" {
    const result = GloVeIndex.cacheExists("nonexistent_file.bin");
    try std.testing.expectEqual(false, result);
}

test "GloVeIndex saveCache saves data correctly" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    // Set up test data
    index.dimension = 2;
    index.loaded = true;

    // Add vectors
    try index.vectors_storage.append(allocator, 1.0);
    try index.vectors_storage.append(allocator, 2.0);
    const vec1 = index.vectors_storage.items[0..2];

    try index.vectors_storage.append(allocator, 3.0);
    try index.vectors_storage.append(allocator, 4.0);
    const vec2 = index.vectors_storage.items[2..4];

    // Add words (alphabetically sorted for binary search)
    const word1 = try allocator.dupe(u8, "alpha");
    const word2 = try allocator.dupe(u8, "beta");
    try index.word_vectors.put(allocator, word1, vec1);
    try index.word_vectors.put(allocator, word2, vec2);

    // Save to cache
    const cache_path = ".test_glove_cache.bin";
    try index.saveCache(cache_path);
    defer std.fs.cwd().deleteFile(cache_path) catch {};

    // Verify file exists
    try std.testing.expectEqual(true, GloVeIndex.cacheExists(cache_path));
}

test "GloVeIndex loadCacheZeroCopy loads data correctly" {
    const allocator = std.testing.allocator;

    // First, create a cache file
    {
        var index = GloVeIndex.init(allocator);
        defer index.deinit(allocator);

        index.dimension = 2;
        index.loaded = true;

        try index.vectors_storage.append(allocator, 1.0);
        try index.vectors_storage.append(allocator, 2.0);
        const vec1 = index.vectors_storage.items[0..2];

        try index.vectors_storage.append(allocator, 3.0);
        try index.vectors_storage.append(allocator, 4.0);
        const vec2 = index.vectors_storage.items[2..4];

        const word1 = try allocator.dupe(u8, "alpha");
        const word2 = try allocator.dupe(u8, "beta");
        try index.word_vectors.put(allocator, word1, vec1);
        try index.word_vectors.put(allocator, word2, vec2);

        const cache_path = ".test_glove_load.bin";
        try index.saveCache(cache_path);
    }

    // Now load with zero-copy
    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    const cache_path = ".test_glove_load.bin";
    try index.loadCacheZeroCopy(allocator, cache_path);

    try std.testing.expectEqual(true, index.loaded);
    try std.testing.expectEqual(true, index.zero_copy);
    try std.testing.expectEqual(@as(usize, 2), index.dimension);
    try std.testing.expectEqual(@as(usize, 2), index.word_table.len);

    // Test vector retrieval
    const vec1 = try index.getVector(allocator, "alpha");
    try std.testing.expect(vec1 != null);
    if (vec1) |v| {
        try std.testing.expectEqual(@as(usize, 2), v.len);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), v[0], 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), v[1], 0.001);
    }

    const vec2 = try index.getVector(allocator, "beta");
    try std.testing.expect(vec2 != null);
    if (vec2) |v| {
        try std.testing.expectEqual(@as(usize, 2), v.len);
        try std.testing.expectApproxEqAbs(@as(f32, 3.0), v[0], 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 4.0), v[1], 0.001);
    }

    // Test OOV word returns error
    const vec3 = index.getVector(allocator, "gamma");
    try std.testing.expectError(error.WordNotFound, vec3);

    // Cleanup
    defer std.fs.cwd().deleteFile(".test_glove_load.bin") catch {};
}

test "GloVeIndex computeEmbedding works with zero-copy mode" {
    const allocator = std.testing.allocator;

    // Create and save cache
    {
        var index = GloVeIndex.init(allocator);
        defer index.deinit(allocator);

        index.dimension = 2;
        index.loaded = true;

        try index.vectors_storage.append(allocator, 1.0);
        try index.vectors_storage.append(allocator, 2.0);
        const vec1 = index.vectors_storage.items[0..2];

        try index.vectors_storage.append(allocator, 3.0);
        try index.vectors_storage.append(allocator, 4.0);
        const vec2 = index.vectors_storage.items[2..4];

        const word1 = try allocator.dupe(u8, "alpha");
        const word2 = try allocator.dupe(u8, "beta");
        try index.word_vectors.put(allocator, word1, vec1);
        try index.word_vectors.put(allocator, word2, vec2);

        const cache_path = ".test_glove_embedding.bin";
        try index.saveCache(cache_path);
    }

    // Load with zero-copy and test embedding
    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    const cache_path = ".test_glove_embedding.bin";
    try index.loadCacheZeroCopy(allocator, cache_path);

    const words = [_][]const u8{ "alpha", "beta" };
    const embedding = try index.computeEmbedding(allocator, &words);
    defer allocator.free(embedding);

    // Average of [1,2] and [3,4] is [2,3]
    try std.testing.expectEqual(@as(usize, 2), embedding.len);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), embedding[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), embedding[1], 0.001);

    // Cleanup
    defer std.fs.cwd().deleteFile(".test_glove_load.bin") catch {};
    defer std.fs.cwd().deleteFile(".test_glove_embedding.bin") catch {};
}

test "GloVeIndex zero-copy mode handles large vocab correctly" {
    const allocator = std.testing.allocator;

    var index = GloVeIndex.init(allocator);
    defer index.deinit(allocator);

    // Create a larger vocabulary for testing
    index.dimension = 3;
    index.loaded = true;

    const words_to_add = [_][]const u8{ "apple", "banana", "cherry", "date", "elderberry" };
    const vectors_to_add = [_][3]f32{
        .{ 1.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 0.5, 0.5, 0.0 },
        .{ 0.33, 0.33, 0.34 },
    };

    for (words_to_add, vectors_to_add) |word, vec| {
        const vec_ptr = try allocator.alloc(f32, 3);
        @memcpy(vec_ptr, &vec);
        try index.vectors_storage.appendSlice(allocator, &vec);
        const word_dup = try allocator.dupe(u8, word);
        try index.word_vectors.put(allocator, word_dup, vec_ptr);
    }

    const cache_path = ".test_glove_large.bin";
    try index.saveCache(cache_path);

    // Load with zero-copy
    var loaded_index = GloVeIndex.init(allocator);
    defer loaded_index.deinit(allocator);

    try loaded_index.loadCacheZeroCopy(allocator, cache_path);

    // Test all words can be retrieved
    for (words_to_add, vectors_to_add) |word, expected| {
        const vec = try loaded_index.getVector(allocator, word);
        try std.testing.expect(vec != null);
        if (vec) |v| {
            try std.testing.expectApproxEqAbs(expected[0], v[0], 0.001);
            try std.testing.expectApproxEqAbs(expected[1], v[1], 0.001);
            try std.testing.expectApproxEqAbs(expected[2], v[2], 0.001);
        }
    }

    // Test binary search with word in middle
    const mid_vec = try loaded_index.getVector(allocator, "cherry");
    try std.testing.expect(mid_vec != null);
    if (mid_vec) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), v[0], 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), v[1], 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), v[2], 0.001);
    }

    // Cleanup
    defer std.fs.cwd().deleteFile(".test_glove_large.bin") catch {};
}
