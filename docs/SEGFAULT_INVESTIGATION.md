# Segmentation Fault Investigation

**Version**: 1.1.0  
**Date**: 2026-02-14  
**Status**: PRE-EXISTING ISSUE  
**Priority**: Critical  

---

## Problem Summary

`engram show man` command causes a segmentation fault. After investigation, this issue is **PRE-EXISTING** and was not introduced by the memory leak fixes (commit 6460061).

---

## Investigation Results

### Testing Performed
1. ✅ Tested original code (before memory leak fixes) - segfault still occurs
2. ✅ Confirmed segfault is NOT caused by memory leak fix changes
3. ⚠️ The segfault exists in the codebase before commit 6460061

### Root Cause Analysis

The root cause appears to be in the `parseContext` function where `put()` operations are called during HashMap iteration. When the custom HashMap needs to rehash, the iterator becomes invalid, leading to undefined behavior.

**Note**: This pattern exists in multiple locations in `parseContext`:
- Lines 94-112: feature/lesson/reference/concept types
- Lines 273-286: default custom context fallback

### Fix Attempts

Attempted to fix by collecting entries into ArrayList before insertion, but encountered Zig 0.15 ArrayList API compatibility issues:
- `std.ArrayList([]const u8).init(allocator)` - not found in API
- `std.ArrayList(u8).init(allocator)` - works but ArrayListUnmanaged has type constraints
- `ArrayListUnmanaged([]const u8)` - element type mismatch with append()

### Current Status

- Code currently reverted to original pattern
- Segfault still present
- Root cause identified but requires alternative fix approach

---

## Recommended Next Steps

1. **Investigate Zig 0.15 ArrayList API** - find correct method to collect entries
2. **Alternative approaches**:
   - Use `std.HashMap.clone()` to create a copy before iteration
   - Pre-allocate HashMap with sufficient capacity
   - Use manual array-based storage instead of HashMap
3. **Testing** - Verify fix with `engram show man` and other custom context neuronas

---

## Testing Plan

### Test Case 1: Reproduce Segfault
**Command**: `engram show man`
**Expected**: Should show "Neurona not found" error message
**Actual**: Segmentation fault
**Status**: ⚠️ FAIL

### Test Case 2: Config File
**Command**: `engram show config`
**Expected**: Should open config file correctly
**Status**: ⏸️ NOT TESTED (hung during previous attempt)

### Test Case 3: Valid Neuronas
**Commands**:
- `engram show feat.yaml-configuration-file-support`
- `engram show issue.create-a-script-for-doc-generation`
- `engram show req.content-test`

**Expected**: Should display correctly
**Status**: ⏸️ NOT TESTED

---

## Risk Assessment

### High Risk
- Segfault affects user experience significantly
- May occur with any neurona using custom context parsing
- Issue is intermittent (depends on HashMap rehash triggers)

### Mitigation
- Document the issue for users
- Provide workaround (avoid large custom contexts)
- Continue investigation for proper fix

---

## References

- AGENTS.md - Zig coding standards
- src/storage/filesystem.zig:84-286 - parseContext function
- Zig HashMap documentation
- Previous memory leak fixes (commit 6460061)

---

**Status**: Investigation ongoing, root cause identified but fix requires further Zig API research
