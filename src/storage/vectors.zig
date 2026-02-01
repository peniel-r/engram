// Vector Storage Implementation
// Manages vector embeddings in binary format with in-memory index
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Binary format constants
/// Binary format constants
pub const MAGIC = "VECT";
pub const VERSION: u32 = 1;

/// Binary header for vector index file
/// Total size: 40 bytes
pub const VectorHeader = struct {
    magic: [4]u8,
    version: u32,
    timestamp: i64,
    dim: u64,
    count: u64,
    checksum: u32,
    padding: u32 = 0,
};

/// Vector with data and precomputed L2 norm
pub const Vector = struct {
    data: []f32,
    norm: f32,

    pub fn init(allocator: Allocator, dimension: usize) !Vector {
        const data = try allocator.alloc(f32, dimension);
        @memset(data, 0.0);
        return Vector{ .data = data, .norm = 0.0 };
    }

    pub fn initFromData(allocator: Allocator, data: []const f32) !Vector {
        const vector_data = try allocator.alloc(f32, data.len);
        @memcpy(vector_data, data);
        var vector = Vector{ .data = vector_data, .norm = 0.0 };
        vector.computeNorm();
        return vector;
    }

    pub fn deinit(self: *Vector, allocator: Allocator) void {
        allocator.free(self.data);
        self.data = &[_]f32{};
        self.norm = 0.0;
    }

    pub fn computeNorm(self: *Vector) void {
        var sum: f32 = 0.0;
        for (self.data) |val| sum += val * val;
        self.norm = @sqrt(sum);
    }
};

pub const SearchResult = struct {
    doc_id: []const u8,
    score: f32,
    pub fn deinit(self: *SearchResult, allocator: Allocator) void {
        allocator.free(self.doc_id);
    }
};

pub const VectorIndex = struct {
    vectors: std.StringHashMapUnmanaged(Vector),
    dimension: usize,

    pub fn init(_allocator: Allocator, dimension: usize) VectorIndex {
        _ = _allocator;
        return VectorIndex{ .vectors = .{}, .dimension = dimension };
    }

    pub fn deinit(self: *VectorIndex, allocator: Allocator) void {
        var it = self.vectors.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.vectors.deinit(allocator);
    }

    pub fn cosineSimilarity(self: *const VectorIndex, vec1: []const f32, vec2: []const f32) f32 {
        if (vec1.len != self.dimension or vec2.len != self.dimension) return 0.0;
        var dot: f32 = 0.0;
        for (vec1, vec2) |a, b| dot += a * b;
        var norm1: f32 = 0.0;
        for (vec1) |a| norm1 += a * a;
        norm1 = @sqrt(norm1);
        var norm2: f32 = 0.0;
        for (vec2) |b| norm2 += b * b;
        norm2 = @sqrt(norm2);
        if (norm1 == 0.0 or norm2 == 0.0) return 0.0;
        return dot / (norm1 * norm2);
    }

    pub fn addVector(self: *VectorIndex, allocator: Allocator, doc_id: []const u8, data: []const f32) !void {
        if (data.len != self.dimension) return error.DimensionMismatch;
        const vector = try Vector.initFromData(allocator, data);
        try self.vectors.put(allocator, try allocator.dupe(u8, doc_id), vector);
    }

    pub fn getVector(self: *const VectorIndex, doc_id: []const u8) ?[]const f32 {
        const vector = self.vectors.get(doc_id) orelse return null;
        return vector.data;
    }

    pub fn search(self: *const VectorIndex, allocator: Allocator, query_vec: []const f32, limit: usize) ![]SearchResult {
        if (query_vec.len != self.dimension) return error.DimensionMismatch;
        var results = std.ArrayListUnmanaged(SearchResult){};
        try results.ensureTotalCapacity(allocator, self.vectors.count());
        var it = self.vectors.iterator();
        while (it.next()) |entry| {
            const doc_id = entry.key_ptr.*;
            const vector = entry.value_ptr.*;
            const similarity = self.cosineSimilarity(query_vec, vector.data);
            try results.append(allocator, .{
                .doc_id = try allocator.dupe(u8, doc_id),
                .score = similarity,
            });
        }
        std.sort.pdq(SearchResult, results.items, {}, struct {
            fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
                return a.score > b.score;
            }
        }.lessThan);
        if (results.items.len > limit) {
            for (results.items[limit..]) |*r| r.deinit(allocator);
            results.items.len = limit;
        }
        return results.toOwnedSlice(allocator);
    }

    /// Get default vector index file path
    pub fn getVectorIndexPath(allocator: Allocator) ![]const u8 {
        return try allocator.dupe(u8, ".activations/vectors.bin");
    }

    /// Save index to binary file with header and checksum
    pub fn save(self: *const VectorIndex, allocator: Allocator, path: []const u8, timestamp: i64) !void {
        var data = std.ArrayListUnmanaged(u8){};
        defer data.deinit(allocator);
        const writer = data.writer(allocator);

        // Write vectors data
        var it = self.vectors.iterator();
        while (it.next()) |entry| {
            const doc_id = entry.key_ptr.*;
            const vector = entry.value_ptr.*;
            try writer.writeInt(u16, @intCast(doc_id.len), .little);
            try writer.writeAll(doc_id);
            for (vector.data) |val| {
                try writer.writeInt(u32, @bitCast(val), .little);
            }
        }

        // Compute checksum
        const checksum = std.hash.Crc32.hash(data.items);

        // Prepare and write header
        var header = VectorHeader{
            .magic = MAGIC.*,
            .version = VERSION,
            .timestamp = timestamp,
            .dim = @intCast(self.dimension),
            .count = @intCast(self.vectors.count()),
            .checksum = checksum,
        };

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(std.mem.asBytes(&header));
        try file.writeAll(data.items);
    }

    /// Loaded index with metadata
    pub const LoadedIndex = struct {
        index: VectorIndex,
        timestamp: i64,
    };

    /// Load index from binary file with validation
    pub fn load(allocator: Allocator, path: []const u8) !LoadedIndex {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var header: VectorHeader = undefined;
        const header_bytes_read = try file.read(std.mem.asBytes(&header));
        if (header_bytes_read < @sizeOf(VectorHeader)) return error.EndOfStream;

        if (!std.mem.eql(u8, &header.magic, MAGIC)) return error.InvalidHeader;
        if (header.version != VERSION) return error.UnsupportedVersion;

        const content_data = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
        defer allocator.free(content_data);

        // Verify checksum
        const computed_checksum = std.hash.Crc32.hash(content_data);
        if (computed_checksum != header.checksum) return error.ChecksumMismatch;

        var index = VectorIndex.init(allocator, @intCast(header.dim));
        errdefer index.deinit(allocator);

        var stream = std.io.fixedBufferStream(content_data);
        const s_reader = stream.reader();

        var i: u64 = 0;
        while (i < header.count) : (i += 1) {
            const doc_id_len = try s_reader.readInt(u16, .little);
            const doc_id = try allocator.alloc(u8, doc_id_len);
            defer allocator.free(doc_id);
            try s_reader.readNoEof(doc_id);

            const vector_data = try allocator.alloc(f32, @intCast(header.dim));
            defer allocator.free(vector_data);
            var j: usize = 0;
            while (j < header.dim) : (j += 1) {
                vector_data[j] = @bitCast(try s_reader.readInt(u32, .little));
            }

            try index.addVector(allocator, doc_id, vector_data);
        }

        return LoadedIndex{
            .index = index,
            .timestamp = header.timestamp,
        };
    }
};

test "VectorIndex save/load with CRC and Metadata" {
    const allocator = std.testing.allocator;

    std.fs.cwd().deleteTree(".activations") catch {};
    defer std.fs.cwd().deleteTree(".activations") catch {};

    var index = VectorIndex.init(allocator, 3);
    defer index.deinit(allocator);

    try index.addVector(allocator, "doc1", &[_]f32{ 1.0, 0.0, 0.0 });
    try index.addVector(allocator, "doc2", &[_]f32{ 0.0, 1.0, 0.0 });

    const tmp_path = ".activations/test_vectors.bin";
    _ = std.fs.cwd().makePath(".activations") catch {};
    try index.save(allocator, tmp_path, 123456789);

    const loaded = try VectorIndex.load(allocator, tmp_path);
    var loaded_index = loaded.index;
    defer loaded_index.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 123456789), loaded.timestamp);

    try std.testing.expectEqual(index.dimension, loaded_index.dimension);
    try std.testing.expectEqual(index.vectors.count(), loaded_index.vectors.count());

    const v1 = loaded_index.getVector("doc1").?;
    try std.testing.expectEqual(@as(f32, 1.0), v1[0]);
    try std.testing.expectEqual(@as(f32, 0.0), v1[1]);

    const v2 = loaded_index.getVector("doc2").?;
    try std.testing.expectEqual(@as(f32, 0.0), v2[0]);
    try std.testing.expectEqual(@as(f32, 1.0), v2[1]);
}
