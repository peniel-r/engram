// File: src/utils/command_metadata.zig
// Command registry and metadata for auto-generation

const std = @import("std");

/// Flag type metadata
pub const FlagType = enum {
    bool,
    string,
    number,
    @"enum",
};

/// Metadata for a single flag
pub const FlagMetadata = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    description: []const u8,
    value_type: FlagType,
    required: bool = false,
    enum_values: ?[]const []const u8 = null,
    default_value: ?[]const u8 = null,
};

/// Metadata for a command
pub const CommandMetadata = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    examples: []const []const u8,
    flags: []const FlagMetadata,
    min_args: usize,
    max_args: usize,
};

/// Command registry with all commands
pub const command_registry = [_]CommandMetadata{
    // init command
    .{
        .name = "init",
        .description = "Initialize a new Cortex",
        .usage = "engram init <name> [--type <type>] [--language <lang>] [--force] [--verbose]",
        .examples = &[_][]const u8{
            "engram init my-project",
            "engram init my-project --type alm",
            "engram init my-project --type notes --language de",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "type",
                .short = "-t",
                .description = "Cortex type (notes, alm, knowledge)",
                .value_type = .@"enum",
                .enum_values = &[_][]const u8{ "notes", "alm", "knowledge" },
                .default_value = "alm",
            },
            .{
                .name = "language",
                .short = "-l",
                .description = "Default language code (en, de, fr, etc.)",
                .value_type = .string,
                .default_value = "en",
            },
            .{
                .name = "force",
                .short = "-f",
                .description = "Force overwrite existing Cortex",
                .value_type = .bool,
            },
            .{
                .name = "verbose",
                .short = "-v",
                .description = "Verbose output",
                .value_type = .bool,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // new command
    .{
        .name = "new",
        .description = "Create a new Neurona",
        .usage = "engram new <type> <title> [options]",
        .examples = &[_][]const u8{
            "engram new requirement \"User Authentication\"",
            "engram new test_case \"Login Test\" --validates req.auth.login",
            "engram new issue \"Bug in login\" --priority 1",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "tag",
                .short = "-t",
                .description = "Add tag to neurona",
                .value_type = .string,
            },
            .{
                .name = "assignee",
                .description = "Assign to person",
                .value_type = .string,
            },
            .{
                .name = "priority",
                .short = "-p",
                .description = "Priority level (1-5)",
                .value_type = .number,
            },
            .{
                .name = "parent",
                .description = "Parent neurona ID",
                .value_type = .string,
            },
            .{
                .name = "validates",
                .description = "Requirement ID this validates",
                .value_type = .string,
            },
            .{
                .name = "blocks",
                .description = "Neurona ID this blocks",
                .value_type = .string,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "no-interactive",
                .description = "Non-interactive mode",
                .value_type = .bool,
            },
        },
        .min_args = 2,
        .max_args = 3,
    },

    // show command
    .{
        .name = "show",
        .description = "Display a Neurona",
        .usage = "engram show <id> [options]",
        .examples = &[_][]const u8{
            "engram show req.auth.login",
            "engram show req.auth.login --json",
            "engram show req.auth.login --no-body",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "no-connections",
                .description = "Don't show connections",
                .value_type = .bool,
            },
            .{
                .name = "no-body",
                .description = "Don't show body content",
                .value_type = .bool,
            },
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // link command
    .{
        .name = "link",
        .description = "Create connections between Neuronas",
        .usage = "engram link <source> <type> <target> [options]",
        .examples = &[_][]const u8{
            "engram link test.login validates req.auth.login",
            "engram link test.api blocks req.auth.login",
            "engram link req.auth.login depends-on req.db.users",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "weight",
                .short = "-w",
                .description = "Connection weight (0.0-1.0)",
                .value_type = .number,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 3,
        .max_args = 3,
    },

    // sync command
    .{
        .name = "sync",
        .description = "Rebuild graph index",
        .usage = "engram sync",
        .examples = &[_][]const u8{
            "engram sync",
            "engram sync --cortex ./my-cortex",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 0,
        .max_args = 0,
    },

    // delete command
    .{
        .name = "delete",
        .description = "Delete a Neurona",
        .usage = "engram delete <id> [options]",
        .examples = &[_][]const u8{
            "engram delete req.auth.login",
            "engram delete req.auth.login --force",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "force",
                .short = "-f",
                .description = "Force delete without confirmation",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // trace command
    .{
        .name = "trace",
        .description = "Trace dependencies",
        .usage = "engram trace <id> [options]",
        .examples = &[_][]const u8{
            "engram trace req.auth.login",
            "engram trace req.auth.login --depth 3",
            "engram trace req.auth.login --direction up",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "depth",
                .short = "-d",
                .description = "Trace depth (default: infinite)",
                .value_type = .number,
            },
            .{
                .name = "direction",
                .description = "Trace direction (up, down, both)",
                .value_type = .@"enum",
                .enum_values = &[_][]const u8{ "up", "down", "both" },
                .default_value = "both",
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // status command
    .{
        .name = "status",
        .description = "List status",
        .usage = "engram status [options]",
        .examples = &[_][]const u8{
            "engram status",
            "engram status --type requirement",
            "engram status --json",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "type",
                .short = "-t",
                .description = "Filter by neurona type",
                .value_type = .@"enum",
                .enum_values = &[_][]const u8{ "requirement", "test_case", "issue", "artifact", "feature" },
            },
            .{
                .name = "state",
                .description = "Filter by state",
                .value_type = .string,
            },
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 0,
        .max_args = 0,
    },

    // query command
    .{
        .name = "query",
        .description = "Query interface",
        .usage = "engram query <query> [options]",
        .examples = &[_][]const u8{
            "engram query \"type:requirement AND status:approved\"",
            "engram query --mode vector \"authentication issues\"",
            "engram query \"link(validates, req.auth.login)\" --json",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "mode",
                .short = "-m",
                .description = "Query mode (filter, text, vector, hybrid, activation)",
                .value_type = .@"enum",
                .enum_values = &[_][]const u8{ "filter", "text", "vector", "hybrid", "activation" },
                .default_value = "filter",
            },
            .{
                .name = "limit",
                .short = "-l",
                .description = "Limit results",
                .value_type = .number,
            },
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // update command
    .{
        .name = "update",
        .description = "Update Neurona fields",
        .usage = "engram update <id> [options]",
        .examples = &[_][]const u8{
            "engram update req.auth.login --set \"state=implemented\"",
            "engram update req.auth.login --set \"assignee=alice\"",
            "engram update req.auth.login --add-tag \"security\"",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "set",
                .description = "Set field value (format: field=value)",
                .value_type = .string,
            },
            .{
                .name = "add-tag",
                .description = "Add tag to neurona",
                .value_type = .string,
            },
            .{
                .name = "remove-tag",
                .description = "Remove tag from neurona",
                .value_type = .string,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // impact command
    .{
        .name = "impact",
        .description = "Impact analysis for code changes",
        .usage = "engram impact <artifact> [options]",
        .examples = &[_][]const u8{
            "engram impact src/auth/login.zig",
            "engram impact src/auth/login.zig --up",
            "engram impact src/auth/login.zig --down --json",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "up",
                .short = "-u",
                .description = "Show upstream dependencies",
                .value_type = .bool,
            },
            .{
                .name = "down",
                .short = "-d",
                .description = "Show downstream dependencies",
                .value_type = .bool,
            },
            .{
                .name = "depth",
                .description = "Analysis depth",
                .value_type = .number,
            },
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 1,
        .max_args = 1,
    },

    // link-artifact command
    .{
        .name = "link-artifact",
        .description = "Link source files to requirements",
        .usage = "engram link-artifact <file> <requirement_id>",
        .examples = &[_][]const u8{
            "engram link-artifact src/auth/login.zig req.auth.login",
            "engram link-artifact src/api/users.ts req.api.users",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 2,
        .max_args = 2,
    },

    // release-status command
    .{
        .name = "release-status",
        .description = "Release readiness check",
        .usage = "engram release-status [options]",
        .examples = &[_][]const u8{
            "engram release-status",
            "engram release-status --json",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 0,
        .max_args = 0,
    },

    // metrics command
    .{
        .name = "metrics",
        .description = "Display project metrics",
        .usage = "engram metrics [options]",
        .examples = &[_][]const u8{
            "engram metrics",
            "engram metrics --json",
        },
        .flags = &[_]FlagMetadata{
            .{
                .name = "json",
                .short = "-j",
                .description = "Output as JSON",
                .value_type = .bool,
            },
            .{
                .name = "cortex",
                .description = "Custom cortex directory",
                .value_type = .string,
            },
        },
        .min_args = 0,
        .max_args = 0,
    },

    // man command
    .{
        .name = "man",
        .description = "Show manual",
        .usage = "engram man [topic]",
        .examples = &[_][]const u8{
            "engram man",
            "engram man query",
            "engram man link",
        },
        .flags = &[_]FlagMetadata{},
        .min_args = 0,
        .max_args = 1,
    },
};

/// Find command metadata by name
pub fn findCommand(command_name: []const u8) ?*const CommandMetadata {
    for (&command_registry) |*cmd| {
        if (std.mem.eql(u8, cmd.name, command_name)) {
            return cmd;
        }
    }
    return null;
}

// ==================== Tests ====================

test "findCommand - existing command" {
    const cmd = findCommand("init");
    try std.testing.expect(cmd != null);
    try std.testing.expectEqualStrings("init", cmd.?.name);
}

test "findCommand - non-existent command" {
    const cmd = findCommand("nonexistent");
    try std.testing.expect(cmd == null);
}

test "command_registry - all commands present" {
    try std.testing.expectEqual(@as(usize, 15), command_registry.len);
}

test "command_registry - init command metadata" {
    const cmd = &command_registry[0];
    try std.testing.expectEqualStrings("init", cmd.name);
    try std.testing.expectEqual(@as(usize, 1), cmd.min_args);
    try std.testing.expectEqual(@as(usize, 1), cmd.max_args);
    try std.testing.expectEqual(@as(usize, 4), cmd.flags.len);
}
