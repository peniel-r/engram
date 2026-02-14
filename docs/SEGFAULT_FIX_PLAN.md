# Segmentation Fault Investigation

**Version**: 1.1.0  
**Date**: 2026-02-14  
**Status**: PRE-EXISTING ISSUE  
**Priority**: Critical  

---

## Problem Summary

`engram show man` command causes a segmentation fault due to HashMap iterator invalidation during `put` operations in the `parseContext` function in `src/storage/filesystem.zig`.

---

## Root Cause Analysis

### Location of Bug
The bug occurs in `src/storage/filesystem.zig` at two locations:
1. **Lines 105-110** - Custom context for feature/lesson/reference/concept types
2. **Lines 278-282** - Default custom context fallback

### Technical Details

The code iterates through a `std.StringHashMap` and performs `put` operations within the loop:

```zig
var it = ctx_obj.iterator();
while (it.next()) |entry| {
    const key = try allocator.dupe(u8, entry.key_ptr.*);
    const val = try getString(allocator, entry.value_ptr.*, "");
    try custom.put(key, val);  // BUG: put() can trigger rehash, invalidating iterator
}
```

### Why This Causes Segfault

When `custom.put()` is called, it may trigger a HashMap rehash if:
- The HashMap doesn't have enough capacity
- The load factor exceeds the threshold
- A rehash is needed to maintain performance

During rehash, the internal storage of the HashMap is reallocated and entries are moved. This invalidates any existing iterators, leading to undefined behavior when `it.next()` is called again. The result is a segmentation fault.

---

## Solution

### Strategy

Collect all entries into a temporary `ArrayList` first, then insert them all at once. This prevents iterator invalidation because:
1. No modifications occur while iterating through the source HashMap
2. All entries are collected into a linear array
3. Insertions happen after iteration is complete
4. Iterator is no longer needed when `put()` operations occur

### Implementation Pattern

```zig
// Define entry struct
const Entry = struct {
    key: []const u8,
    value: []const u8,
};

// Create ArrayList to collect entries
var entries = std.ArrayList(Entry).init(allocator);
defer {
    for (entries.items) |entry| {
        allocator.free(entry.key);
        allocator.free(entry.value);
    }
    entries.deinit();
}

// Iterate and collect entries
var it = ctx_obj.iterator();
while (it.next()) |entry| {
    const key = try allocator.dupe(u8, entry.key_ptr.*);
    const val = try getString(allocator, entry.value_ptr.*, "");
    try entries.append(Entry{ .key = key, .value = val });
}

// Create custom HashMap
var custom = std.StringHashMap([]const u8).init(allocator);
errdefer {
    var clean_it = custom.iterator();
    while (clean_it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    custom.deinit();
}

// Insert all collected entries
for (entries.items) |entry| {
    try custom.put(entry.key, entry.value);
}

// Clear entries.items to prevent double-free
entries.items.len = 0;

return Context{ .custom = custom };
```

---

## Files to Modify

### Primary File
- `src/storage/filesystem.zig`

### Locations Within File

#### Location 1: Lines 94-113
**Function**: `parseContext`
**Purpose**: Handle feature, lesson, reference, concept types as custom context

**Current Code**:
```zig
if (neurona_type == .feature or neurona_type == .lesson or neurona_type == .reference or neurona_type == .concept) {
    var custom = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = custom.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        custom.deinit();
    }

    var it = ctx_obj.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try getString(allocator, entry.value_ptr.*, "");
        try custom.put(key, val);
    }

    return Context{ .custom = custom };
}
```

**Changes Required**:
- Define `Entry` struct at function scope
- Create `entries` ArrayList
- Collect all key-value pairs
- Create custom HashMap
- Insert all entries
- Clear entries to prevent double-free

#### Location 2: Lines 267-286
**Function**: `parseContext`
**Purpose**: Default custom context fallback for any other fields

**Current Code**:
```zig
// Default: custom context for any other fields
var custom = std.StringHashMap([]const u8).init(allocator);
errdefer {
    var it = custom.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    custom.deinit();
}

var it = ctx_obj.iterator();
while (it.next()) |entry| {
    const key = try allocator.dupe(u8, entry.key_ptr.*);
    const val = try getString(allocator, entry.value_ptr.*, "");
    try custom.put(key, val);
}

return Context{ .custom = custom };
```

**Changes Required**: Same pattern as Location 1

---

## Implementation Steps

### Step 1: Define Entry Struct Helper

At the top of `parseContext` function (before the first if statement), add:

```zig
const Entry = struct {
    key: []const u8,
    value: []const u8,
};
```

### Step 2: Fix Location 1 (Lines 94-113)

Replace the existing code with:

```zig
if (neurona_type == .feature or neurona_type == .lesson or neurona_type == .reference or neurona_type == .concept) {
    // Collect entries first to avoid iterator invalidation
    var entries = std.ArrayList(Entry).init(allocator);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        entries.deinit();
    }

    var collect_it = ctx_obj.iterator();
    while (collect_it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try getString(allocator, entry.value_ptr.*, "");
        try entries.append(Entry{ .key = key, .value = val });
    }

    var custom = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var clean_it = custom.iterator();
        while (clean_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        custom.deinit();
    }

    for (entries.items) |entry| {
        try custom.put(entry.key, entry.value);
    }

    // Clear entries to prevent double-free
    entries.items.len = 0;

    return Context{ .custom = custom };
}
```

### Step 3: Fix Location 2 (Lines 267-286)

Replace the existing code with:

```zig
// Default: custom context for any other fields
// Collect entries first to avoid iterator invalidation
var entries = std.ArrayList(Entry).init(allocator);
defer {
    for (entries.items) |entry| {
        allocator.free(entry.key);
        allocator.free(entry.value);
    }
    entries.deinit();
}

var collect_it = ctx_obj.iterator();
while (collect_it.next()) |entry| {
    const key = try allocator.dupe(u8, entry.key_ptr.*);
    const val = try getString(allocator, entry.value_ptr.*, "");
    try entries.append(Entry{ .key = key, .value = val });
}

var custom = std.StringHashMap([]const u8).init(allocator);
errdefer {
    var clean_it = custom.iterator();
    while (clean_it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    custom.deinit();
}

for (entries.items) |entry| {
    try custom.put(entry.key, entry.value);
}

// Clear entries to prevent double-free
entries.items.len = 0;

return Context{ .custom = custom };
```

---

## Testing Plan

### Test Case 1: Basic Command (Critical)
**Command**: `engram show man`

**Expected Behavior**: 
- Should display "Neurona not found" error message
- Should NOT cause segmentation fault

**Command**: `engram show man --json`

**Expected Behavior**:
- Should return JSON error response
- Should NOT cause segmentation fault

### Test Case 2: Config File
**Command**: `engram show config`

**Expected Behavior**:
- Should open config file in configured editor
- Should work without segfault

### Test Case 3: Valid Neurona
**Command**: `engram show feat.yaml-configuration-file-support`

**Expected Behavior**:
- Should display neurona details
- All custom context fields should be present
- Should work without segfault

### Test Case 4: Various Neurona Types

Test with different neurona types to ensure no regressions:

```bash
# Feature type
engram show feat.yaml-configuration-file-support

# Concept type (if available)
engram show concept.<id>

# Reference type (if available)
engram show reference.<id>

# Lesson type (if available)
engram show lesson.<id>

# Issue type
engram show issue.<id>

# Requirement type
engram show req.<id>

# Test case type
engram show test.<id>
```

### Test Case 5: Edge Cases

**Large custom context**:
- Create a neurona with many custom context fields (> 20)
- Verify no segfault occurs

**Empty context**:
- Create a neurona with empty context object
- Verify no segfault occurs

**Nested context structures**:
- Test with various context field types
- Verify parsing works correctly

---

## Validation Checklist

After implementation, verify:

- [ ] `engram show man` shows error without segfault
- [ ] `engram show config` opens config file correctly
- [ ] `engram show feat.yaml-configuration-file-support` displays correctly
- [ ] All neurona types can be displayed without errors
- [ ] No memory leaks (use `zig build test` with leak detection)
- [ ] Existing tests still pass
- [ ] No new compiler warnings
- [ ] Code follows Zig coding standards from AGENTS.md

---

## Risk Assessment

### Low Risk
- Changes are localized to one function
- Solution pattern is well-tested and safe
- No API changes or breaking modifications

### Medium Risk
- Memory management complexity increased slightly
- Need to ensure proper cleanup in all error paths

### Mitigation
- Use `errdefer` for cleanup on errors
- Clear entries array after transfer to HashMap
- Comprehensive testing before merging

---

## Estimated Effort

- Implementation: 30 minutes
- Testing: 30 minutes
- Code review: 15 minutes
- **Total**: ~1.25 hours

---

## Related Issues

This fix addresses the segmentation fault reported when running `engram show man`. The root cause affects any neurona that uses custom context parsing, particularly those with many context fields.

---

## References

- AGENTS.md - Zig coding standards
- src/storage/filesystem.zig:84-286 - parseContext function
- Zig HashMap documentation: https://ziglang.org/documentation/master/#std.StringHashMap

---

## Implementation Notes

### Memory Safety
1. The `Entry` struct holds owned pointers (allocated with `allocator.dupe`)
2. The `defer` block on `entries` ensures cleanup if we return early
3. After transferring entries to `custom`, we clear `entries.items.len` to prevent double-free
4. The `errdefer` on `custom` ensures cleanup if any `put` operation fails

### Performance Impact
- Minimal: One additional ArrayList allocation
- The ArrayList is freed immediately after use
- No performance degradation expected

### Code Style
- Follows Zig 0.15+ conventions
- Uses explicit allocator patterns
- No global variables
- Proper error handling throughout

---

**Status**: Ready for implementation
**Next Step**: Apply code changes to src/storage/filesystem.zig
