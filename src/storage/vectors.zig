// Vector Storage Implementation
// Manages vector embeddings in binary format with in-memory index
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Binary format constants
const HEADER = "ENGRAM_VEC";
const VERSION: u8 = 1;

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
        self.data = &[0]f32{};
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
        std.sort.insertion(SearchResult, results.items, {}, struct {
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

    pub fn save(self: *const VectorIndex, _allocator: Allocator, path: []const u8) !void {
        _ = _allocator;
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const writer = file.writer();
        try writer.writeAll(HEADER);
        try writer.writeInt(u8, VERSION, .little);
        try writer.writeInt(u32, @intCast(self.dimension), .little);
        try writer.writeInt(u32, @intCast(self.vectors.count()), .little);
        var it = self.vectors.iterator();
        while (it.next()) |entry| {
            const doc_id = entry.key_ptr.*;
            const vector = entry.value_ptr.*;
            try writer.writeInt(u16, @intCast(doc_id.len), .little);
            try writer.writeAll(doc_id);
            for (vector.data) |val| try writer.writeInt(f32, val, .little);
        }
    }

    pub fn load(allocator: Allocator, path: []const u8) !VectorIndex {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const reader = file.reader();
        var header_buffer: [HEADER.len]u8 = undefined;
        try reader.readAll(&header_buffer);
        if (!std.mem.eql(u8, &header_buffer, HEADER)) return error.InvalidHeader;
        const version = try reader.readInt(u8, .little);
        if (version != VERSION) return error.UnsupportedVersion;
        const dimension = try reader.readInt(u32, .little);
        const count = try reader.readInt(u32, .little);
        var index = VectorIndex.init(allocator, dimension);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const doc_id_len = try reader.readInt(u16, .little);
            const doc_id = try allocator.alloc(u8, doc_id_len);
            try reader.readAll(doc_id);
            const vector_data = try allocator.alloc(f32, dimension);
            var j: usize = 0;
            while (j < dimension) : (j += 1) vector_data[j] = try reader.readInt(f32, .little);
            try index.addVector(allocator, doc_id, vector_data);
            allocator.free(vector_data);
            allocator.free(doc_id);
        }
        return index;
    }
};
