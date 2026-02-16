//! Wikilink Parser for Engram Notes System
//! Parses [[wikilink]] syntax and converts to markdown links
//! Extracts connection suggestions from wikilinks

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Parsed wikilink information
pub const Wikilink = struct {
    /// Full text including brackets (e.g., "[[concept]]")
    full_text: []const u8,
    /// Link target (e.g., "concept")
    target: []const u8,
    /// Optional display text (e.g., "display" in "[[concept|display]]")
    display: ?[]const u8,
    /// Start position in source text
    start: usize,
    /// End position in source text
    end: usize,
};

/// Connection suggestion extracted from wikilink
pub const ConnectionSuggestion = struct {
    /// Target neurona ID
    target_id: []const u8,
    /// Suggested connection type
    connection_type: []const u8,
    /// Suggested weight
    weight: u8 = 50,
};

/// Parse all wikilinks from text
pub fn parse(allocator: Allocator, text: []const u8) ![]Wikilink {
    var result = std.ArrayListUnmanaged(Wikilink){};
    errdefer {
        for (result.items) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
        }
        result.deinit(allocator);
    }

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        // Find opening [[
        if (text[i] == '[' and i + 1 < text.len and text[i + 1] == '[') {
            const start = i;
            
            // Find closing ]]
            const closing = std.mem.indexOfPos(u8, text, i + 2, "]]") orelse {
                // No closing found, skip
                continue;
            };
            
            const link_text = text[start + 2 .. closing];
            
            // Parse display text if present (format: [[target|display]])
            const display_opt: ?[]const u8 = if (std.mem.indexOf(u8, link_text, "|")) |pipe_pos| {
                const target = link_text[0..pipe_pos];
                const display = link_text[pipe_pos + 1 ..];
                
                // Need to allocate separate copies
                const target_copy = try allocator.dupe(u8, target);
                const display_copy = try allocator.dupe(u8, display);
                
                display_copy; // Return display copy
            } else null;
            
            const target_text = if (display_opt) |_| 
                // If there's a display, get target before the pipe
                if (std.mem.indexOf(u8, link_text, "|")) |pipe_pos| link_text[0..pipe_pos] else link_text
            else
                link_text;
            
            const full_text_copy = try allocator.dupe(u8, text[start .. closing + 2]);
            
            // Allocate display copy if present
            var display_copy: ?[]const u8 = null;
            if (std.mem.indexOf(u8, link_text, "|")) |pipe_pos| {
                display_copy = try allocator.dupe(u8, link_text[pipe_pos + 1 ..]);
            }
            
            const target_copy = if (display_copy != null)
                link_text[0..std.mem.indexOf(u8, link_text, "|").?]
            else
                link_text;
            
            // Allocate target copy separately
            const target_allocated = try allocator.dupe(u8, target_copy);
            
            try result.append(allocator, .{
                .full_text = full_text_copy,
                .target = target_allocated,
                .display = display_copy,
                .start = start,
                .end = closing + 2,
            });
            
            i = closing + 1; // Skip to closing bracket
        }
    }
    
    return try result.toOwnedSlice(allocator);
}

/// Convert wikilinks to markdown links
/// Format: [[target|display]] -> [display](#target)
/// Format: [[target]] -> [target](#target)
pub fn convertToMarkdownLinks(allocator: Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);
    const writer = result.writer(allocator);
    
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        // Find opening [[
        if (text[i] == '[' and i + 1 < text.len and text[i + 1] == '[') {
            const start = i;
            
            // Find closing ]]
            const closing = std.mem.indexOfPos(u8, text, i + 2, "]]") orelse {
                // No closing, write as is and continue
                try writer.writeAll(text[i..i+1]);
                continue;
            };
            
            const link_text = text[start + 2 .. closing];
            
            // Check for display text
            if (std.mem.indexOf(u8, link_text, "|")) |pipe_pos| {
                const target = link_text[0..pipe_pos];
                const display = link_text[pipe_pos + 1 ..];
                try writer.print("[{s}](#{s})", .{ display, target });
            } else {
                try writer.print("[{s}](#{s})", .{ link_text, link_text });
            }
            
            i = closing + 1; // Skip to closing bracket
        } else {
            try writer.writeByte(text[i]);
        }
    }
    
    return try result.toOwnedSlice(allocator);
}

/// Extract connection suggestions from wikilinks
/// Returns list of suggested connections based on link patterns
pub fn extractConnections(allocator: Allocator, text: []const u8) ![]ConnectionSuggestion {
    var wikilinks = try parse(allocator, text);
    defer {
        for (wikilinks) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
            allocator.free(wl.target);
        }
        allocator.free(wikilinks);
    }
    
    var suggestions = std.ArrayListUnmanaged(ConnectionSuggestion){};
    errdefer {
        for (suggestions.items) |*s| allocator.free(s.target_id);
        allocator.free(s.connection_type);
        suggestions.deinit(allocator);
    }
    
    for (wikilinks) |wl| {
        // Determine connection type based on target patterns
        const conn_type = try guessConnectionType(allocator, wl.target);
        errdefer allocator.free(conn_type);
        
        const target_copy = try allocator.dupe(u8, wl.target);
        
        try suggestions.append(allocator, .{
            .target_id = target_copy,
            .connection_type = conn_type,
            .weight = 50,
        });
    }
    
    return try suggestions.toOwnedSlice(allocator);
}

/// Guess connection type from link target
fn guessConnectionType(allocator: Allocator, target: []const u8) ![]const u8 {
    _ = allocator;
    _ = target;
    // Simple heuristic: default to "relates_to"
    // In a more sophisticated version, we could analyze:
    // - Target neurona type
    // - Context in which link appears
    // - Keywords in target name
    return try allocator.dupe(u8, "relates_to");
}

/// Check if text contains wikilinks
pub fn containsWikilinks(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "[[") != null;
}

/// Count wikilinks in text
pub fn countWikilinks(text: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '[' and i + 1 < text.len and text[i + 1] == '[') {
            count += 1;
            // Skip to closing ]]
            if (std.mem.indexOfPos(u8, text, i + 2, "]]")) |closing| {
                i = closing + 1;
            } else {
                break;
            }
        }
    }
    return count;
}

// ==================== Tests ====================

test "parse extracts simple wikilinks" {
    const allocator = std.testing.allocator;
    
    const text = "This is a [[concept]] with a link.";
    const links = try parse(allocator, text);
    defer {
        for (links) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
            allocator.free(wl.target);
        }
        allocator.free(links);
    }
    
    try std.testing.expectEqual(@as(usize, 1), links.len);
    try std.testing.expectEqualStrings("concept", links[0].target);
}

test "parse extracts wikilinks with display text" {
    const allocator = std.testing.allocator;
    
    const text = "See [[concept|Concept A]] for details.";
    const links = try parse(allocator, text);
    defer {
        for (links) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
            allocator.free(wl.target);
        }
        allocator.free(links);
    }
    
    try std.testing.expectEqual(@as(usize, 1), links.len);
    try std.testing.expectEqualStrings("concept", links[0].target);
    try std.testing.expect(links[0].display != null);
    try std.testing.expectEqualStrings("Concept A", links[0].display.?);
}

test "parse handles multiple wikilinks" {
    const allocator = std.testing.allocator;
    
    const text = "[[first]] and [[second]] links";
    const links = try parse(allocator, text);
    defer {
        for (links) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
            allocator.free(wl.target);
        }
        allocator.free(links);
    }
    
    try std.testing.expectEqual(@as(usize, 2), links.len);
    try std.testing.expectEqualStrings("first", links[0].target);
    try std.testing.expectEqualStrings("second", links[1].target);
}

test "parse handles no wikilinks" {
    const allocator = std.testing.allocator;
    
    const text = "This is just plain text.";
    const links = try parse(allocator, text);
    defer {
        for (links) |*wl| {
            allocator.free(wl.full_text);
            if (wl.display) |d| allocator.free(d);
            allocator.free(wl.target);
        }
        allocator.free(links);
    }
    
    try std.testing.expectEqual(@as(usize, 0), links.len);
}

test "convertToMarkdownLinks converts simple links" {
    const allocator = std.testing.allocator;
    
    const text = "See [[concept]] for details.";
    const result = try convertToMarkdownLinks(allocator, text);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "[concept](#concept)") != null);
}

test "convertToMarkdownLinks converts links with display" {
    const allocator = std.testing.allocator;
    
    const text = "See [[concept|Concept A]] for details.";
    const result = try convertToMarkdownLinks(allocator, text);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "[Concept A](#concept)") != null);
}

test "containsWikilinks detects wikilinks" {
    try std.testing.expect(containsWikilinks("See [[link]]"));
    try std.testing.expect(!containsWikilinks("No links here"));
}

test "countWikilinks counts correctly" {
    try std.testing.expectEqual(@as(usize, 0), countWikilinks("No links"));
    try std.testing.expectEqual(@as(usize, 1), countWikilinks("One [[link]]"));
    try std.testing.expectEqual(@as(usize, 2), countWikilinks("[[one]] and [[two]]"));
}

test "extractConnections creates suggestions" {
    const allocator = std.testing.allocator;
    
    const text = "Links to [[concept1]] and [[concept2]]";
    const suggestions = try extractConnections(allocator, text);
    defer {
        for (suggestions) |*s| {
            allocator.free(s.target_id);
            allocator.free(s.connection_type);
        }
        allocator.free(suggestions);
    }
    
    try std.testing.expectEqual(@as(usize, 2), suggestions.len);
    try std.testing.expectEqualStrings("concept1", suggestions[0].target_id);
    try std.testing.expectEqualStrings("concept2", suggestions[1].target_id);
}