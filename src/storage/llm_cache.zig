// Simple JSON-backed LLM cache for summaries
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CacheError = error{IoError, InvalidFormat};

fn cacheDir() []const u8 { return ".activations/cache"; }

pub fn getCachePath(allocator: Allocator, neurona_id: []const u8) ![]const u8 {
    // Ensure cache directory exists
    _ = try std.fs.cwd().createDirAll(cacheDir(), 0o755);

    // Build filename: {id}.json
    const filename = try std.fmt.allocPrint(allocator, "{s}.json", .{neurona_id});
    defer allocator.free(filename);
    const path = try std.fs.path.join(allocator, &.{ cacheDir(), filename });
    return path;
}

fn escapeJson(allocator: Allocator, s: []const u8) ![]const u8 {
    // Escape backslash and quote and newline
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    for (s) |c| {
        if (c == '\\') try out.append(allocator, '\\');
        if (c == '"') try out.append(allocator, '\\');
        if (c == '\n') try out.append(allocator, '\\');
        try out.append(allocator, c);
    }
    return try out.toOwnedSlice(allocator);
}

pub fn saveSummary(allocator: Allocator, neurona_id: []const u8, hash: []const u8, summary: []const u8) !void {
    const path = try getCachePath(allocator, neurona_id);
    defer allocator.free(path);

    const fh = try std.fs.cwd().createFile(path, .{});
    defer fh.close();

    const esc_id = try escapeJson(allocator, neurona_id);
    defer allocator.free(esc_id);
    const esc_hash = try escapeJson(allocator, hash);
    defer allocator.free(esc_hash);
    const esc_summary = try escapeJson(allocator, summary);
    defer allocator.free(esc_summary);

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);
    try w.print("{{\"version\":1,\"neurona_id\":\"{s}\",\"hash\":\"{s}\",\"summary\":\"{s}\"}}", .{esc_id, esc_hash, esc_summary});

    const data = try buf.toOwnedSlice(allocator);
    defer allocator.free(data);
    try fh.writeAll(data);
}

fn unescapeJson(allocator: Allocator, s: []const u8) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '\\' and i + 1 < s.len) {
            const n = s[i + 1];
            if (n == 'n') {
                try out.append(allocator, '\n');
            } else {
                try out.append(allocator, n);
            }
            i += 1;
        } else {
            try out.append(allocator, c);
        }
    }
    return try out.toOwnedSlice(allocator);
}

pub fn loadSummary(allocator: Allocator, neurona_id: []const u8) !?[]const u8 {
    const path = try getCachePath(allocator, neurona_id);
    defer allocator.free(path);
    const data = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch return null;
    defer allocator.free(data);

    // Naive JSON parsing: find "summary":"..."
    const key = "\"summary\":\"";
    const idx = std.mem.indexOf(u8, data, key) orelse return null;
    const start = idx + key.len;
    const tail = data[start..];
    const end_rel = std.mem.indexOf(u8, tail, "\"") orelse return null;
    const raw = tail[0..end_rel];
    const unesc = try unescapeJson(allocator, raw);
    return unesc;
}

pub fn invalidateSummary(allocator: Allocator, neurona_id: []const u8) !void {
    const path = try getCachePath(allocator, neurona_id);
    defer allocator.free(path);
    _ = std.fs.cwd().removeFile(path) catch {};
}

pub fn summaryExists(allocator: Allocator, neurona_id: []const u8) bool {
    const path_res = getCachePath(allocator, neurona_id) catch return false;
    defer allocator.free(path_res);
    return std.fs.cwd().access(path_res, .{}) == null;
}

test "llm_cache save/load/invalidate" {
    const allocator = std.testing.allocator;
    const id = "test.neurona";
    const hash = "sha:1";
    const summary = "This is a cached summary.";

    // ensure clean
    _ = invalidateSummary(allocator, id) catch {};

    try saveSummary(allocator, id, hash, summary);
    try std.testing.expect(summaryExists(allocator, id));

    const loaded = try loadSummary(allocator, id);
    defer if (loaded) |s| allocator.free(s);
    try std.testing.expect(loaded orelse false);
    if (loaded) try std.testing.expectEqualStrings(summary, loaded.?);

    try invalidateSummary(allocator, id);
    try std.testing.expect(!summaryExists(allocator, id));
}

