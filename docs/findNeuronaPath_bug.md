# findNeuronaPath Segmentation Fault

**Version**: 1.0.0
**Date**: 2026-02-14
**Status**: FIXED
**Priority**: Critical

---

## Problem Summary

`engram show <non-existent-id>` command causes a segmentation fault in the `findNeuronaPath` function when trying to locate a neurona that doesn't exist. This bug is separate from the HashMap iterator invalidation bug fixed in SEGFAULT_FIX_PLAN.md.

---

## Affected Commands

All commands that attempt to read non-existent neuronas:
- `engram show man` - Segfaults
- `engram show <any-invalid-id>` - Segfaults
- Any command that calls `FileOps.readNeuronaWithBody()` with invalid ID

---

## Stack Trace

```
Segmentation fault at address 0x...
C:\...\std\mem\Allocator.zig:430:26: in free
@memset(non_const_ptr[0..bytes_len], undefined);
                         ^
src\storage\filesystem.zig:890:28: in findNeuronaPath
    errdefer allocator.free(id_md);
                           ^
src\utils\file_ops.zig:35:48: in readNeuronaWithBody
    const filepath = try fs.findNeuronaPath(allocator, neuronas_dir, id);
                                               ^
src\cli\show.zig:82:49: in execute
    var result = try FileOps.readNeuronaWithBody(allocator, neuronas_dir, resolved_id.?);
```

**Error Location**: `src/storage/filesystem.zig:890` - Line 900 in current version

---

## Root Cause Analysis

### Location of Bug

The bug occurs in `src/storage/filesystem.zig` in the `findNeuronaPath` function around line 890-900.

### Code Pattern

```zig
pub fn findNeuronaPath(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) ![]const u8 {
    const id_md = try std.fmt.allocPrint(allocator, "{s}.md", .{id});
    errdefer allocator.free(id_md);  // LINE 900 - Potential double-free issue

    var dir = if (std.fs.path.isAbsolute(neuronas_dir))
        std.fs.openDirAbsolute(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        }
    else
        std.fs.cwd().openDir(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        };
    defer dir.close();

    // Check for .md file directly
    if (dir.access(id_md, .{})) |_| {
        const result = try std.fs.path.join(allocator, &.{ neuronas_dir, id_md });
        allocator.free(id_md);  // FREE #1
        return result;
    } else |_| {}

    // Search in neuronas directory
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        const base_name = entry.name[0 .. entry.name.len - 3];
        if (std.mem.eql(u8, base_name, id)) {
            const result = try std.fs.path.join(allocator, &.{ neuronas_dir, entry.name });
            allocator.free(id_md);  // FREE #2 (executed)
            return result;
        }
    }

    allocator.free(id_md);  // FREE #3 (executed when not found)
    return error.NeuronaNotFound;  // Function returns error, triggering errdefer
}
```

### Why This Causes Segfault

1. **Error Path**: When a neurona is not found, the function returns `error.NeuronaNotFound`
2. **errdefer Triggered**: The `errdefer allocator.free(id_md)` on line 900 is executed
3. **Double Free**: The function already called `allocator.free(id_md)` on the final error return path (line 931), causing double-free
4. **Memory Corruption**: Double-free leads to heap corruption, causing segfault

**Critical Issue**: The `errdefer` should only free `id_md` if an error occurs BEFORE the manual free on line 931, but currently both execute.

---

## Testing Results

### Test Case 1: Non-existent Neurona
**Command**: `engram show man`
**Expected**: Should display "Error: Neurona 'man' not found."
**Actual**: Segmentation fault
**Status**: ⚠️ FAIL

### Test Case 2: Other Invalid IDs
**Command**: `engram show invalid-test-123`
**Expected**: Should display error message
**Actual**: Segmentation fault
**Status**: ⚠️ FAIL

### Test Case 3: Valid Neuronas
**Commands**:
- `engram show feat.yaml-configuration-file-support`
- `engram show issue.create-a-script-for-doc-generation`
- `engram show req.content-test`

**Expected**: Should display correctly
**Actual**: Works correctly
**Status**: ✅ PASS

### Test Case 4: Pre-existing Bug Confirmation

**Test**: Stashed HashMap iterator fix, tested original code
**Result**: Segfault still occurs with original code
**Conclusion**: This is a pre-existing bug, NOT introduced by HashMap iterator fix

---

## Distinction from HashMap Iterator Bug

| Aspect | HashMap Iterator Bug | findNeuronaPath Bug |
|---------|---------------------|----------------------|
| **Location** | `parseContext` function (lines 94-113, 267-286) | `findNeuronaPath` function (lines 887-933) |
| **Root Cause** | HashMap `put()` during iteration causes rehash, invalidates iterator | Double-free of `id_md` allocation |
| **Trigger** | Any neurona with custom context that triggers rehash | Any non-existent neurona ID |
| **Fix Status** | ✅ FIXED (see SEGFAULT_FIX_PLAN.md) | ⚠️ OPEN (needs fix) |
| **Impact** | Segfault with valid neuronas using custom context | Segfault with invalid neurona IDs |
| **Error Type** | Undefined behavior from invalid iterator | Memory corruption from double-free |

---

## Proposed Fix

### Option 1: Remove errdefer (Recommended)

Remove the `errdefer` since the function manually frees `id_md` on all return paths:

```zig
pub fn findNeuronaPath(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) ![]const u8 {
    const id_md = try std.fmt.allocPrint(allocator, "{s}.md", .{id});
    // REMOVED: errdefer allocator.free(id_md);

    var dir = if (std.fs.path.isAbsolute(neuronas_dir))
        std.fs.openDirAbsolute(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        }
    else
        std.fs.cwd().openDir(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        };
    defer dir.close();

    // Check for .md file directly
    if (dir.access(id_md, .{})) |_| {
        const result = try std.fs.path.join(allocator, &.{ neuronas_dir, id_md });
        allocator.free(id_md);
        return result;
    } else |_| {}

    // Search in neuronas directory
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        const base_name = entry.name[0 .. entry.name.len - 3];
        if (std.mem.eql(u8, base_name, id)) {
            const result = try std.fs.path.join(allocator, &.{ neuronas_dir, entry.name });
            allocator.free(id_md);
            return result;
        }
    }

    allocator.free(id_md);
    return error.NeuronaNotFound;
}
```

**Pros**:
- Simple change
- All return paths explicitly handle cleanup
- No risk of double-free

**Cons**:
- Need to verify all error paths manually free `id_md`

### Option 2: Use defer Instead of errdefer

Change `errdefer` to `defer` to ensure cleanup happens on all return paths, then remove manual frees:

```zig
pub fn findNeuronaPath(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) ![]const u8 {
    const id_md = try std.fmt.allocPrint(allocator, "{s}.md", .{id});
    defer allocator.free(id_md);  // Changed from errdefer

    var dir = if (std.fs.path.isAbsolute(neuronas_dir))
        std.fs.openDirAbsolute(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        }
    else
        std.fs.cwd().openDir(neuronas_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return error.NeuronaNotFound;
            return err;
        };
    defer dir.close();

    // Check for .md file directly
    if (dir.access(id_md, .{})) |_| {
        return try std.fs.path.join(allocator, &.{ neuronas_dir, id_md });
        // id_md freed by defer
    } else |_| {}

    // Search in neuronas directory
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        const base_name = entry.name[0 .. entry.name.len - 3];
        if (std.mem.eql(u8, base_name, id)) {
            return try std.fs.path.join(allocator, &.{ neuronas_dir, entry.name });
            // id_md freed by defer
        }
    }

    return error.NeuronaNotFound;
    // id_md freed by defer
}
```

**Pros**:
- Guaranteed cleanup on all paths
- Simpler code (no manual frees)
- Follows Zig best practices

**Cons**:
- None significant

---

## Risk Assessment

### High Risk
- Affects user experience when neurona not found
- Segfault instead of helpful error message
- Common scenario (user types wrong ID)

### Low Risk (for fix)
- Localized to one function
- Simple fix (one line change)
- Well-understood memory management issue

---

## Implementation Steps

### Step 1: Apply Fix
Choose Option 1 or Option 2 and update `src/storage/filesystem.zig`

### Step 2: Test Fix
```bash
# Test non-existent neurona (should show error, not segfault)
engram show man

# Test other invalid IDs
engram show invalid-test-123

# Test valid neuronas still work
engram show feat.yaml-configuration-file-support
engram show issue.create-a-script-for-doc-generation
```

### Step 3: Install and Verify
```bash
just install
engram show man  # Should show error message
```

### Step 4: Update SEGFAULT_INVESTIGATION.md
Mark the HashMap iterator bug as FIXED and reference this document for the remaining issue.

---

## Testing Checklist

After fix implementation, verify:

- [ ] `engram show man` displays error message instead of segfault
- [ ] `engram show <invalid-id>` displays error message
- [ ] `engram show config` works correctly (opens editor)
- [ ] Valid neuronas still display correctly
- [ ] No memory leaks (test with GPA)
- [ ] Build passes with `zig build`
- [ ] Production installation works with `just install`

---

## References

- AGENTS.md - Zig coding standards
- memory-leak-investigation.md - Memory management patterns
- SEGFAULT_FIX_PLAN.md - HashMap iterator bug fix
- src/storage/filesystem.zig:887-933 - findNeuronaPath function
- src/utils/file_ops.zig:28-46 - readNeuronaWithBody function
- Zig defer and errdefer documentation

---

## Fix Applied (2026-02-14)

**Fix Applied**: Changed `errdefer allocator.free(id_md)` to `defer allocator.free(id_md)` and removed all manual frees.

**Files Changed**:
- `src/storage/filesystem.zig:900` - Changed errdefer to defer
- `src/storage/filesystem.zig:917, 936, 941` - Removed manual frees

**Testing Results**:
- ✅ `engram show man` - Displays error message (no segfault)
- ✅ `engram show invalid-test-123` - Displays error message
- ✅ `engram show feat.yaml-configuration-file-support` - Works correctly
- ✅ Build passes: `zig build`
- ✅ Production install works: `just install`

**Status**: FIXED - Double-free issue resolved by using defer instead of errdefer
