# Segmentation Fault Investigation

**Version**: 1.2.0
**Date**: 2026-02-14
**Status**: PARTIALLY RESOLVED
**Priority**: Critical

---

## Problem Summary

`engram show man` command causes a segmentation fault. This investigation has identified **TWO SEPARATE BUGS**:

1. ✅ **HashMap Iterator Invalidation** - FIXED (see SEGFAULT_FIX_PLAN.md)
2. ⚠️ **findNeuronaPath Double-Free** - Open (see findNeuronaPath_bug.md)

Both bugs are PRE-EXISTING and were not introduced by the memory leak fixes (commit 6460061).

---

## Investigation Results

### Testing Performed
1. ✅ Tested original code (before memory leak fixes) - segfault still occurs
2. ✅ Confirmed segfault is NOT caused by memory leak fix changes
3. ✅ Identified TWO separate bugs causing segfaults
4. ⚠️ The segfault exists in the codebase before commit 6460061

### Root Cause Analysis - Bug #1: HashMap Iterator Invalidation (RESOLVED ✅)

**Location**: `parseContext` function where `put()` operations are called during HashMap iteration.

**Root Cause**: When the custom HashMap needs to rehash during iteration, the iterator becomes invalid, leading to undefined behavior.

**Affected Code**:
- Lines 94-112: feature/lesson/reference/concept types
- Lines 273-286: default custom context fallback

**Fix Applied**: See [SEGFAULT_FIX_PLAN.md](SEGFAULT_FIX_PLAN.md)
- Collect all entries into ArrayList before HashMap insertion
- Transfer ownership after iteration completes
- Prevents iterator invalidation

**Status**: ✅ FIXED and tested in production

### Root Cause Analysis - Bug #2: findNeuronaPath Double-Free (OPEN ⚠️)

**Location**: `findNeuronaPath` function around line 900.

**Root Cause**: Double-free of `id_md` allocation due to both `errdefer` and manual free being executed.

**Affected Commands**: All commands attempting to read non-existent neuronas.

**Documentation**: See [findNeuronaPath_bug.md](findNeuronaPath_bug.md)

**Status**: ⚠️ OPEN - Requires fix

---

## Recommended Next Steps

### Completed ✅
1. ✅ **HashMap Iterator Bug** - Fixed in SEGFAULT_FIX_PLAN.md
   - Implemented ArrayList collection pattern
   - Ownership tracking prevents double-free
   - Tested in production with multiple neurona types

### Open ⚠️
2. ⚠️ **findNeuronaPath Double-Free** - Documented in findNeuronaPath_bug.md
   - Requires fix to memory management in `findNeuronaPath`
   - Simple fix: Change `errdefer` to `defer` or remove errdefer entirely
   - See findNeuronaPath_bug.md for detailed implementation steps

### Testing
3. **Production Validation** - Apply findNeuronaPath fix and test:
   - `engram show man` should show error message (not segfault)
   - `engram show <invalid-id>` should show error message
   - Valid neuronas must continue to work correctly

---

## Testing Plan

### Test Case 1: HashMap Iterator Bug (FIXED ✅)
**Command**: `engram show feat.yaml-configuration-file-support`
**Expected**: Should display correctly without segfault
**Actual**: Works correctly
**Status**: ✅ PASS (production tested)

### Test Case 2: findNeuronaPath Bug (OPEN ⚠️)
**Command**: `engram show man`
**Expected**: Should show "Neurona not found" error message
**Actual**: Segmentation fault (due to double-free in findNeuronaPath)
**Status**: ⚠️ FAIL (documented in findNeuronaPath_bug.md)

### Test Case 3: Valid Neuronas (PASSING ✅)
**Commands**:
- `engram show feat.yaml-configuration-file-support`
- `engram show issue.create-a-script-for-doc-generation`
- `engram show req.content-test`

**Expected**: Should display correctly
**Actual**: All work correctly
**Status**: ✅ PASS

### Test Case 4: Config File
**Command**: `engram show config`
**Expected**: Should open config file in editor
**Actual**: Opens correctly (expected behavior)
**Status**: ✅ PASS

---

## Risk Assessment

### Resolved Risks ✅
- **HashMap Iterator Invalidation**: FIXED
  - No longer affects user experience
  - All neurona types with custom context work correctly
  - Tested in production with multiple test cases

### Remaining Risks ⚠️
- **findNeuronaPath Double-Free**: HIGH RISK
  - Affects user experience when neurona not found
  - Segfault instead of helpful error message
  - Common scenario (user types wrong ID)
  - **Mitigation**: Documented in findNeuronaPath_bug.md with proposed fix

---

## References

- [SEGFAULT_FIX_PLAN.md](SEGFAULT_FIX_PLAN.md) - HashMap iterator bug fix (implemented)
- [findNeuronaPath_bug.md](findNeuronaPath_bug.md) - findNeuronaPath double-free bug (open)
- AGENTS.md - Zig coding standards
- memory-leak-investigation.md - Memory management patterns
- src/storage/filesystem.zig:84-286 - parseContext function (HashMap bug)
- src/storage/filesystem.zig:887-933 - findNeuronaPath function (double-free bug)
- Zig HashMap documentation
- Previous memory leak fixes (commit 6460061)

---

**Status**: PARTIALLY RESOLVED
- ✅ HashMap iterator bug: FIXED (see SEGFAULT_FIX_PLAN.md)
- ⚠️ findNeuronaPath double-free bug: DOCUMENTED (see findNeuronaPath_bug.md)
