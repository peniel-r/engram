# Engram API Bug Fix Plan

**Date:** February 1, 2026  
**Engram Version:** 0.1.0  
**Issue Type:** API Documentation vs. Implementation  
**Severity:** Critical  
**Status:** Implementation Plan

---

## Executive Summary

The bug report documents 6 major categories of issues blocking programmatic Engram usage:

1. **`--set content=` not working** - Critical blocker for storing descriptions
2. **`--set context.*` not working** - Can't set nested context fields  
3. **`--set _llm.*` not working** - Can't set AI optimization metadata
4. **`--json` flags not working** - Query/Show/Status don't output complete JSON
5. **State transition enforcement** - Blocks initial data entry
6. **Multiple `--set` flags** - Not working (but code shows it should)

These issues prevent AI agents and automation scripts from using Engram programmatically, blocking the zigstory project's documentation workflow.

---

## Root Cause Analysis

| Issue | Root Cause | Affected Files |
|-------|-------------|----------------|
| `--set content=` fails | `content` field doesn't exist in `Neurona` struct - it's stored in markdown body (after `---\n`), not YAML frontmatter. `update.zig` only handles YAML fields. | `src/core/neurona.zig`, `src/cli/update.zig` |
| `--set context.*` fails | `applyContextUpdate()` only handles specific hardcoded fields per context type. Missing fields like `acceptance_criteria`. | `src/cli/update.zig` lines 152-319 |
| `--set _llm.*` fails | Uses flattened `_llm_t`, `_llm_d` format in YAML, but `update.zig` doesn't handle these special fields. | `src/storage/filesystem.zig` lines 404-454 |
| `--json` not working | JSON output functions exist (`outputJson`) but only print partial data. In `query.zig` line 40, `json_output` flag exists but `outputJson` at line 1019 only prints `id`, `title`, `type`, `tags` - missing body, context, connections. | `src/cli/query.zig`, `src/cli/show.zig`, `src/cli/status.zig` |
| State transitions | `state_machine.zig` enforces rigid state machine even for initial creation | `src/core/state_machine.zig` |
| Multiple `--set` | **Investigation needed** - Code shows it should work, but bug report says it doesn't | `src/main.zig`, `src/cli/update.zig` |

---

## Implementation Plan

### Priority 1: Fix `--set content=` Support (CRITICAL)

**Problem:** The `content` field is not part of the `Neurona` struct. It's stored in the markdown body (after `---`), not YAML frontmatter. The current `--set` implementation only updates YAML frontmatter.

**Solution:** Add support for updating markdown body content via `--set content=...`.

**Files to Modify:**
- `src/cli/update.zig` - Add handling for `content` field
- `src/storage/filesystem.zig` - Add `updateBody()` function

**Implementation Steps:**

#### Step 1.1: Add `updateBody()` function to `src/storage/filesystem.zig`

Add this function around line 672 (after `generateMarkdown`):

```zig
/// Update only the body content of a Neurona file (preserves frontmatter)
pub fn updateBody(allocator: Allocator, filepath: []const u8, new_body: []const u8) !void {
    // Read existing file
    const content = try std.fs.cwd().readFileAlloc(allocator, filepath, 10 * 1024 * 1024);
    defer allocator.free(content);
    
    // Extract frontmatter
    const fm = try frontmatter.parse(allocator, content);
    defer fm.deinit(allocator);
    
    // Generate new file with old frontmatter + new body
    const new_content = try generateMarkdown(allocator, fm.content, new_body);
    defer allocator.free(new_content);
    
    // Write back to file
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();
    try file.writeAll(new_content);
}
```

#### Step 1.2: Add `content` handling to `applyUpdate()` in `src/cli/update.zig`

Add this case around line 95 (before the `if (std.mem.eql(u8, field, "type"))` check):

```zig
if (std.mem.eql(u8, field, "content")) {
    // Update markdown body content (not frontmatter)
    const body_filepath = try findNeuronaPath(allocator, config.neuronas_dir, neurona.id);
    defer allocator.free(body_filepath);
    try updateBody(allocator, body_filepath, value);
    if (verbose) std.debug.print("  Set body content to: {s}...\n", .{value[0..@min(50, value.len)]});
    return true;
}
```

**Test:**
```bash
engram new requirement "Test" --no-interactive
REQ_ID=$(engram status --json | jq -r '.[0].id')
engram update $REQ_ID --set content="This is a long description that should work now"
cat neuronas/$REQ_ID.md
# Verify body contains new content
```

---

### Priority 2: Expand `--set context.*` Field Support (CRITICAL)

**Problem:** `applyContextUpdate()` only handles hardcoded fields. Missing many documented fields.

**Solution:** Add support for all documented context fields and add `_llm` field support.

**Files to Modify:**
- `src/cli/update.zig` - Expand `applyUpdate()` to support more fields

#### Step 2.1: Add `_llm.*` field handling in `applyUpdate()`

Add this section before the context handling (around line 89, after the `context.` check but before direct fields):

```zig
// Handle _llm metadata fields (flattened format)
if (std.mem.eql(u8, field, "_llm_t")) {
    try updateLLMMetadata(allocator, &neurona, "short_title", value, verbose);
    return true;
}
if (std.mem.eql(u8, field, "_llm_d")) {
    try updateLLMMetadata(allocator, &neurona, "density", value, verbose);
    return true;
}
if (std.mem.eql(u8, field, "_llm_k")) {
    try updateLLMMetadata(allocator, &neurona, "keywords", value, verbose);
    return true;
}
if (std.mem.eql(u8, field, "_llm_c")) {
    try updateLLMMetadata(allocator, &neurona, "token_count", value, verbose);
    return true;
}
if (std.mem.eql(u8, field, "_llm_strategy")) {
    try updateLLMMetadata(allocator, &neurona, "strategy", value, verbose);
    return true;
}
```

#### Step 2.2: Add `updateLLMMetadata()` helper function

Add this function after `applyContextUpdate()` (around line 319):

```zig
/// Update LLM metadata field
fn updateLLMMetadata(allocator: Allocator, neurona: *Neurona, field: []const u8, value: []const u8, verbose: bool) !bool {
    // Initialize metadata if not exists
    if (neurona.llm_metadata == null) {
        neurona.llm_metadata = LLMMetadata{
            .short_title = try allocator.dupe(u8, ""),
            .density = 2,
            .keywords = .{},
            .token_count = 0,
            .strategy = try allocator.dupe(u8, "summary"),
        };
    }
    
    const meta = &neurona.llm_metadata.?;
    
    if (std.mem.eql(u8, field, "short_title")) {
        allocator.free(meta.short_title);
        meta.short_title = try allocator.dupe(u8, value);
        if (verbose) std.debug.print("  Set _llm.short_title to: {s}\n", .{value});
    } else if (std.mem.eql(u8, field, "density")) {
        meta.density = std.fmt.parseInt(u8, value, 10) catch {
            std.debug.print("Error: Invalid density '{s}'\n", .{value});
            return false;
        };
        if (verbose) std.debug.print("  Set _llm.density to: {d}\n", .{meta.density});
    } else if (std.mem.eql(u8, field, "keywords")) {
        // Split comma-separated keywords
        var it = std.mem.splitScalar(u8, value, ',');
        meta.keywords.deinit(allocator);
        meta.keywords = .{};
        while (it.next()) |kw| {
            const trimmed = std.mem.trim(u8, kw, " ");
            if (trimmed.len > 0) {
                try meta.keywords.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
        if (verbose) std.debug.print("  Set _llm.keywords to: {d} items\n", .{meta.keywords.items.len});
    } else if (std.mem.eql(u8, field, "token_count")) {
        meta.token_count = std.fmt.parseInt(u32, value, 10) catch 0;
        if (verbose) std.debug.print("  Set _llm.token_count to: {d}\n", .{meta.token_count});
    } else if (std.mem.eql(u8, field, "strategy")) {
        allocator.free(meta.strategy);
        meta.strategy = try allocator.dupe(u8, value);
        if (verbose) std.debug.print("  Set _llm.strategy to: {s}\n", .{value});
    } else {
        return false;
    }
    
    return true;
}
```

#### Step 2.3: Add missing context fields to `applyContextUpdate()`

Add `acceptance_criteria` handling for requirement context (around line 258 in update.zig, after `effort_points`):

```zig
if (std.mem.eql(u8, context_field, "acceptance_criteria")) {
    // Store in custom context as comma-separated list
    const custom_ctx = switch (neurona.context) {
        .custom => |*c| c,
        else => {
            // Convert to custom context to add arbitrary fields
            var custom = std.StringHashMap([]const u8).init(allocator);
            errdefer {
                var it = custom.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                custom.deinit();
            }
            neurona.context = Context{ .custom = custom };
            return try allocator.dupe(u8, "acceptance_criteria");
        },
    };
    
    if (custom_ctx.get("acceptance_criteria")) |old| {
        allocator.free(old);
    }
    try custom_ctx.put(allocator, try allocator.dupe(u8, "acceptance_criteria"), try allocator.dupe(u8, value));
    if (verbose) std.debug.print("  Set context.acceptance_criteria to: {s}\n", .{value});
    return true;
}
```

Add `resolution_notes` handling for issue context (around line 252, after `closed`):

```zig
if (std.mem.eql(u8, context_field, "resolution_notes")) {
    if (ctx.resolution_notes) |old| allocator.free(old);
    ctx.resolution_notes = try allocator.dupe(u8, value);
    if (verbose) std.debug.print("  Set context.resolution_notes to: {s}\n", .{value});
    return true;
}
```

**Test:**
```bash
REQ_ID=$(engram new requirement "Test" --no-interactive --json | jq -r .id)

engram update $REQ_ID --set "_llm_t=Short"
# Expect: Success

engram update $REQ_ID --set "_llm_d=3"
# Expect: Success

engram update $REQ_ID --set "_llm_k=keyword1,keyword2"
# Expect: Success

engram update $REQ_ID --set "context.acceptance_criteria=criteria1,criteria2"
# Expect: Success
```

---

### Priority 3: Fix JSON Output Completeness (HIGH)

**Problem:** `outputJson` functions exist but only output partial data (missing body, context, connections, _llm).

**Solution:** Expand `outputJson` functions to output complete neurona data.

**Files to Modify:**
- `src/cli/query.zig` - `outputJson()` function (line 1019)
- `src/cli/show.zig` - `outputJson()` function (line 168)
- `src/cli/status.zig` - `outputJson()` function (line 339)

#### Step 3.1: Add JSON string escaping helper

Add this helper function to `src/cli/query.zig` before the `outputJson` function (around line 1018):

```zig
/// Print string as JSON-escaped value
fn printJsonString(s: []const u8) void {
    std.debug.print("\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => std.debug.print("\\\"", .{}),
            '\\' => std.debug.print("\\\\", .{}),
            '\n' => std.debug.print("\\n", .{}),
            '\r' => std.debug.print("\\r", .{}),
            '\t' => std.debug.print("\\t", .{}),
            else => std.debug.print("{c}", .{c}),
        }
    }
    std.debug.print("\"", .{});
}
```

#### Step 3.2: Rewrite `outputJson()` in `src/cli/query.zig`

Replace the existing function (lines 1019-1041) with:

```zig
/// JSON output for AI - complete neurona data
fn outputJson(allocator: Allocator, neuras: []const Neurona) !void {
    _ = allocator;
    std.debug.print("[", .{});
    for (neuras, 0..) |neurona, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{", .{});
        std.debug.print("\"id\":\"{s}\",", .{neurona.id});
        std.debug.print("\"title\":\"{s}\",", .{neurona.title});
        std.debug.print("\"type\":\"{s}\",", .{@tagName(neurona.type)});
        
        // Tags
        std.debug.print("\"tags\":[", .{});
        for (neurona.tags.items, 0..) |tag, ti| {
            if (ti > 0) std.debug.print(",", .{});
            printJsonString(tag);
        }
        std.debug.print("],");
        
        // Context
        std.debug.print("\"context\":{", .{});
        switch (neurona.context) {
            .requirement => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"verification_method\":\"{s}\",", .{ctx.verification_method});
                std.debug.print("\"priority\":{d}", .{ctx.priority});
                if (ctx.assignee) |a| std.debug.print(",\"assignee\":\"{s}\"", .{a});
            },
            .test_case => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"framework\":\"{s}\"", .{ctx.framework});
            },
            .issue => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"priority\":{d}", .{ctx.priority});
                if (ctx.assignee) |a| std.debug.print(",\"assignee\":\"{s}\"", .{a});
            },
            .artifact => |ctx| {
                std.debug.print("\"runtime\":\"{s}\",", .{ctx.runtime});
                std.debug.print("\"file_path\":\"{s}\"", .{ctx.file_path});
            },
            else => {},
        }
        std.debug.print("},");
        
        // LLM metadata
        if (neurona.llm_metadata) |*meta| {
            std.debug.print("\"_llm\":{", .{});
            std.debug.print("\"t\":\"{s}\",", .{meta.short_title});
            std.debug.print("\"d\":{d},", .{meta.density});
            std.debug.print("\"strategy\":\"{s}\"", .{meta.strategy});
            if (meta.keywords.items.len > 0) {
                std.debug.print(",\"k\":[", .{});
                for (meta.keywords.items, 0..) |kw, ki| {
                    if (ki > 0) std.debug.print(",", .{});
                    printJsonString(kw);
                }
                std.debug.print("]", .{});
                std.debug.print(",\"c\":{d}", .{meta.token_count});
            }
            std.debug.print("},");
        }
        
        // Connections count
        std.debug.print("\"connections\":{d}", .{neurona.connections.count()});
        std.debug.print("}", .{});
    }
    std.debug.print("]\n", .{});
}
```

#### Step 3.3: Rewrite `outputJson()` in `src/cli/show.zig`

Replace the existing function (lines 168-178) with:

```zig
/// JSON output for AI
fn outputJson(allocator: Allocator, neurona: *const Neurona, filepath: []const u8, body: []const u8) !void {
    _ = allocator;
    std.debug.print("{", .{});
    std.debug.print("\"id\":\"{s}\",", .{neurona.id});
    std.debug.print("\"title\":\"{s}\",", .{neurona.title});
    std.debug.print("\"type\":\"{s}\",", .{@tagName(neurona.type)});
    std.debug.print("\"filepath\":\"{s}\",", .{filepath});
    std.debug.print("\"language\":\"{s}\",", .{neurona.language});
    std.debug.print("\"updated\":\"{s}\",", .{neurona.updated});
    
    // Tags
    std.debug.print("\"tags\":[", .{});
    for (neurona.tags.items, 0..) |tag, i| {
        if (i > 0) std.debug.print(",", .{});
        printJsonString(tag);
    }
    std.debug.print("],");
    
    // Connections count
    std.debug.print("\"connections\":{d},", .{neurona.connections.count()});
    
    // Body content (escaped for JSON)
    std.debug.print("\"body\":", .{});
    printJsonString(body);
    std.debug.print(",");
    
    // Context
    std.debug.print("\"context\":{", .{});
    switch (neurona.context) {
        .requirement => |ctx| {
            std.debug.print("\"status\":\"{s}\",", .{ctx.status});
            std.debug.print("\"verification_method\":\"{s}\"", .{ctx.verification_method});
        },
        .test_case => |ctx| {
            std.debug.print("\"status\":\"{s}\",", .{ctx.status});
            std.debug.print("\"framework\":\"{s}\"", .{ctx.framework});
        },
        .issue => |ctx| {
            std.debug.print("\"status\":\"{s}\"", .{ctx.status});
        },
        .artifact => |ctx| {
            std.debug.print("\"runtime\":\"{s}\"", .{ctx.runtime});
        },
        else => {},
    }
    std.debug.print("},");
    
    // LLM metadata
    if (neurona.llm_metadata) |*meta| {
        std.debug.print("\"_llm\":{", .{});
        std.debug.print("\"t\":\"{s}\",", .{meta.short_title});
        std.debug.print("\"d\":{d}", .{meta.density});
        std.debug.print("}", .{});
    }
    
    std.debug.print("}\n", .{});
}

/// Print string as JSON-escaped value
fn printJsonString(s: []const u8) void {
    std.debug.print("\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => std.debug.print("\\\"", .{}),
            '\\' => std.debug.print("\\\\", .{}),
            '\n' => std.debug.print("\\n", .{}),
            '\r' => std.debug.print("\\r", .{}),
            '\t' => std.debug.print("\\t", .{}),
            else => std.debug.print("{c}", .{c}),
        }
    }
    std.debug.print("\"", .{});
}
```

#### Step 3.4: Rewrite `outputJson()` in `src/cli/status.zig`

Replace the existing function (lines 339-362) with:

```zig
/// JSON output for AI
fn outputJson(issues: []*const Neurona) !void {
    std.debug.print("[", .{});
    for (issues, 0..) |issue, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{", .{});
        std.debug.print("\"id\":\"{s}\",", .{issue.id});
        std.debug.print("\"title\":\"{s}\",", .{issue.title});
        std.debug.print("\"type\":\"{s}\",", .{@tagName(issue.type)});
        
        // Get status from context
        std.debug.print("\"status\":\"", .{});
        switch (issue.context) {
            .test_case => |ctx| std.debug.print("{s}", .{ctx.status}),
            .issue => |ctx| std.debug.print("{s}", .{ctx.status}),
            .requirement => |ctx| std.debug.print("{s}", .{ctx.status}),
            else => std.debug.print("[N/A]"),
        }
        std.debug.print("\",");
        
        // Get priority from context
        std.debug.print("\"priority\":", .{});
        switch (issue.context) {
            .test_case => |ctx| std.debug.print("{d}", .{ctx.priority}),
            .issue => |ctx| std.debug.print("{d}", .{ctx.priority}),
            .requirement => |ctx| std.debug.print("{d}", .{ctx.priority}),
            else => std.debug.print("null"),
        }
        std.debug.print(",");
        
        // Tags count
        std.debug.print("\"tags\":{d}", .{issue.tags.items.len});
        std.debug.print("}", .{});
    }
    std.debug.print("]\n", .{});
}
```

**Test:**
```bash
# Test query JSON
engram query --type requirement --json | jq '.[0]'
# Expect: Contains id, title, type, tags, context, _llm, connections

# Test show JSON
REQ_ID=$(engram status --json | jq -r '.[0].id')
engram show $REQ_ID --json | jq '.'
# Expect: Contains id, title, type, filepath, body, tags, connections, context, _llm

# Test status JSON
engram status --type requirement --json | jq '.[0]'
# Expect: Contains id, title, type, status, priority, tags
```

---

### Priority 4: Fix State Transition Enforcement for Initial Setup (HIGH)

**Problem:** Rigid state machine prevents setting initial status (e.g., `implemented` for completed features).

**Solution:** Add `--force` flag to `engram update` to bypass state validation, OR add `--skip-validation` for initial updates.

**Files to Modify:**
- `src/cli/update.zig` - Add force option
- `src/main.zig` - Parse force flag

#### Step 4.1: Add `force` field to `UpdateConfig`

In `src/cli/update.zig`, update the struct (around line 18):

```zig
pub const UpdateConfig = struct {
    id: []const u8,
    sets: std.ArrayListUnmanaged(FieldUpdate),
    verbose: bool = false,
    neuronas_dir: []const u8 = "neuronas",
    force: bool = false,  // NEW: bypass state validation
};
```

#### Step 4.2: Update `execute()` to pass force flag

In `src/cli/update.zig`, update the applyUpdate call (around line 56):

```zig
for (config.sets.items) |*update| {
    if (try applyUpdate(allocator, &neurona, update.*, config.verbose, config.force)) {
        updated = true;
    }
}
```

#### Step 4.3: Modify `applyUpdate()` signature to accept force flag

In `src/cli/update.zig`, update the function signature (around line 85):

```zig
fn applyUpdate(allocator: Allocator, neurona: *Neurona, update: FieldUpdate, verbose: bool, force: bool) !bool {
```

#### Step 4.4: Update `applyContextUpdate()` signature and add force handling

In `src/cli/update.zig`, update the function signature (around line 152):

```zig
fn applyContextUpdate(allocator: Allocator, neurona: *Neurona, context_field: []const u8, value: []const u8, verbose: bool, force: bool) !bool {
    _ = verbose;
    
    // Skip state validation if force=true
    if (force) {
        // Allow direct setting without validation
        switch (neurona.context) {
            .requirement => |*ctx| {
                if (std.mem.eql(u8, context_field, "status")) {
                    allocator.free(ctx.status);
                    ctx.status = try allocator.dupe(u8, value);
                    return true;
                }
            },
            .test_case => |*ctx| {
                if (std.mem.eql(u8, context_field, "status")) {
                    allocator.free(ctx.status);
                    ctx.status = try allocator.dupe(u8, value);
                    return true;
                }
            },
            .issue => |*ctx| {
                if (std.mem.eql(u8, context_field, "status")) {
                    allocator.free(ctx.status);
                    ctx.status = try allocator.dupe(u8, value);
                    return true;
                }
            },
            else => {},
        }
    }
    
    // ... rest of existing validation logic continues below
```

#### Step 4.5: Pass force flag in applyContextUpdate calls

In `src/cli/update.zig`, update the applyContextUpdate call (around line 91):

```zig
if (std.mem.startsWith(u8, field, "context.")) {
    return try applyContextUpdate(allocator, neurona, field["context.".len..], value, verbose, config.force);
}
```

#### Step 4.6: Parse `--force` flag in `main.zig` `handleUpdate()`

In `src/main.zig`, add force flag parsing (around line 819, after `--verbose`):

```zig
} else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
    config.force = true;
```

**Test:**
```bash
REQ_ID=$(engram new requirement "Test" --no-interactive --json | jq -r .id)

# Test 1: Set implemented status without --force (should fail)
engram update $REQ_ID --set "context.status=implemented"
# Expect: Error - Invalid state transition

# Test 2: Set implemented status with --force (should succeed)
engram update $REQ_ID --set "context.status=implemented" --force
# Expect: Success
```

---

### Priority 5: Verify Multiple `--set` Flags Work (MEDIUM)

**Investigation needed:** The bug report says multiple `--set` flags don't work, but `main.zig` lines 790-824 shows a loop that collects all `--set` flags.

**Action:** Write test to verify this works. If broken, fix the loop.

**Test:**
```bash
REQ_ID=$(engram new requirement "Test" --no-interactive --json | jq -r .id)

engram update $REQ_ID \
  --set title="New Title" \
  --set priority=2 \
  --set "context.status=approved"

# Verify all fields were updated
cat neuronas/$REQ_ID.md
# Expect: title="New Title", priority=2, status=approved
```

**If broken:** Investigate in `src/cli/update.zig` execute() function to ensure the `config.sets` array is properly processed.

---

### Priority 6: Add `--json` Flag to More Commands (MEDIUM)

**Problem:** Bug report says `--json` doesn't work for `query`, `show`, `status`, but code shows it's partially implemented.

**Action:** Verify `--json` flag is parsed in `main.zig` and passed to execute functions.

**Verification:** Check `main.zig`:
- `handleQuery()` line 743: ✅ Has `--json` parsing
- `handleShow()` line 396: ✅ Has `--json` parsing  
- `handleStatus()` line 630: ✅ Has `--json` parsing

**Conclusion:** Flag parsing is correct. The issue is that `outputJson` functions are incomplete (already addressed in Priority 3).

---

### Priority 7: Update Help Documentation (LOW)

**Problem:** Help text may not reflect actual capabilities.

**Action:** Review all help functions and ensure they match implemented features.

In `src/main.zig`, update help text:

- `printUpdateHelp()` (line 1381): Add mention of `--force` flag and `content` field
- `printQueryHelp()` (line 1300): Document that JSON output includes all fields
- `printShowHelp()` (line 1168): Document that JSON output includes body content

Example update to `printUpdateHelp()`:

```zig
fn printUpdateHelp() void {
    std.debug.print(
        \\Update Neurona fields programmatically
        \\
        \\Usage:
        \\  engram update <id> [options]
        \\
        \\Arguments:
        \\  id                Neurona ID to update (required)
        \\
        \\Options:
        \\  --set <field=value> Set field to value (can be repeated)
        \\                    Supported fields:
        \\                      title, type, language, hash
        \\                      tag (use --append to add to list)
        \\                      content (markdown body content)
        \\                      context.status, context.priority, context.assignee, ...
        \\                      _llm_t, _llm_d, _llm_k, _llm_c, _llm_strategy
        \\                    Examples: --set title="New Title"
        \\                              --set content="Description..."
        \\                              --set context.status=implemented
        \\                              --set _llm_t="Short Title"
        \\  --force, -f       Bypass state transition validation (for initial setup)
        \\  --verbose, -v     Show verbose output
        \\
        \\Examples:
        \\  engram update test.001 --set context.status=passing
        \\  engram update req.auth --set title="OAuth 2.0 Support"
        \\  engram update issue.001 --set context.status=resolved
        \\  engram update req.001 --set content="Detailed description" --force
        \\
    , .{});
}
```

---

## Testing Plan

### Test Suite 1: `--set content=` Support

```bash
# Test 1: Set content on new requirement
engram new requirement "Content Test" --no-interactive
REQ_ID=$(engram status --json | jq -r '.[0].id')
engram update $REQ_ID --set content="This is a detailed description for testing"

# Verify
cat neuronas/$REQ_ID.md
# Expected: Body contains "This is a detailed description for testing"

# Test 2: Update content
engram update $REQ_ID --set content="Updated content"

# Verify
cat neuronas/$REQ_ID.md
# Expected: Body contains "Updated content"
```

### Test Suite 2: `--set context.*` Support

```bash
REQ_ID=$(engram new requirement "Context Test" --no-interactive)

# Test 3: Set context status (should fail without force)
engram update $REQ_ID --set "context.status=implemented"
# Expected: Error - Invalid state transition

# Test 4: Set context status with force
engram update $REQ_ID --set "context.status=implemented" --force
# Expected: Success

# Test 5: Set context priority
engram update $REQ_ID --set "context.priority=1"
# Expected: Success

# Test 6: Set context assignee
engram update $REQ_ID --set "context.assignee=alice"
# Expected: Success
```

### Test Suite 3: `--set _llm.*` Support

```bash
REQ_ID=$(engram new requirement "LLM Test" --no-interactive)

# Test 7: Set LLM short title
engram update $REQ_ID --set "_llm_t=Test"
# Expected: Success

# Test 8: Set LLM density
engram update $REQ_ID --set "_llm_d=3"
# Expected: Success

# Test 9: Set LLM keywords
engram update $REQ_ID --set "_llm_k=keyword1,keyword2,keyword3"
# Expected: Success

# Test 10: Set LLM token count
engram update $REQ_ID --set "_llm_c=500"
# Expected: Success

# Test 11: Set LLM strategy
engram update $REQ_ID --set "_llm_strategy=full"
# Expected: Success
```

### Test Suite 4: JSON Output Completeness

```bash
# Test 12: Query with JSON
engram query --type requirement --json > query_output.json
jq '.[0]' query_output.json
# Expected: Output contains id, title, type, tags, context, _llm (if set), connections

# Test 13: Show with JSON
engram show $REQ_ID --json > show_output.json
jq '.' show_output.json
# Expected: Output contains id, title, type, filepath, body, tags, connections, context, _llm

# Test 14: Status with JSON
engram status --type requirement --json > status_output.json
jq '.[0]' status_output.json
# Expected: Output contains id, title, type, status, priority, tags
```

### Test Suite 5: Multiple `--set` Flags

```bash
REQ_ID=$(engram new requirement "Multi Test" --no-interactive)

# Test 15: Multiple updates in one command
engram update $REQ_ID \
  --set title="Multi Update" \
  --set priority=2 \
  --set "context.status=approved"

# Verify
cat neuronas/$REQ_ID.md
# Expected: title="Multi Update", priority=2, status=approved
```

### Test Suite 6: State Transition Bypass

```bash
REQ_ID=$(engram new requirement "State Test" --no-interactive)

# Test 16: Set implemented status directly (without --force - should fail)
engram update $REQ_ID --set "context.status=implemented"
# Expected: Error - Invalid state transition

# Test 17: Set implemented status with --force
engram update $REQ_ID --set "context.status=implemented" --force
# Expected: Success

# Verify
cat neuronas/$REQ_ID.md
# Expected: status=implemented
```

---

## Implementation Timeline

| Priority | Task | Estimated Effort | Dependencies |
|----------|-------|-----------------|--------------|
| P1 | Fix `--set content=` | 2 hours | None |
| P1 | Expand `--set context.*` | 3 hours | None |
| P1 | Add `--set _llm.*` support | 2 hours | None |
| P2 | Fix JSON output completeness | 2 hours | P1 (content), P1 (_llm) |
| P2 | Fix state transition enforcement | 1 hour | None |
| P3 | Verify multiple `--set` | 0.5 hours | None |
| P4 | Update help documentation | 0.5 hours | All above |

**Total estimated effort: ~11 hours**

---

## Implementation Status Update

Based on review of the last 5 commits (Feb 1-2, 2026):

### ✅ **COMPLETED:**

#### Priority 1: `--set content=` Support
- **Commit 7261ba9** (Feb 1, 22:54): ✅ Fully implemented
  - Added `updateBody()` function to `filesystem.zig`
  - Added content field handling to `update.zig`
  - Modified `writeNeurona()` to support `preserve_body` flag
  - Tested and working correctly

#### Priority 2: JSON Output Completeness  
- **Commit 428f0ef** (Feb 1, 23:28): ✅ Fully implemented
  - Expanded `outputJson()` in all CLI modules
  - Added `printJsonString()` helper for proper escaping
  - Complete neurona data now included in JSON output
  - Backward compatibility maintained

### ⚠️ **IN PROGRESS / NEEDS DEBUGGING:**

#### Priority 2: `--set context.*` and `--set _llm.*` Support
- **Commit 591af61** (Feb 1, 23:09): ⚠️ Partially implemented
- **Commit aafa0cf** (Feb 1, 23:12): ⚠️ Documented Zig compilation errors
  - LLMMetadata import added
  - `updateLLMMetadata()` helper function added
  - Field handling code added but has compilation errors:
    - `use of undeclared identifier 'field'` (should be `update.field`)
    - JSON syntax errors in output functions (resolved in later commit)

### ❌ **NOT YET STARTED:**

#### Priority 2: State Transition Enforcement
- No commits yet
- Need to add `--force` flag to bypass state validation

#### Priority 3: Multiple `--set` Flags Verification
- No commits yet  
- Need to test if multiple flags work correctly

#### Priority 4: Help Documentation Updates
- No commits yet
- Need to update help text to reflect new capabilities

---

## Summary

This plan addresses all 6 categories of issues in the bug report:

1. **✅ `--set content=`** - COMPLETED (Feb 1)
2. **⚠️ `--set context.*`** - IN PROGRESS - Has Zig compilation errors to fix
3. **⚠️ `--set _llm.*`** - IN PROGRESS - Same compilation errors as above
4. **✅ `--json` flags** - COMPLETED (Feb 1)
5. **❌ State transitions** - NOT STARTED - Need `--force` flag
6. **❌ Multiple `--set`** - NOT STARTED - Need verification

**Current Status:** 2/6 priorities completed, 2/6 in progress with bugs, 2/6 not started

After implementing all fixes, Engram will support the full documented API:

- ✅ Set all fields including `content`
- ✅ Set all `context.*` fields
- ✅ Set all `_llm.*` metadata
- ✅ Query/Show/Status with complete JSON output
- ✅ Bypass state transitions for initial setup
- ✅ Multiple field updates in one command

This will enable full programmatic Engram usage for AI agents and automation scripts, resolving all blockers for the zigstory project.

---

## Verification Checklist

**CRITICAL - Must Fix First:**
- [ ] **Fix Zig compilation errors** in `src/cli/update.zig`
  - [ ] Change `field` to `update.field` in _llm handling (line 94+)
  - [ ] Ensure all `field` references use `update.field`
  - [ ] Verify `zig build run` compiles successfully

**COMPLETED - Can Verify Now:**
- [x] `engram update --set content=` works (verified in commits)
- [x] `engram query --json` outputs complete data (completed in commit 428f0ef)
- [x] `engram show --json` outputs complete data (completed in commit 428f0ef)
- [x] `engram status --json` outputs complete data (completed in commit 428f0ef)

**PENDING - Fix Compilation Errors First:**
- [ ] `engram update --set context.*` works (needs compilation fix)
- [ ] `engram update --set _llm.*` works (needs compilation fix)
- [ ] `engram update --force` bypasses state validation (not implemented)
- [ ] Multiple `--set` flags work in single command (needs verification)
- [ ] Help documentation is updated (not implemented)
- [ ] All test suites pass successfully
- [ ] Integration tests pass

---

## Immediate Next Steps (Critical Fixes Required)

### 1. **Fix Zig Compilation Errors in `--set _llm.*` Support**
**Files:** `src/cli/update.zig`
**Issue:** Line 94 uses `field` instead of `update.field`
**Fix:** Update all references from `field` to `update.field` in the _llm handling code

```zig
// Current (BROKEN):
if (std.mem.eql(u8, field, "_llm_t")) {

// Should be (FIXED):
if (std.mem.eql(u8, update.field, "_llm_t")) {
```

### 2. **Complete `--set context.*` Support**
The framework is in place but needs debugging. Fix the same `field` vs `update.field` issues in context handling.

### 3. **Test `--set _llm.*` and `--set context.*` After Fixes**
```bash
# Test _llm fields
engram update req.test --set "_llm_t=Short Title"
engram update req.test --set "_llm_d=3"
engram update req.test --set "_llm_k=keyword1,keyword2"

# Test context fields  
engram update req.test --set "context.acceptance_criteria=criteria1,criteria2"
engram update req.test --set "context.resolution_notes=Fixed issue"
```

### 4. **Implement Remaining Priorities**
- Add `--force` flag for state transition bypass
- Verify multiple `--set` flags work
- Update help documentation

### 5. **Full Testing Suite**
Run all test suites from the original plan once compilation issues are resolved.

---

## Updated Implementation Timeline

| Priority | Task | Status | Estimated Effort |
|----------|-------|---------|-----------------|
| P1 | `--set content=` | ✅ Complete | 2 hours (Done) |
| P1 | `--set context.*` | ⚠️ Needs debugging | 1 hour (fix errors) |
| P1 | `--set _llm.*` | ⚠️ Needs debugging | 1 hour (fix errors) |
| P2 | JSON output | ✅ Complete | 2 hours (Done) |
| P2 | State transitions | ❌ Not started | 1 hour |
| P3 | Multiple `--set` | ❌ Not started | 0.5 hours |
| P4 | Help docs | ❌ Not started | 0.5 hours |

**Remaining effort: ~4 hours** (after fixing compilation errors)

---

**Document Version:** 1.1  
**Created:** February 1, 2026  
**Last Updated:** February 2, 2026  
**Status:** Partially Implemented - In Progress
