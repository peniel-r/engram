# Polish Plan

## 1. Enhance `engram status`
**Goal:** Add `--blocking <target>` convenience flag to easily find issues blocking a specific requirement or release.

*   **File:** `src/cli/status.zig`
    *   Add `blocking_target: ?[]const u8` to `StatusConfig`.
    *   Update `filterNeuronas` to scan connections for `blocks` type and matching target.
*   **File:** `src/main.zig`
    *   Update `handleStatus` to parse `--blocking <id>` flag and populate `StatusConfig`.

## 2. Enable Interactive `engram new`
**Goal:** Restore interactive context gathering to allow human users to input fields like priority and status during creation.

*   **File:** `src/cli/new.zig`
    *   Implement `readStringInput` helper using `std.io.getStdIn()`.
    *   Update `gatherContextInteractive` to use `readStringInput` instead of skipping.

## 3. Enhance `engram trace`
**Goal:** Add `--full-chain` flag to trace dependencies to the maximum depth.

*   **File:** `src/cli/trace.zig`
    *   Add `full_chain: bool` to `TraceConfig`.
    *   Update `execute` to set `max_depth = usize.max` if `full_chain` is true.
*   **File:** `src/main.zig`
    *   Update `handleTrace` to parse `--full-chain` flag.

## 4. Verification Strategy
*   **Status Check:** Run `engram status --blocking <issue_id>` and verify it lists issues blocking that target.
*   **New Check:** Run `engram new requirement "Test Req"` and verify prompts appear and input is saved.
*   **Trace Check:** Run `engram trace <id> --full-chain` and verify it traces deeper than the default 10 levels (if data exists).
