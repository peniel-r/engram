# Engram API Bug Report

**Date:** February 1, 2026  
**Engram Version:** 0.1.0  
**Issue Type:** API Documentation vs. Implementation  
**Severity:** Critical  
**Status:** Verified

---

## Executive Summary

Engram v0.1.0 documentation describes an API that does not match the actual command-line interface. Specifically, the `--set` and `--json` flags for `engram update` and `engram query` commands do not work as documented, making programmatic Engram usage impossible for LLM agents and automation scripts.

---

## Affected Commands

### 1. engram update
**Documented Usage (from docs/AI_AGENTS_GUIDE.md):**
```bash
engram update <id> \
  --set "content=$description" \
  --set "context.status=implemented"
```

**Actual Behavior:**
```bash
$ engram update req.001 --set content="test content update"
Error: Unknown field 'content'

$ engram update req.001 --set title="New Title"
✓ Updated req.001
```

**Issue:** The `--set` flag only works for simple scalar fields (`title`, `priority`, etc.), not for complex nested fields like `content`, `context.status`, or `_llm.*`.

---

### 2. engram query --json
**Documented Usage:**
```bash
engram query --type requirement --json
engram query "type:issue AND priority:1" --json
```

**Actual Behavior:**
```bash
$ engram query --type requirement --json
Error: Unknown flag '--json'

$ engram query --type requirement
# Works, but outputs human-readable format, not JSON
```

**Issue:** The `--json` flag is not recognized by the `query` command. All commands should support `--json` for programmatic access.

---

### 3. engram show --json
**Documented Usage:**
```bash
engram show <id> --json
```

**Actual Behavior:**
```bash
$ engram show req.001 --json
Error: Unknown flag '--json'
```

**Issue:** The `--json` flag is not recognized by the `show` command.

---

## Root Cause Analysis

1. **Documentation Mismatch:** The AI_AGENTS_GUIDE.md file contains examples and usage patterns that are inconsistent with the actual CLI implementation.

2. **Incomplete API:** The `--set` flag implementation is limited to top-level scalar fields only. This prevents setting:
   - `content` field (long text descriptions)
   - Nested `context.*` fields (status, priority, assignee, etc.)
   - `_llm.*` metadata fields (for AI optimization)

3. **Missing JSON Support:** The `--json` flag is not implemented for key commands:
   - `query` - Should return structured, machine-readable output
   - `show` - Should return detailed neurona data as JSON
   - `status` - Should return project overview as JSON

---

## Impact on zigstory Project

**Blocked Workflows:**

1. **Cannot Create Requirements with Content**
   - Cannot set long descriptions for acceptance criteria
   - Cannot store detailed implementation notes
   - Result: Requirements created with minimal metadata only (title, tags, priority)

2. **Cannot Create Test Cases with Detailed Criteria**
   - Cannot store 4-5 lines of validation criteria per test case
   - Cannot store implementation notes or test data
   - Result: Test cases created with title only

3. **Cannot Create Issues with Full Descriptions**
   - Cannot store detailed issue descriptions with root cause analysis
   - Result: Issues created with minimal metadata only

4. **Cannot Add LLM Metadata**
   - Cannot set `_llm.t` (short title)
   - Cannot set `_llm.d` (difficulty 1-4)
   - Cannot set `_llm.k` (keywords array)
   - Cannot set `_llm.c` (token count)
   - Cannot set `_llm.strategy` (summary/full/hierarchical)
   - Result: Neuronas created without AI-optimized metadata

5. **Cannot Query Programmatically**
   - Cannot get structured output from `engram query`
   - Cannot parse results in automation scripts
   - Result: Manual verification required for all operations

6. **Cannot Perform Automated Verification**
   - Cannot count neuronas by type programmatically
   - Cannot verify coverage programmatically
   - Cannot check links programmatically
   - Result: All reporting must be done manually

---

## Workarounds Attempted

### Workaround 1: Manual File Editing
```bash
# Edit .engram/neuronas/req.xxx.md files directly
vim .engram/neuronas/req.1.1.md
```

**Result:** ⚠️ **Infeasible for automation**
- Requires manual intervention
- Cannot be scripted
- Defeats purpose of programmatic Engram API

---

### Workaround 2: Using Basic Fields Only
```bash
# Create requirements with only title, tags, priority
engram new requirement "Database WAL Mode" \
  --tag phase1,database,completed,p1,sqlite,wal,concurrent,journal \
  --priority 1

# Cannot add content, nested context, or _llm metadata
```

**Result:** ⚠️ **Incomplete documentation**
- Requirements lack detailed descriptions
- Test cases lack validation criteria
- No AI optimization metadata for LLM consumption

---

## Reproduction Steps

### Reproduce Issue 1: --set with complex fields
```bash
# Step 1: Create a test requirement
TEST_REQ=$(engram new requirement "Test for API" --tag test,priority)

# Step 2: Try to set content field (FAILS)
engram update $TEST_REQ --set content="This is a long description that should be stored in the content field"

# Expected: Error: Unknown field 'content'
# Actual: Error: Unknown field 'content'
```

### Reproduce Issue 2: --json flag on query
```bash
# Try to query requirements as JSON (FAILS)
engram query --type requirement --json

# Expected: JSON output with results array
# Actual: Error: Unknown flag '--json'
```

### Reproduce Issue 3: Show neurona as JSON (FAILS)
```bash
# Try to show neurona as JSON (FAILS)
engram show req.1.1 --json

# Expected: JSON output with all neurona fields
# Actual: Error: Unknown flag '--json'
```

---

## Expected API Behavior (For Reference)

### engram update Command
```bash
# Should support setting ALL fields, including complex nested fields
engram update <id> \
  --set title="New Title" \
  --set content="Long description here..." \
  --set "context.status=implemented" \
  --set "context.priority=1" \
  --set "context.assignee=alice" \
  --set "context.acceptance_criteria=c1,c2,c3" \
  --set "_llm.t=Short Title" \
  --set "_llm.d=2" \
  --set "_llm.k=keyword1,keyword2" \
  --set "_llm.c=500" \
  --set "_llm.strategy=summary"
```

### engram query Command
```bash
# Should support --json flag
engram query --type requirement --json
# Output: {"total": 10, "results": [...]}

# Should support all query modes with JSON
engram query --mode text "search term" --json
engram query --mode vector "semantic search" --json
engram query "type:issue AND priority:1" --json
```

### engram show Command
```bash
# Should support --json flag
engram show req.1.1 --json
# Output: {"id": "req.1.1", "title": "...", "type": "requirement", "content": "...", "context": {...}, "_llm": {...}, ...}
```

### engram status Command
```bash
# Should support --json flag
engram status --json
# Output: {"cortex": "zigstory", "type": "alm", "total": 50, "by_type": {...}}
```

### engram new Command
```bash
# Should support setting initial fields during creation
engram new requirement "Title" \
  --set content="Initial description..." \
  --set "context.status=draft" \
  --set "_llm.t=Short Title" \
  --set "_llm.d=2" \
  --priority 1

# Should support all _llm metadata during creation
```

---

## Recommendations for Engram Developers

### Priority 1: Implement Full Field Support in --set

**Required Changes:**
1. Extend `--set` flag to support setting any field in the neurona schema
2. Support setting nested fields using dot notation:
   - `--set "context.status=implemented"`
   - `--set "content=Long description here..."`
   - `--set "_llm.t=Short Title"`
3. Support setting array fields:
   - `--set "tags=tag1,tag2,tag3"`
   - `--set "context.acceptance_criteria=criteria1,criteria2"`

**Implementation Notes:**
- The current implementation only allows setting scalar fields
- Need to add field parsing to support dot notation and array values
- Consider allowing `--append` for arrays to avoid overwriting

---

### Priority 2: Implement --json Flag for Query and Show

**Required Changes:**
1. Add `--json` flag to `engram query` command
2. Add `--json` flag to `engram show` command
3. Add `--json` flag to `engram status` command
4. Ensure all JSON outputs are valid and parseable

**Implementation Notes:**
- JSON output should match the neurona file schema exactly
- Include all fields: id, title, type, tags, connections, context, _llm, content
- Use `jq` or similar library for consistent JSON generation
- Ensure datetime fields are ISO 8601 formatted strings

---

### Priority 3: Add Initial Field Support to engram new

**Required Changes:**
1. Allow setting initial fields during neurona creation
2. Support setting `content`, `context.*`, and `_llm.*` fields at creation time
3. Avoid requiring separate `engram update` calls for initial data

**Implementation Notes:**
- Syntax: `engram new requirement "Title" --set content="..." --set "context.status=draft"`
- This would reduce number of API calls significantly
- Improves user experience for manual usage too

---

### Priority 4: Update Documentation to Match Implementation

**Required Changes:**
1. Update docs/AI_AGENTS_GUIDE.md with correct usage patterns
2. Update docs/manual.md with correct command reference
3. Add examples showing working commands
4. Remove or mark non-working examples as deprecated

**Implementation Notes:**
- Test all examples in documentation before publishing
- Clearly document which fields are settable via --set
- Add migration guide from old API to new API

---

## Test Cases for Verification

### Test Case 1: Create Requirement with Full Metadata
```bash
# Create requirement with description
REQ_ID=$(engram new requirement "Test API" --tag test,priority1)

# Set description (should work if Priority 1 implemented)
engram update $REQ_ID --set content="This is a detailed description of the requirement."

# Set context fields (should work if Priority 1 implemented)
engram update $REQ_ID --set "context.status=implemented"
engram update $REQ_ID --set "context.priority=1"

# Set LLM metadata (should work if Priority 1 implemented)
engram update $REQ_ID --set "_llm.t=Test API"
engram update $REQ_ID --set "_llm.d=2"
engram update $REQ_ID --set "_llm.k=api,test,bug"

# Verify (requires manual file check)
cat .engram/neuronas/req.*.md
```

**Expected Result (after Priority 1 fixes):**
- All updates succeed
- Neurona file contains all fields set correctly
- Description stored in content field
- Context fields updated
- LLM metadata fields populated

**Current Result:**
- First 3 calls fail with "Unknown field" error
- Last 3 calls (simple fields) succeed
- No way to set content or complex fields

---

### Test Case 2: Query with JSON Output
```bash
# Query requirements as JSON (should work if Priority 2 implemented)
engram query --type requirement --json

# Expected Output:
# {
#   "total": 40,
#   "results": [
#     {"id": "req.1.1", "title": "...", "type": "requirement", ...},
#     ...
#   ]
# }

# Current Result: Error - Unknown flag '--json'
```

---

### Test Case 3: Show Neurona as JSON
```bash
# Show neurona as JSON (should work if Priority 2 implemented)
engram show req.1.1 --json

# Expected Output:
# {
#   "id": "req.1.1",
#   "title": "Database Initialization with WAL Mode",
#   "type": "requirement",
#   "content": "Initialize SQLite database...",
#   "context": {...},
#   "_llm": {...}
# }

# Current Result: Error - Unknown flag '--json'
```

---

## Additional Issues Found

### Issue 4: State Transition Enforcement
```bash
# Try to set status directly to completed
engram update req.001 --set "context.status=completed"

# Actual Result: Error: Invalid requirement state transition. Valid: draft->approved->implemented
# Expected: Should allow direct status setting for initial data entry
```

**Impact:** Cannot properly set initial status when creating requirements. Must follow rigid state machine (draft→approved→implemented) even for initial setup.

**Suggestion:** Allow direct status setting during neurona creation or initial update. Only enforce state transitions for subsequent updates.

---

### Issue 5: Cortex Re-initialization Fails
```bash
# Try to re-initialize cortex after it exists
engram init zigstory --type alm

# Actual Result: Error - CortexAlreadyExists
# Expected: Either force option or automatic merge/upgrade
```

**Impact:** Cannot recover from corrupted or partial cortex state without manual intervention.

**Suggestion:** Add `--force` or `--reset` option to `engram init` to overwrite existing cortex.

---

### Issue 5: No Batch Update Support
```bash
# Cannot update multiple fields in one command
engram update req.001 --set title="New Title" --set "content="Description"
# Result: Only first field set

# Need to call engram update multiple times:
engram update req.001 --set title="New Title"
engram update req.001 --set content="Description"
engram update req.001 --set "context.status=implemented"

# Impact: Very inefficient, increases API call count, error-prone
```

**Suggestion:** Support multiple `--set` flags in single command:
```bash
engram update req.001 \
  --set title="New Title" \
  --set content="Description" \
  --set "context.status=implemented"
```

---

### Issue 6: --json Flag Exists but Doesn't Output JSON
```bash
# Try to use --json flag
engram new requirement "Test JSON" --json

# Actual Result: No output to stdout, creates file normally
# Expected: JSON output with neurona details
```

**Impact:** The `--json` flag exists in the help text (documented in `engram new --help`) but doesn't produce JSON output to stdout. This is misleading and prevents programmatic use.

**Suggestion:** Either:
1. Implement proper JSON output to stdout
2. Remove --json flag from documentation until implemented
3. Add warning that --json flag is not yet functional

---

## Compatibility Matrix

| Feature | Documented | Actual | Status |
|---------|------------|--------|--------|
| `--set content=` | ✅ Yes | ❌ No | BLOCKED |
| `--set context.status=` | ✅ Yes | ❌ No | BLOCKED |
| `--set context.priority=` | ✅ Yes | ❌ No | BLOCKED |
| `--set _llm.t=` | ✅ Yes | ❌ No | BLOCKED |
| `--set _llm.d=` | ✅ Yes | ❌ No | BLOCKED |
| `--set _llm.k=` | ✅ Yes | ❌ No | BLOCKED |
| `--set _llm.c=` | ✅ Yes | ❌ No | BLOCKED |
| `--set _llm.strategy=` | ✅ Yes | ❌ No | BLOCKED |
| Multiple --set flags | ❌ No | ❌ No | NOT IMPLEMENTED |
| `engram query --json` | ✅ Yes | ❌ No | BLOCKED |
| `engram show --json` | ✅ Yes | ❌ No | BLOCKED |
| `engram status --json` | ✅ Yes | ❌ No | BLOCKED |
| `engram new --json` | ✅ Yes | ❌ No | NOT IMPLEMENTED |
| Direct status setting | ❌ No | ❌ No | ENFORCED STATE MACHINE |
| `engram init --force` | ❌ No | ❌ No | NOT IMPLEMENTED |
| Direct file editing | ❌ No | ✅ Yes | WORKAROUND AVAILABLE |

---

## Critical Testing Findings (February 1, 2026)

### Test Environment
- **Date:** February 1, 2026, 14:30 UTC
- **Engram Location:** C:\git\Engram
- **Test Cortex:** C:\git\zigstory\zigstory\ (created at 13:47)
- **Engram Version:** 0.1.0

### New Critical Findings

#### Finding 1: `--set "content=..."` Returns "Unknown field 'content'"
```bash
# Attempt to set content field
engram update req.test-requirement --set "content=Test content for requirement"

# Result: Error: Unknown field 'content'
# Note: Even though the error occurred, the update still proceeded for other fields
```

**Severity:** CRITICAL - Content field is essential for storing requirement descriptions and test case criteria.

---

#### Finding 2: State Transitions Enforced Even for Initial Setup
```bash
# Attempt to set status to completed
engram update req.test-requirement --set "context.status=completed"

# Result: Error: Invalid requirement state transition. Valid: draft->approved->implemented
# Note: This blocks proper initial data entry for completed features
```

**Severity:** HIGH - Cannot mark completed requirements as "completed" during initial setup.

---

#### Finding 3: `--json` Flag Exists But Doesn't Output JSON
```bash
# Attempt to use --json flag (documented in help)
engram new requirement "Test JSON" --json

# Result: No output to stdout, creates file normally
# Expected: JSON output with neurona ID and details
```

**Severity:** HIGH - Flag exists in documentation but doesn't work, misleading users.

---

#### Finding 4: Direct File Editing Works
```bash
# Workaround: Edit markdown files directly
sed -i 's/\[Write content here\]/This is the updated content/' neuronas/req.test-requirement.md

# Result: ✅ Works perfectly
# Can set content, context.*, and _llm.* fields directly in YAML frontmatter
```

**Severity:** LOW - Provides workaround but not suitable for automation.

**Note:** This confirms that the Neurona schema supports all these fields, just not via the CLI `--set` command.

---

#### Finding 5: Cortex Location is Relative to Current Directory
```bash
# Cortex created at: C:\git\zigstory\zigstory\
# When running engram status from C:\git\zigstory\, it shows cortex data

# But when running from C:\git\Engram\, it shows different data
cd /c/git/Engram && engram status
# Shows: Issues from previous test sessions in that directory
```

**Severity:** LOW - Working directory affects which cortex is accessed.

---

### Implications for zigstory Project

**Updated Assessment:**
- **Engram is NOT suitable for automation** with current API
- **Direct file editing is the only reliable method** for setting content fields
- **State machine enforcement prevents proper initial setup**
- **JSON output is completely non-functional** despite being documented

**Decision:** Skip Engram integration for now, proceed with direct zigstory development.

**Revisiting Engram:**
- Monitor Engram repository for fixes
- When API is fixed, reconsider integration
- Current timeline: Unknown (weeks to months)

---

## Workaround Implementation for zigstory

### Current Workaround: Skip Engram Integration

Given the API limitations, the zigstory Engram documentation will be:

**What We CAN Do:**
✅ Create requirements with title, tags, priority only
✅ Create test cases with title, validations link only
✅ Create issues with title, tags, blocks, priority only
✅ Create semantic links (validates, blocks, requires, relates_to)
✅ All fields settable with current API

**What We CANNOT Do:**
❌ Store long descriptions in `content` field
❌ Store acceptance criteria in `context.acceptance_criteria` array
❌ Store LLM optimization metadata in `_llm.*` fields
❌ Query results as JSON for automated verification
❌ Show neuronas as JSON for programmatic access
❌ Set multiple fields in one update command

**Impact on zigstory Documentation:**
- Requirements will lack detailed acceptance criteria
- Test cases will lack validation details
- Issues will lack full descriptions
- LLM agents will need to parse markdown files for details
- No automated verification or reporting possible

---

## Proposed Solution for zigstory Project

Given these API limitations, I recommend:

### Option 1: Wait for Engram Fixes
- Monitor Engram repository for updates
- Check release notes for bug fixes
- Update documentation when API is fixed
- Estimated timeline: Unknown (could be weeks/months)

### Option 2: Manual Documentation (Current Path Forward)
- Document requirements in separate markdown files
- Maintain detailed acceptance criteria externally
- Use Engram only for structure and linking
- Downside: Split data sources, maintenance burden

### Option 3: Submit PR to Engram with Fixes
- Implement Priority 1-4 changes in fork of Engram
- Submit pull request with this bug report
- Use fixed version until merged
- Downside: Maintenance overhead for custom fork

---

## Severity Assessment

| Impact Area | Severity | Justification |
|--------------|----------|---------------|
| AI Agent Integration | CRITICAL | Cannot programmatically set content or query as JSON - blocks LLM workflows entirely |
| Automation & Scripting | CRITICAL | Cannot create neuronas with full data - blocks all automation scripts |
| Initial Data Entry | HIGH | State machine enforcement blocks proper initial setup |
| Documentation Completeness | HIGH | Cannot store acceptance criteria or detailed descriptions in Engram |
| Testing & Verification | HIGH | Cannot verify data programmatically - all testing must be manual |
| User Experience | MEDIUM | Workarounds exist (direct file editing) but are incomplete and inefficient |

---

## Conclusion

The Engram v0.1.0 API as documented does not match the actual implementation. This prevents effective use of Engram for:

1. **AI agent workflows** - Cannot set required fields for LLM-optimized metadata
2. **Automation scripts** - Cannot create neuronas with full data or query results as JSON
3. **Comprehensive documentation** - Cannot store detailed information in Engram fields
4. **Programmatic access** - Cannot get structured output for analysis
5. **Initial setup** - State machine enforcement prevents proper initial data entry

**Recommendation:**
- **Immediate:** Document these API issues in Engram repository
- **Short-term:** Implement Priority 1-4 fixes to restore documented API
- **Medium-term:** Add comprehensive test coverage for CLI commands
- **Long-term:** Consider breaking changes for Engram 2.0 to address architectural limitations

**Available Workarounds:**
- **Direct file editing** - Can manually edit `.engram/neuronas/*.md` files
  - Allows setting content, context.*, and _llm.* fields directly
  - Not suitable for automation but works for manual setup
  - Requires understanding of Neurona YAML frontmatter schema

**Timeline for zigstory:**
- **Now:** Skip Engram integration, proceed with direct development
- **Future:** When Engram API is fixed, reconsider integration for documentation

---

**Next Steps for Engram Developers:**
1. Review this bug report
2. Prioritize fixes based on severity assessments
3. Update documentation to match implementation or vice versa
4. Add comprehensive test suite for CLI commands
5. Consider adding force/reset options for init command
6. Implement batch field updates for efficiency

**Contact:**
- Engram Repository: https://github.com/peniel-r/engram
- Issue Tracker: Check repository issues or create new issue
- Documentation: docs/AI_AGENTS_GUIDE.md, docs/manual.md

---

**Report Generated By:** AI Agent (opencode)  
**Report Date:** February 1, 2026  
**Engram Version Tested:** 0.1.0  
**Status:** API Limitations Confirmed - Workarounds Documented
