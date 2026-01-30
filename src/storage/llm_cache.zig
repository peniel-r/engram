// LLM Cache storage for summaries and token counts
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Cache entry for an LLM operation
pub const CacheEntry = struct {
    value: []const u8,
    timestamp: i64,
};

/// Cache for token counts
pub const TokenEntry = struct {
    count: u32,
    timestamp: i64,
};

pub const LLMCache = struct {
    summaries: std.StringHashMapUnmanaged(CacheEntry),
    tokens: std.StringHashMapUnmanaged(TokenEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) LLMCache {
        return .{
            .summaries = .{},
            .tokens = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LLMCache) void {
        var sum_it = self.summaries.iterator();
        while (sum_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.summaries.deinit(self.allocator);

        var tok_it = self.tokens.iterator();
        while (tok_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.tokens.deinit(self.allocator);
    }

    /// Generate a cache key from parameters
    pub fn generateKey(allocator: Allocator, neurona_id: []const u8, strategy: []const u8, max_tokens: u32, content_hash: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{s}:{s}:{d}:{s}", .{ neurona_id, strategy, max_tokens, content_hash });
    }

    /// Get a summary from cache if not expired
    pub fn getSummary(self: *LLMCache, key: []const u8, ttl_seconds: i64) ?[]const u8 {
        const entry = self.summaries.get(key) orelse return null;
        const now = std.time.timestamp();
        if (now - entry.timestamp > ttl_seconds and ttl_seconds > 0) return null;
        return entry.value;
    }

    /// Set a summary in cache
    pub fn setSummary(self: *LLMCache, key: []const u8, value: []const u8) !void {
        const key_dupe = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_dupe);
        const value_dupe = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_dupe);

        const gop = try self.summaries.getOrPut(self.allocator, key_dupe);
        if (gop.found_existing) {
            self.allocator.free(key_dupe);
            self.allocator.free(gop.value_ptr.value);
        }
        gop.value_ptr.* = .{
            .value = value_dupe,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Get token count from cache if not expired
    pub fn getTokenCount(self: *LLMCache, neurona_id: []const u8, content_hash: []const u8, ttl_seconds: i64) ?u32 {
        const key = neurona_id; // For simplicity, token count is just by ID + hash
        _ = content_hash; // In a more robust version, we'd incorporate hash into key
        const entry = self.tokens.get(key) orelse return null;
        const now = std.time.timestamp();
        if (now - entry.timestamp > ttl_seconds and ttl_seconds > 0) return null;
        return entry.count;
    }

    /// Set token count in cache
    pub fn setTokenCount(self: *LLMCache, neurona_id: []const u8, count: u32) !void {
        const key_dupe = try self.allocator.dupe(u8, neurona_id);
        errdefer self.allocator.free(key_dupe);

        const gop = try self.tokens.getOrPut(self.allocator, key_dupe);
        if (gop.found_existing) {
            self.allocator.free(key_dupe);
        }
        gop.value_ptr.* = .{
            .count = count,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn saveToDisk(self: *LLMCache, summaries_path: []const u8, tokens_path: []const u8) !void {
        try saveMap(self.allocator, self.summaries, summaries_path);
        try saveMap(self.allocator, self.tokens, tokens_path);
    }

    fn writeJsonString(writer: anytype, s: []const u8) !void {
        try writer.writeAll("\"");
        for (s) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '\"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => if (c < 32) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                },
            }
        }
        try writer.writeAll("\"");
    }

    fn saveMap(allocator: Allocator, map: anytype, path: []const u8) !void {
        var list = std.ArrayListUnmanaged(u8){};
        defer list.deinit(allocator);
        const writer = list.writer(allocator);

        try writer.writeAll("{");
        var first = true;
        var it = map.iterator();
        while (it.next()) |entry| {
            if (!first) try writer.writeAll(",");
            first = false;
            try writeJsonString(writer, entry.key_ptr.*);
            try writer.writeAll(":");

            const V = @TypeOf(entry.value_ptr.*);
            if (V == CacheEntry) {
                try writer.print("{{\"value\":", .{});
                try writeJsonString(writer, entry.value_ptr.value);
                try writer.print(",\"timestamp\":{d}}}", .{entry.value_ptr.timestamp});
            } else if (V == TokenEntry) {
                try writer.print("{{\"count\":{d},\"timestamp\":{d}}}", .{ entry.value_ptr.count, entry.value_ptr.timestamp });
            }
        }
        try writer.writeAll("}");

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(list.items);
    }

    pub fn loadFromDisk(self: *LLMCache, summaries_path: []const u8, tokens_path: []const u8) !void {
        self.loadMap(summaries_path, &self.summaries) catch |err| {
            if (err != error.FileNotFound) return err;
        };
        self.loadMap(tokens_path, &self.tokens) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    fn loadMap(self: *LLMCache, path: []const u8, map: anytype) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return error.FileNotFound;
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        var it = obj.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;

            const key_dupe = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_dupe);

            const gop = try map.getOrPut(self.allocator, key_dupe);
            if (gop.found_existing) {
                self.allocator.free(key_dupe);
            }

            const V = @TypeOf(gop.value_ptr.*);
            if (V == CacheEntry) {
                if (gop.found_existing) self.allocator.free(gop.value_ptr.value);
                gop.value_ptr.* = .{
                    .value = try self.allocator.dupe(u8, val.object.get("value").?.string),
                    .timestamp = val.object.get("timestamp").?.integer,
                };
            } else if (V == TokenEntry) {
                gop.value_ptr.* = .{
                    .count = @intCast(val.object.get("count").?.integer),
                    .timestamp = val.object.get("timestamp").?.integer,
                };
            }
        }
    }

    pub fn cleanup(self: *LLMCache, latest_neuronas: []const []const u8) void {
        _ = self;
        _ = latest_neuronas;
    }
};

test "LLMCache basic" {
    const allocator = std.testing.allocator;
    var cache = LLMCache.init(allocator);
    defer cache.deinit();

    try cache.setSummary("test_id:full:0:hash", "cached summary");
    const hit = cache.getSummary("test_id:full:0:hash", 3600);
    try std.testing.expectEqualStrings("cached summary", hit.?);

    const miss = cache.getSummary("nonexistent", 3600);
    try std.testing.expect(miss == null);
}

test "LLMCache token count" {
    const allocator = std.testing.allocator;
    var cache = LLMCache.init(allocator);
    defer cache.deinit();

    try cache.setTokenCount("test_id", 123);
    const hit = cache.getTokenCount("test_id", "any_hash", 3600);
    try std.testing.expectEqual(@as(u32, 123), hit.?);
}
