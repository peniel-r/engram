# Issue: Neuronas and .activations Created Outside Cortex Folder

**Type**: Bug Report
**Priority**: Medium
**Status**: Open
**Affected Component**: Engram CLI
**Report Date**: February 4, 2026

---

## Problem Description

When running `engram new` commands from within a project directory that contains a subdirectory with a cortex (e.g., `project/`), newly created neurona files and `.activations` folder are created in the root directory instead of inside the `project/` cortex folder.

## Steps to Reproduce

1. Initialize a cortex:
   ```bash
   engram init project --type alm
   ```
   This creates `project/` directory with:
   - `project/cortex.json`
   - `project/.activations/`
   - `project/neuronas/` (empty)

2. From the parent directory (e.g., `C:\git\ZiGUI`), run:
   ```bash
   engram new requirement "Some Title" --priority 1
   engram new feature "Some Title"
   ```

3. **Result**: Neurona files are created at `C:\git\ZiGUI\neuronas/` instead of `C:\git\ZiGUI\project\neuronas/`

4. **Result**: `.activations` folder is created at `C:\git\ZiGUI\.activations/` instead of `C:\git\ZiGUI\project\.activations/`

## Expected Behavior

- Engram should detect the existing cortex folder in subdirectories
- New neurona files should be created inside the detected cortex folder
- `.activations` folder should be maintained inside the cortex folder

## Actual Behavior

- Engram creates a new cortex structure at the current working directory
- Neurona files are created outside the existing cortex
- Multiple `.activations` folders can be created (one in root, one in project/)
- This leads to orphaned neuronas and data inconsistency

## Impact

- **User Experience**: Confusing and unexpected behavior
- **Data Integrity**: Neuronas are not properly associated with the correct cortex
- **Maintenance**: Manual intervention required to move files to correct location
- **Consistency**: Risk of orphaned neuronas and broken connections

## Manual Workaround Applied

The following manual steps were required to fix the issue:

```bash
# Move neurona files to correct location
mv neuronas/* project/neuronas/

# Move activations graph index
cp .activations/graph.idx project/.activations/

# Remove incorrectly placed directories
rmdir neuronas
rm -rf .activations

# Re-sync engram
cd project
engram sync
```

## Root Cause Analysis

Engram does not seem to detect the presence of a cortex folder in subdirectories when commands are run from the parent directory. The tool appears to:

1. **Always create** a new cortex structure at the current working directory
2. **Not recursively search** for existing cortex folders
3. **Not validate** or check if the current directory is within an existing cortex

This behavior is problematic because:

- Users often run commands from project root directories
- Cortex folders are typically organized in subdirectories
- The lack of detection leads to duplicate and conflicting structures

## Proposed Solutions

### Option 1: Automatic Cortex Detection

Implement automatic cortex detection that:

1. Recursively searches parent directories for a valid `cortex.json` file
2. Uses the detected cortex as the target for all operations
3. Provides clear warning/error if multiple cortex folders are found
4. Allows explicit override via a `--cortex` flag

**Example Usage**:
```bash
# Auto-detects project/ cortex
engram new requirement "Title"

# Explicit override
engram new requirement "Title" --cortex project
```

**Benefits**:
- Zero-configuration for most use cases
- Intuitive and expected behavior
- Reduces user errors

**Implementation Considerations**:
- Maximum search depth (e.g., 5 levels up)
- Priority selection when multiple cortexes found
- Clear error messages for ambiguous situations

### Option 2: Cortex Path Validation

Add validation to prevent creating neuronas outside a cortex:

1. Check if `cortex.json` exists in the current directory
2. If not, search parent directories (up to N levels)
3. If no cortex is found, require the user to specify `--cortex` path
4. Display clear error message: "No cortex found. Use `--cortex <path>` to specify location"

**Example Behavior**:
```bash
# No cortex detected
$ engram new requirement "Title"
Error: No cortex found in current directory or parent directories.
Use `--cortex <path>` to specify a cortex location, or navigate to the cortex directory.

# With explicit path
$ engram new requirement "Title" --cortex project
✓ Created req.example
```

**Benefits**:
- Prevents accidental creation of orphaned neuronas
- Forces users to be explicit about cortex location
- Reduces confusion and errors

**Implementation Considerations**:
- Configurable maximum search depth
- Caching of detected cortex for performance
- Warning instead of error for non-critical commands

### Option 3: Explicit Cortex Context

Always require explicit cortex context when running from outside a cortex:

**Example Usage**:
```bash
# Current behavior (problematic)
engram new requirement "Title"

# Proposed behavior (explicit)
engram --cortex project new requirement "Title"

# Or navigate to cortex directory first
cd project
engram new requirement "Title"
```

**Benefits**:
- Completely unambiguous behavior
- Users are always aware of cortex location
- Easier to reason about and debug

**Drawbacks**:
- More verbose command-line usage
- Higher friction for common workflows

### Option 4: Configuration File Support

Add a local configuration file that engram can detect and use:

**Example `.engramrc.json`**:
```json
{
  "cortex": "project",
  "default_type": "alm",
  "auto_detect": true,
  "search_depth": 5
}
```

**Behavior**:
- Engram checks current directory for `.engramrc.json`
- If found, uses specified cortex path
- Falls back to auto-detection if not found
- Allows project-specific configuration

**Benefits**:
- Per-project configuration flexibility
- No need to repeatedly specify `--cortex` flag
- Can store other project-specific settings

**Implementation Considerations**:
- Configuration file format (JSON, YAML, TOML)
- Priority when multiple `.engramrc.json` files exist
- Command-line flag override behavior

### Option 5: Hybrid Approach (Recommended)

Combine multiple approaches for the best user experience:

1. **Primary**: Automatic cortex detection (Option 1)
2. **Fallback**: Explicit `--cortex` flag when needed
3. **Configuration**: `.engramrc.json` for project-specific overrides
4. **Validation**: Error when no cortex can be detected

**Example Behavior**:
```bash
# Scenario 1: Auto-detection works
$ cd /path/to/project
$ engram new requirement "Title"
✓ Using cortex: project/
✓ Created req.example

# Scenario 2: Multiple cortexes found
$ engram new requirement "Title"
Warning: Multiple cortexes detected:
  1. project/ (depth 1)
  2. old-project/ (depth 2)
Using cortex: project/
✓ Created req.example

# Scenario 3: Explicit override
$ engram new requirement "Title" --cortex old-project
✓ Using cortex: old-project/
✓ Created req.example

# Scenario 4: Configuration file
# .engramrc.json contains: {"cortex": "dev"}
$ engram new requirement "Title"
✓ Using cortex from .engramrc.json: dev/
✓ Created req.example
```

## Requirements

### Functional Requirements

1. **Cortex Detection**: Engram must detect cortex folders in parent directories
2. **Correct Location**: Neurona files must always be created inside a valid cortex folder
3. **Activations Folder**: `.activations` folder must always be inside a valid cortex folder
4. **Recursive Search**: Cortex detection should work recursively up the directory tree
5. **Clear Errors**: Display clear error messages when no cortex can be detected
6. **Explicit Override**: `--cortex` flag allows explicit cortex specification
7. **Configuration**: Support for `.engramrc.json` configuration files

### Non-Functional Requirements

1. **Performance**: Cortex detection should complete within 100ms
2. **Compatibility**: Must work on Windows, Linux, and macOS
3. **Backward Compatibility**: Existing workflows should not break
4. **Documentation**: User-facing documentation must be updated

## Acceptance Criteria

- [ ] Engram detects cortex folders in parent directories (up to configurable depth)
- [ ] New neuronas are created inside the detected cortex
- [ ] `.activations` folder is created/maintained inside the detected cortex
- [ ] Clear error message is displayed when no cortex can be detected
- [ ] `--cortex` flag allows explicit cortex specification and overrides detection
- [ ] `.engramrc.json` configuration files are supported
- [ ] Multiple cortex detection scenarios are handled gracefully
- [ ] Documentation is updated with cortex detection behavior
- [ ] Unit tests cover cortex detection logic
- [ ] Integration tests verify neurona creation in correct location

## Test Cases

### Test Case 1: Single Cortex in Subdirectory

**Setup**:
```
project-root/
├── .engramrc.json (optional)
├── project/
│   ├── cortex.json
│   ├── neuronas/
│   └── .activations/
```

**Command**: `cd project-root && engram new requirement "Test" --priority 1`

**Expected**: Neurona created in `project-root/project/neuronas/`

### Test Case 2: Multiple Cortexes

**Setup**:
```
project-root/
├── project/
│   └── cortex.json
├── old-project/
│   └── cortex.json
```

**Command**: `cd project-root && engram new requirement "Test"`

**Expected**: Warning displayed, uses closest cortex (`project/`)

### Test Case 3: No Cortex Found

**Setup**: Empty directory or directory without `cortex.json`

**Command**: `cd empty-dir && engram new requirement "Test"`

**Expected**: Error message requiring `--cortex` flag

### Test Case 4: Explicit Override

**Setup**: Any directory structure

**Command**: `engram new requirement "Test" --cortex /path/to/cortex`

**Expected**: Neurona created in specified cortex location

### Test Case 5: Configuration File

**Setup**: `.engramrc.json` with cortex path

**Command**: `engram new requirement "Test"`

**Expected**: Uses cortex from configuration file

## Additional Context

### Environment

- **Engram Version**: 0.1.0
- **Operating System**: Windows (Git Bash)
- **Working Directory**: `C:\git\ZiGUI`
- **Cortex Directory**: `C:\git\ZiGUI\project\`

### Use Case

The reporter was setting up an engram cortex for the ZigGUI project and needed to create requirements from the project issues documented in `docs/plan.md`. The expected workflow was to run engram commands from the project root directory, with neuronas being created in the `project/` subdirectory cortex.

### References

- Engram documentation (if available)
- Similar tools' behavior (e.g., Git's `.git` detection)
- Best practices for CLI tool directory detection

---

## Attachments

- **Workaround Commands**: Bash script used to manually fix the issue
- **Directory Structure**: Before and after structure comparison
- **Error Logs**: Any relevant error messages from engram

---

## Contact Information

**Reporter**: ZiGUI Project Team
**Project**: https://github.com/[username]/ZiGUI
**Issue Tracker**: (link if applicable)

---

*This issue is being sent directly to the engram development team for review and implementation.*
