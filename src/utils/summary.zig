// Summary generator for LLM optimization
const std = @import("std");
const Allocator = std.mem.Allocator;
const token_counter = @import("./token_counter.zig");

pub fn generateSummary(allocator: Allocator, text: []const u8, strategy: []const u8, max_tokens: u32) ![]u8 {
    if (std.mem.eql(u8, strategy, "full")) {
        return try allocator.dupe(u8, text);
    }

    if (std.mem.eql(u8, strategy, "summary")) {
        return try generateSimpleSummary(allocator, text, max_tokens);
    }

    if (std.mem.eql(u8, strategy, "hierarchical")) {
        return try generateHierarchicalSummary(allocator, text, max_tokens);
    }

    // Fallback to full if unknown strategy
    return try allocator.dupe(u8, text);
}

fn generateSimpleSummary(allocator: Allocator, text: []const u8, max_tokens: u32) ![]u8 {
    // Naive sentence split by .!? and keep sentences until token limit
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '.' or c == '!' or c == '?') {
            const end = i + 1;
            const sentence = text[start..end];
            // Trim leading spaces
            const s = trimSpaces(sentence);
            if (s.len > 0) {
                // Try append and check token count
                const prev_len = out.items.len;
                try writer.print("{s} ", .{s});
                const tokens = try token_counter.countTokens(allocator, out.items);
                if (tokens > max_tokens and max_tokens > 0) {
                    // Remove last appended sentence by truncating to previous length
                    out.shrinkAndFree(allocator, prev_len);
                    break;
                }
            }
            start = end;
        }
    }

    // If nothing was captured, fallback to first N chars
    if (out.items.len == 0) {
        const take = if (text.len < 200) text.len else 200;
        return try allocator.dupe(u8, text[0..take]);
    }

    // Trim trailing space before returning
    const result = try out.toOwnedSlice(allocator);
    if (result.len > 0 and result[result.len - 1] == ' ') {
        const trimmed = try allocator.dupe(u8, result[0 .. result.len - 1]);
        allocator.free(result);
        return trimmed;
    }
    return result;
}

fn generateHierarchicalSummary(allocator: Allocator, text: []const u8, max_tokens: u32) ![]u8 {
    // Extract headings (lines starting with #) and create indented bullets
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        // find line start
        const line_start = i;
        while (i < text.len and text[i] != '\n') : (i += 1) {}
        const line_end = i;
        const line = text[line_start..line_end];
        const trimmed = trimSpaces(line);
        if (trimmed.len > 0 and trimmed[0] == '#') {
            // count hashes
            var level: usize = 0;
            while (level < trimmed.len and trimmed[level] == '#') : (level += 1) {}
            // skip spaces after hashes
            var content_start = level;
            while (content_start < trimmed.len and (trimmed[content_start] == ' ' or trimmed[content_start] == '\t')) : (content_start += 1) {}
            const heading = trimmed[content_start..];
            // Build bullet: indent by (level-1)*2 spaces
            var indent_buf: [32]u8 = undefined;
            var indent_slice: []const u8 = "";
            if (level > 1) {
                const n = if ((level - 1) * 2 <= indent_buf.len) (level - 1) * 2 else indent_buf.len;
                for (indent_buf[0..n]) |*c| c.* = ' ';
                indent_slice = indent_buf[0..n];
            }
            try writer.print("{s}- {s}\n", .{ indent_slice, heading });

            const current = try out.toOwnedSlice(allocator);
            defer allocator.free(current);
            const tokens = try token_counter.countTokens(allocator, current);
            if (tokens >= max_tokens and max_tokens > 0) break;
        }
    }

    // Fallback to simple summary if no headings
    if (out.items.len == 0) {
        return try generateSimpleSummary(allocator, text, max_tokens);
    }

    return try out.toOwnedSlice(allocator);
}

fn trimSpaces(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) : (start += 1) {}
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n' or s[end - 1] == '\r')) : (end -= 1) {}
    return s[start..end];
}

test "generateSummary full returns original" {
    const allocator = std.testing.allocator;
    const txt = "This is a test. Second sentence.";
    const out = try generateSummary(allocator, txt, "full", 0);
    defer allocator.free(out);
    try std.testing.expectEqualStrings(txt, out);
}

test "generateSummary summary returns shorter or equal" {
    const allocator = std.testing.allocator;
    const txt = "Sentence one. Sentence two. Sentence three.";
    const out = try generateSummary(allocator, txt, "summary", 2);
    defer allocator.free(out);
    const tokens = try @import("./token_counter.zig").countTokens(allocator, out);
    std.debug.print("\nSummary: '{s}', Tokens: {d}\n", .{ out, tokens });
    try std.testing.expect(tokens <= 2);
}

test "generateSummary hierarchical extracts headings" {
    const allocator = std.testing.allocator;
    const txt = "# Title\n## Sub\nContent here.\n# Another";
    const out = try generateSummary(allocator, txt, "hierarchical", 100);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "Title") != null);
}
