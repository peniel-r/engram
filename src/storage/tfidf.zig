// BM25 (Best Matching 25) Text Search Implementation
// Implements industry-standard ranking function for text search
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Search result with document ID and relevance score
pub const SearchResult = struct {
    doc_id: []const u8,
    score: f32,

    pub fn deinit(self: *SearchResult, allocator: Allocator) void {
        allocator.free(self.doc_id);
    }
};

/// Tokenize text into words
/// Converts to lowercase and splits on non-alphanumeric characters
/// Filters out tokens shorter than 2 characters
pub fn tokenize(text: []const u8, allocator: Allocator) ![][]const u8 {
    var tokens = std.ArrayListUnmanaged([]const u8){};

    // Handle empty input
    if (text.len == 0) {
        return try tokens.toOwnedSlice(allocator);
    }

    // Convert to lowercase
    const lower = try allocator.alloc(u8, text.len);
    defer allocator.free(lower);
    for (text, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    // Split on non-alphanumeric
    var start: usize = 0;
    var in_word = false;

    for (lower, 0..) |c, i| {
        const is_alpha = std.ascii.isAlphanumeric(c);

        if (is_alpha and !in_word) {
            // Start of word
            start = i;
            in_word = true;
        } else if (!is_alpha and in_word) {
            // End of word
            const token = lower[start..i];
            if (token.len >= 2) {
                try tokens.append(allocator, try allocator.dupe(u8, token));
            }
            in_word = false;
        }
    }

    // Handle last token
    if (in_word) {
        const token = lower[start..];
        if (token.len >= 2) {
            try tokens.append(allocator, try allocator.dupe(u8, token));
        }
    }

    return tokens.toOwnedSlice(allocator);
}

/// BM25 Index for text search
pub const BM25Index = struct {
    // Document statistics
    doc_count: usize,
    avg_doc_length: f32,
    doc_lengths: std.StringHashMapUnmanaged(usize),

    // Term statistics
    term_docs: std.StringHashMapUnmanaged(usize), // Number of docs containing term
    term_freqs: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged(usize)), // Term frequency per doc

    // Tuning parameters
    k1: f32, // Typically 1.2-2.0, controls term frequency saturation
    b: f32, // Typically 0.75, controls document length normalization

    /// Initialize empty BM25 index
    pub fn init() BM25Index {
        return BM25Index{
            .doc_count = 0,
            .avg_doc_length = 0.0,
            .doc_lengths = .{},
            .term_docs = .{},
            .term_freqs = .{},
            .k1 = 1.2,
            .b = 0.75,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *BM25Index, allocator: Allocator) void {
        // Free document lengths
        var doc_it = self.doc_lengths.iterator();
        while (doc_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.doc_lengths.deinit(allocator);

        // Free term frequencies (nested maps)
        var term_it = self.term_freqs.iterator();
        while (term_it.next()) |entry| {
            // Free each document map
            var doc_it_inner = entry.value_ptr.iterator();
            while (doc_it_inner.next()) |doc_entry| {
                allocator.free(doc_entry.key_ptr.*);
            }
            entry.value_ptr.deinit(allocator);

            // Free term key
            allocator.free(entry.key_ptr.*);
        }
        self.term_freqs.deinit(allocator);

        // Free term docs
        var term_docs_it = self.term_docs.iterator();
        while (term_docs_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.term_docs.deinit(allocator);
    }

    /// Add a document to the index
    /// Tokenizes the text and stores term frequencies
    pub fn addDocument(self: *BM25Index, allocator: Allocator, doc_id: []const u8, text: []const u8) !void {
        // Tokenize document
        const tokens = try tokenize(text, allocator);
        defer {
            for (tokens) |t| allocator.free(t);
            allocator.free(tokens);
        }

        // Store document length
        try self.doc_lengths.put(allocator, try allocator.dupe(u8, doc_id), tokens.len);
        self.doc_count += 1;

        // Count term frequencies for this document
        var term_counts = std.StringHashMapUnmanaged(usize){};
        defer {
            var cleanup_it = term_counts.iterator();
            while (cleanup_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            term_counts.deinit(allocator);
        }

        for (tokens) |token| {
            const entry = try term_counts.getOrPut(allocator, token);
            if (!entry.found_existing) {
                entry.key_ptr.* = try allocator.dupe(u8, token);
                entry.value_ptr.* = 0;
            }
            entry.value_ptr.* += 1;
        }

        // Store term frequencies in term_freqs map
        var it = term_counts.iterator();
        while (it.next()) |entry| {
            const term = entry.key_ptr.*;
            const count = entry.value_ptr.*;

            // Get or create term entry
            const term_entry = try self.term_freqs.getOrPut(allocator, term);
            if (!term_entry.found_existing) {
                term_entry.key_ptr.* = try allocator.dupe(u8, term);
                term_entry.value_ptr.* = .{};

                // Initialize term in term_docs
                try self.term_docs.put(allocator, try allocator.dupe(u8, term), 0);
            }

            // Get or create doc entry for this term
            const doc_entry = try term_entry.value_ptr.getOrPut(allocator, doc_id);
            if (!doc_entry.found_existing) {
                doc_entry.key_ptr.* = try allocator.dupe(u8, doc_id);
                doc_entry.value_ptr.* = 0;
            }
            doc_entry.value_ptr.* = count;

            // Update term_docs count (number of docs containing this term)
            const doc_count_ptr = self.term_docs.getPtr(term).?;
            doc_count_ptr.* += 1;
        }
    }

    /// Build index and compute final statistics
    /// Must be called after all documents are added
    pub fn build(self: *BM25Index) void {
        var total_length: usize = 0;
        var it = self.doc_lengths.iterator();
        while (it.next()) |entry| {
            total_length += entry.value_ptr.*;
        }

        if (self.doc_count > 0) {
            self.avg_doc_length = @floatFromInt(total_length);
            self.avg_doc_length /= @as(f32, @floatFromInt(self.doc_count));
        }
    }

    /// Compute Inverse Document Frequency (IDF) for a term
    /// IDF(qi) = log((N - n(qi) + 0.5) / (n(qi) + 0.5) + 1)
    fn computeIDF(self: *const BM25Index, term: []const u8) f32 {
        const n = self.term_docs.get(term) orelse 0;
        if (n == 0) return 0.0;

        const N = @as(f32, @floatFromInt(self.doc_count));
        const n_f = @as(f32, @floatFromInt(n));

        // IDF formula with smoothing
        const num = N - n_f + 0.5;
        const den = n_f + 0.5;
        const idf = @log(num / den + 1.0);

        return idf;
    }

    /// Compute BM25 score for a document given query terms
    /// score(D, Q) = Σ IDF(qi) * (f(qi, D) * (k1 + 1)) / (f(qi, D) + k1 * (1 - b + b * |D| / avgdl))
    fn computeBM25Score(self: *const BM25Index, doc_id: []const u8, query_terms: []const []const u8) f32 {
        var score: f32 = 0.0;

        const doc_len = self.doc_lengths.get(doc_id) orelse 0;
        const doc_len_f = @as(f32, @floatFromInt(doc_len));

        for (query_terms) |term| {
            // Get term frequency in document
            const term_entry = self.term_freqs.get(term) orelse continue;
            const f = term_entry.get(doc_id) orelse 0;
            if (f == 0) continue;

            // Compute IDF
            const idf = self.computeIDF(term);

            // Compute BM25 numerator and denominator
            const f_f = @as(f32, @floatFromInt(f));
            const numerator = f_f * (self.k1 + 1.0);
            const denominator = f_f + self.k1 * (1.0 - self.b + self.b * doc_len_f / self.avg_doc_length);

            score += idf * numerator / denominator;
        }

        return score;
    }

    /// Search for documents matching the query
    /// Returns top-N results sorted by BM25 score (descending)
    pub fn search(self: *const BM25Index, allocator: Allocator, query: []const u8, limit: usize) ![]SearchResult {
        // Tokenize query
        const query_tokens = try tokenize(query, allocator);
        defer {
            for (query_tokens) |t| allocator.free(t);
            allocator.free(query_tokens);
        }

        if (query_tokens.len == 0) return &[_]SearchResult{};

        // Compute scores for all documents
        var results = std.ArrayListUnmanaged(SearchResult){};
        try results.ensureTotalCapacity(allocator, self.doc_count);

        var it = self.doc_lengths.iterator();
        while (it.next()) |entry| {
            const doc_id = entry.key_ptr.*;
            const score = self.computeBM25Score(doc_id, query_tokens);

            if (score > 0) {
                try results.append(allocator, .{
                    .doc_id = try allocator.dupe(u8, doc_id),
                    .score = score,
                });
            }
        }

        // Sort by score (descending)
        std.sort.insertion(SearchResult, results.items, {}, struct {
            fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
                return a.score > b.score; // Descending
            }
        }.lessThan);

        // Limit results
        if (results.items.len > limit) {
            // Free extra results
            for (results.items[limit..]) |*r| {
                r.deinit(allocator);
            }
            results.items.len = limit;
        }

        return results.toOwnedSlice(allocator);
    }
};

test "BM25Index init creates empty index" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), index.doc_count);
    try std.testing.expectEqual(@as(f32, 0.0), index.avg_doc_length);
    try std.testing.expectEqual(@as(usize, 0), index.doc_lengths.count());
    try std.testing.expectEqual(@as(usize, 0), index.term_docs.count());
    try std.testing.expectEqual(@as(usize, 0), index.term_freqs.count());
    try std.testing.expectEqual(@as(f32, 1.2), index.k1);
    try std.testing.expectEqual(@as(f32, 0.75), index.b);
}

test "BM25Index deinit cleans up memory" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    // Test that deinit doesn't crash on empty index
    index.deinit(allocator);

    // Test with some data
    var index2 = BM25Index.init();
    try index2.doc_lengths.put(allocator, try allocator.dupe(u8, "doc1"), 10);
    index2.deinit(allocator);
}

test "SearchResult deinit cleans up doc_id" {
    const allocator = std.testing.allocator;

    var result = SearchResult{
        .doc_id = try allocator.dupe(u8, "test_doc"),
        .score = 0.5,
    };
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("test_doc", result.doc_id);
    try std.testing.expectEqual(@as(f32, 0.5), result.score);
}

test "tokenize basic text" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("Hello World!", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("hello", tokens[0]);
    try std.testing.expectEqualStrings("world", tokens[1]);
}

test "tokenize multiple words" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("Multiple words here", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqualStrings("multiple", tokens[0]);
    try std.testing.expectEqualStrings("words", tokens[1]);
    try std.testing.expectEqualStrings("here", tokens[2]);
}

test "tokenize empty string" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("", allocator);
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 0), tokens.len);
}

test "tokenize filters short tokens" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("a bb ccc dddd", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqualStrings("bb", tokens[0]);
    try std.testing.expectEqualStrings("ccc", tokens[1]);
    try std.testing.expectEqualStrings("dddd", tokens[2]);
}

test "tokenize handles punctuation" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("Hello, world! How are you?", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 5), tokens.len);
    try std.testing.expectEqualStrings("hello", tokens[0]);
    try std.testing.expectEqualStrings("world", tokens[1]);
    try std.testing.expectEqualStrings("how", tokens[2]);
    try std.testing.expectEqualStrings("are", tokens[3]);
    try std.testing.expectEqualStrings("you", tokens[4]);
}

test "tokenize handles lowercase" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("HELLO World", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("hello", tokens[0]);
    try std.testing.expectEqualStrings("world", tokens[1]);
}

test "tokenize handles numbers" {
    const allocator = std.testing.allocator;

    const tokens = try tokenize("test123 data", allocator);
    defer {
        for (tokens) |t| allocator.free(t);
        allocator.free(tokens);
    }

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("test123", tokens[0]);
    try std.testing.expectEqualStrings("data", tokens[1]);
}

test "addDocument indexes single document" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana cherry");

    try std.testing.expectEqual(@as(usize, 1), index.doc_count);
    try std.testing.expectEqual(@as(usize, 1), index.doc_lengths.count());
    try std.testing.expectEqual(@as(usize, 3), index.doc_lengths.get("doc1").?);
    try std.testing.expectEqual(@as(usize, 3), index.term_docs.count());
    try std.testing.expectEqual(@as(usize, 1), index.term_docs.get("apple").?);
    try std.testing.expectEqual(@as(usize, 1), index.term_docs.get("banana").?);
    try std.testing.expectEqual(@as(usize, 1), index.term_docs.get("cherry").?);
}

test "addDocument handles duplicate terms" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple apple banana");

    try std.testing.expectEqual(@as(usize, 1), index.doc_count);
    try std.testing.expectEqual(@as(usize, 3), index.doc_lengths.get("doc1").?);

    // Check term frequency for "apple"
    const apple_entry = index.term_freqs.get("apple").?;
    try std.testing.expectEqual(@as(usize, 2), apple_entry.get("doc1").?);
}

test "addDocument multiple documents" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana");
    try index.addDocument(allocator, "doc2", "apple cherry");
    try index.addDocument(allocator, "doc3", "banana cherry");

    try std.testing.expectEqual(@as(usize, 3), index.doc_count);

    // "apple" appears in 2 docs
    try std.testing.expectEqual(@as(usize, 2), index.term_docs.get("apple").?);
    // "banana" appears in 2 docs
    try std.testing.expectEqual(@as(usize, 2), index.term_docs.get("banana").?);
    // "cherry" appears in 2 docs
    try std.testing.expectEqual(@as(usize, 2), index.term_docs.get("cherry").?);
}

test "build computes average document length" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "one two three four five"); // 5 tokens
    try index.addDocument(allocator, "doc2", "one two three four five six"); // 6 tokens
    try index.addDocument(allocator, "doc3", "one two three"); // 3 tokens

    index.build();

    try std.testing.expectEqual(@as(f32, 14.0 / 3.0), index.avg_doc_length);
}

test "build with zero documents" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    index.build();

    try std.testing.expectEqual(@as(f32, 0.0), index.avg_doc_length);
}

test "computeIDF returns zero for unknown term" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "test content");
    index.build();

    const idf = index.computeIDF("nonexistent");
    try std.testing.expectEqual(@as(f32, 0.0), idf);
}

test "computeIDF for term in all documents" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "common other");
    try index.addDocument(allocator, "doc2", "common other");
    try index.addDocument(allocator, "doc3", "common unique");

    index.build();

    const common_idf = index.computeIDF("common");
    const other_idf = index.computeIDF("other");
    const unique_idf = index.computeIDF("unique");

    try std.testing.expect(common_idf > 0.0);
    // "unique" appears in 1 doc, should have higher IDF than "common" (appears in 3 docs)
    try std.testing.expect(unique_idf > common_idf);
    // "other" appears in 2 docs, should have higher IDF than "common" (appears in 3 docs)
    try std.testing.expect(other_idf > common_idf);
}

test "computeBM25Score with matching document" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana cherry");
    try index.addDocument(allocator, "doc2", "date egg fig");

    index.build();

    // Search for "apple"
    const query_tokens = try tokenize("apple", allocator);
    defer {
        for (query_tokens) |t| allocator.free(t);
        allocator.free(query_tokens);
    }

    const score = index.computeBM25Score("doc1", query_tokens);
    try std.testing.expect(score > 0.0);
}

test "computeBM25Score with non-matching document" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana cherry");
    try index.addDocument(allocator, "doc2", "date egg fig");

    index.build();

    // Search for "apple" in doc2
    const query_tokens = try tokenize("apple", allocator);
    defer {
        for (query_tokens) |t| allocator.free(t);
        allocator.free(query_tokens);
    }

    const score = index.computeBM25Score("doc2", query_tokens);
    try std.testing.expectEqual(@as(f32, 0.0), score);
}

test "computeBM25Score higher for more query terms" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana");
    try index.addDocument(allocator, "doc2", "apple");

    index.build();

    // Query "apple banana"
    const query_tokens = try tokenize("apple banana", allocator);
    defer {
        for (query_tokens) |t| allocator.free(t);
        allocator.free(query_tokens);
    }

    const score_doc1 = index.computeBM25Score("doc1", query_tokens);
    const score_doc2 = index.computeBM25Score("doc2", query_tokens);

    try std.testing.expect(score_doc1 > score_doc2);
}

test "search returns top documents" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple");
    try index.addDocument(allocator, "doc2", "apple banana");
    try index.addDocument(allocator, "doc3", "cherry");

    index.build();

    const results = try index.search(allocator, "apple", 10);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    // Both doc1 and doc2 match "apple"
    try std.testing.expect(results.len == 2);
    // doc1 should be first because it's shorter (better TF ratio)
    try std.testing.expectEqualStrings("doc1", results[0].doc_id);
    try std.testing.expectEqualStrings("doc2", results[1].doc_id);
}

test "search respects limit" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple");
    try index.addDocument(allocator, "doc2", "apple banana");
    try index.addDocument(allocator, "doc3", "apple banana cherry");

    index.build();

    const results = try index.search(allocator, "apple", 2);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "search with empty query" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana");

    index.build();

    const results = try index.search(allocator, "", 10);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "search with no matches" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana");

    index.build();

    const results = try index.search(allocator, "nonexistent term", 10);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "search results sorted by score" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple");
    try index.addDocument(allocator, "doc2", "apple apple");
    try index.addDocument(allocator, "doc3", "apple apple apple");

    index.build();

    const results = try index.search(allocator, "apple", 10);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expect(results.len == 3);
    try std.testing.expect(results[0].score > results[1].score);
    try std.testing.expect(results[1].score > results[2].score);
    try std.testing.expectEqualStrings("doc3", results[0].doc_id);
    try std.testing.expectEqualStrings("doc2", results[1].doc_id);
    try std.testing.expectEqualStrings("doc1", results[2].doc_id);
}

test "search with special characters" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "hello-world");

    index.build();

    const results = try index.search(allocator, "hello world", 10);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expect(results.len == 1);
    try std.testing.expectEqualStrings("doc1", results[0].doc_id);
}

test "search case insensitive" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "APPLE");

    index.build();

    const results = try index.search(allocator, "apple", 10);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expect(results.len == 1);
    try std.testing.expectEqualStrings("doc1", results[0].doc_id);
}

test "search multiple query terms" {
    const allocator = std.testing.allocator;

    var index = BM25Index.init();
    defer index.deinit(allocator);

    try index.addDocument(allocator, "doc1", "apple banana");
    try index.addDocument(allocator, "doc2", "apple");
    try index.addDocument(allocator, "doc3", "banana");

    index.build();

    const results = try index.search(allocator, "apple banana", 10);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    try std.testing.expect(results.len == 3);
    // doc1 should be highest because it has both terms
    try std.testing.expectEqualStrings("doc1", results[0].doc_id);
}
