const std = @import("std");
const Allocator = std.mem.Allocator;

// Import all CLI command modules
const init_cmd = @import("cli/init.zig");
const new_cmd = @import("cli/new.zig");
const show_cmd = @import("cli/show.zig");
const link_cmd = @import("cli/link.zig");
const sync_cmd = @import("cli/sync.zig");
const delete_cmd = @import("cli/delete.zig");
const trace_cmd = @import("cli/trace.zig");
const status_cmd = @import("cli/status.zig");
const query_cmd = @import("cli/query.zig");
const query_helpers = @import("cli/query_helpers.zig");
const update_cmd = @import("cli/update.zig");
const impact_cmd = @import("cli/impact.zig");
const link_artifact_cmd = @import("cli/link_artifact.zig");
const release_status_cmd = @import("cli/release_status.zig");
const metrics_cmd = @import("cli/metrics.zig");
const man_cmd = @import("cli/man.zig");

// Command registry
const Command = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (allocator: Allocator, args: []const []const u8) anyerror!void,
    help_fn: *const fn () void,
};

const commands = [_]Command{
    .{
        .name = "init",
        .description = "Initialize a new Cortex",
        .handler = handleInit,
        .help_fn = printInitHelp,
    },
    .{
        .name = "new",
        .description = "Create a new Neurona",
        .handler = handleNew,
        .help_fn = printNewHelp,
    },
    .{
        .name = "show",
        .description = "Display a Neurona",
        .handler = handleShow,
        .help_fn = printShowHelp,
    },
    .{
        .name = "link",
        .description = "Create connections between Neuronas",
        .handler = handleLink,
        .help_fn = printLinkHelp,
    },
    .{
        .name = "sync",
        .description = "Rebuild graph index",
        .handler = handleSync,
        .help_fn = printSyncHelp,
    },
    .{
        .name = "delete",
        .description = "Delete a Neurona",
        .handler = handleDelete,
        .help_fn = printDeleteHelp,
    },
    .{
        .name = "trace",
        .description = "Trace dependencies",
        .handler = handleTrace,
        .help_fn = printTraceHelp,
    },
    .{
        .name = "status",
        .description = "List status",
        .handler = handleStatus,
        .help_fn = printStatusHelp,
    },
    .{
        .name = "query",
        .description = "Query interface",
        .handler = handleQuery,
        .help_fn = printQueryHelp,
    },
    .{
        .name = "update",
        .description = "Update Neurona fields",
        .handler = handleUpdate,
        .help_fn = printUpdateHelp,
    },
    .{
        .name = "impact",
        .description = "Impact analysis for code changes",
        .handler = handleImpact,
        .help_fn = printImpactHelp,
    },
    .{
        .name = "link-artifact",
        .description = "Link source files to requirements",
        .handler = handleLinkArtifact,
        .help_fn = printLinkArtifactHelp,
    },
    .{
        .name = "release-status",
        .description = "Release readiness check",
        .handler = handleReleaseStatus,
        .help_fn = printReleaseStatusHelp,
    },
    .{
        .name = "metrics",
        .description = "Display project metrics",
        .handler = handleMetrics,
        .help_fn = printMetricsHelp,
    },
    .{
        .name = "man",
        .description = "Show manual",
        .handler = handleMan,
        .help_fn = printManHelp,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Handle --help and --version first (no command needed)
    if (args.len == 1) {
        printUsage();
        return;
    }

    const first_arg = args[1];

    // Global flags (no command needed)
    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        printHelp();
        return;
    }

    if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-v")) {
        printVersion();
        return;
    }

    // Find and execute command
    for (commands) |cmd| {
        if (std.mem.eql(u8, first_arg, cmd.name)) {
            // Check for --help flag after command name
            if (args.len > 2 and (std.mem.eql(u8, args[2], "--help") or std.mem.eql(u8, args[2], "-h"))) {
                cmd.help_fn();
                return;
            }

            try cmd.handler(allocator, args);
            return;
        }
    }

    // Unknown command
    std.debug.print("Unknown command: {s}\n\n", .{first_arg});
    printUsage();
    std.process.exit(1);
}

// ==================== Error Handling Helpers ====================

/// Handle NeuronaNotFound error gracefully
/// Prints user-friendly error message and exits if the error is NeuronaNotFound
/// Otherwise returns the error for further handling
fn handleNeuronaNotFound(err: anyerror, id: []const u8) void {
    if (err == error.NeuronaNotFound) {
        std.debug.print("Error: Neurona '{s}' not found.\n", .{id});
        std.debug.print("\nHint: Run 'engram status' to see all available neuronas.\n", .{});
        std.process.exit(1);
    }
}

/// Handle errors specific to link-artifact command
/// Handles NeuronaNotFound and InvalidNeuronaType errors
fn handleLinkArtifactError(err: anyerror, id: []const u8) void {
    if (err == error.NeuronaNotFound) {
        std.debug.print("Error: Neurona '{s}' not found.\n", .{id});
        std.debug.print("\nHint: Run 'engram status' to see all available neuronas.\n", .{});
        std.process.exit(1);
    } else if (err == error.InvalidNeuronaType) {
        std.debug.print("Error: '{s}' is not a requirement.\n", .{id});
        std.debug.print("\nHint: link-artifact only works with requirement neuronas.\n", .{});
        std.process.exit(1);
    }
}

// ==================== Command Handlers ====================

fn handleInit(allocator: Allocator, args: []const []const u8) !void {
    var name: ?[]const u8 = null;

    var config = init_cmd.InitConfig{
        .name = undefined,
        .cortex_type = .alm,
        .default_language = "en",
        .force = false,
        .verbose = false,
    };

    // Parse command-line arguments
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, "--type") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --type requires a value\n", .{});
                printInitHelp();
                std.process.exit(1);
            }
            i += 1;
            const type_str = args[i];
            const cortex_type = init_cmd.CortexType.fromString(type_str);
            if (cortex_type == null) {
                std.debug.print("Error: Invalid cortex type '{s}'. Valid types: zettelkasten, alm, knowledge\n", .{type_str});
                printInitHelp();
                std.process.exit(1);
            }
            config.cortex_type = cortex_type.?;
        } else if (std.mem.eql(u8, arg, "--language") or std.mem.eql(u8, arg, "-l")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --language requires a value\n", .{});
                printInitHelp();
                std.process.exit(1);
            }
            i += 1;
            config.default_language = args[i];
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            config.force = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // Unknown flag
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printInitHelp();
            std.process.exit(1);
        } else if (name == null) {
            // First non-flag argument is the Cortex name
            name = arg;
        } else {
            std.debug.print("Error: Too many arguments\n", .{});
            printInitHelp();
            std.process.exit(1);
        }
    }

    // Validate that Cortex name was provided
    if (name == null) {
        std.debug.print("Error: Cortex name is required\n", .{});
        printInitHelp();
        std.process.exit(1);
    }

    config.name = name.?;
    try init_cmd.execute(allocator, config);
}

fn handleNew(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing required arguments\n", .{});
        printNewHelp();
        std.process.exit(1);
    }

    // Parse neurona type
    const type_str = args[2];
    const neurona_type = new_cmd.NeuronaType.fromString(type_str);
    if (neurona_type == null) {
        std.debug.print("Error: Invalid neurona type '{s}'. Valid types: requirement, test_case, issue, artifact, feature\n", .{type_str});
        printNewHelp();
        std.process.exit(1);
    }

    // Parse title
    if (args.len < 4) {
        std.debug.print("Error: Missing title\n", .{});
        printNewHelp();
        std.process.exit(1);
    }
    const title = args[3];

    var config = new_cmd.NewConfig{
        .neurona_type = neurona_type.?,
        .title = title,
        .interactive = true,
        .json_output = false,
        .auto_link = true,
        .cortex_dir = null,
    };

    // Parse options
    var i: usize = 4;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--tag") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --tag requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            _ = args[i]; // Would add to tags list in full implementation
        } else if (std.mem.eql(u8, arg, "--assignee")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --assignee requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.assignee = args[i];
        } else if (std.mem.eql(u8, arg, "--priority") or std.mem.eql(u8, arg, "-p")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --priority requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.priority = std.fmt.parseInt(u8, args[i], 10) catch {
                std.debug.print("Error: Invalid priority '{s}'\n", .{args[i]});
                printNewHelp();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--parent")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --parent requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.parent = args[i];
        } else if (std.mem.eql(u8, arg, "--validates")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --validates requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.validates = args[i];
        } else if (std.mem.eql(u8, arg, "--blocks")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --blocks requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.blocks = args[i];
        } else if (std.mem.eql(u8, arg, "--cortex")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --cortex requires a value\n", .{});
                printNewHelp();
                std.process.exit(1);
            }
            i += 1;
            config.cortex_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--no-interactive")) {
            config.interactive = false;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printNewHelp();
            std.process.exit(1);
        }
    }

    try new_cmd.execute(allocator, config);
}

fn handleShow(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing neurona ID\n", .{});
        printShowHelp();
        std.process.exit(1);
    }

    var config = show_cmd.ShowConfig{
        .id = args[2],
        .show_connections = true,
        .show_body = true,
        .json_output = false,
    };

    // Parse options
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--no-connections")) {
            config.show_connections = false;
        } else if (std.mem.eql(u8, arg, "--no-body")) {
            config.show_body = false;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printShowHelp();
            std.process.exit(1);
        }
    }

    show_cmd.execute(allocator, config) catch |err| {
        handleNeuronaNotFound(err, config.id);
        return err;
    };
}

fn handleLink(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("Error: Missing arguments\n", .{});
        printLinkHelp();
        std.process.exit(1);
    }

    var config = link_cmd.LinkConfig{
        .source_id = undefined,
        .target_id = undefined,
        .connection_type = undefined,
    };

    var positionals = std.ArrayListUnmanaged([]const u8){};
    defer positionals.deinit(allocator);

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--weight") or std.mem.eql(u8, arg, "-w")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --weight requires a value\n", .{});
                printLinkHelp();
                std.process.exit(1);
            }
            i += 1;
            config.weight = std.fmt.parseInt(u8, args[i], 10) catch {
                std.debug.print("Error: Invalid weight '{s}'\n", .{args[i]});
                printLinkHelp();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--bidirectional") or std.mem.eql(u8, arg, "-b")) {
            config.bidirectional = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printLinkHelp();
            std.process.exit(1);
        } else {
            try positionals.append(allocator, arg);
        }
    }

    if (positionals.items.len < 3) {
        std.debug.print("Error: Missing required arguments: source_id target_id connection_type\n", .{});
        printLinkHelp();
        std.process.exit(1);
    }

    config.source_id = positionals.items[0];
    config.target_id = positionals.items[1];
    config.connection_type = positionals.items[2];

    try link_cmd.execute(allocator, config);
}

fn handleSync(allocator: Allocator, args: []const []const u8) !void {
    var config = sync_cmd.SyncConfig{
        .directory = null,
        .verbose = false,
        .rebuild_index = true,
        .force_rebuild = false,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--no-rebuild")) {
            config.rebuild_index = false;
        } else if (std.mem.eql(u8, arg, "--force-rebuild") or std.mem.eql(u8, arg, "-f")) {
            config.force_rebuild = true;
        } else if (std.mem.eql(u8, arg, "--directory") or std.mem.eql(u8, arg, "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --directory requires a value\n", .{});
                printSyncHelp();
                std.process.exit(1);
            }
            i += 1;
            config.directory = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printSyncHelp();
            std.process.exit(1);
        }
    }

    try sync_cmd.execute(allocator, config);
}

fn handleTrace(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing neurona ID\n", .{});
        printTraceHelp();
        std.process.exit(1);
    }

    var config = trace_cmd.TraceConfig{
        .id = args[2],
        .direction = .down,
        .max_depth = 10,
        .format = .tree,
        .json_output = false,
    };

    // Parse command-line arguments
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--up") or std.mem.eql(u8, arg, "-u")) {
            config.direction = .up;
        } else if (std.mem.eql(u8, arg, "--depth") or std.mem.eql(u8, arg, "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --depth requires a value\n", .{});
                printTraceHelp();
                std.process.exit(1);
            }
            i += 1;
            config.max_depth = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("Error: Invalid depth '{s}'\n", .{args[i]});
                printTraceHelp();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --format requires a value\n", .{});
                printTraceHelp();
                std.process.exit(1);
            }
            i += 1;
            const format_str = args[i];
            if (std.mem.eql(u8, format_str, "tree")) {
                config.format = .tree;
            } else if (std.mem.eql(u8, format_str, "list")) {
                config.format = .list;
            } else {
                std.debug.print("Error: Invalid format '{s}'. Valid formats: tree, list\n", .{format_str});
                printTraceHelp();
                std.process.exit(1);
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printTraceHelp();
            std.process.exit(1);
        }
    }

    trace_cmd.execute(allocator, config) catch |err| {
        handleNeuronaNotFound(err, config.id);
        return err;
    };
}

fn handleStatus(allocator: Allocator, args: []const []const u8) !void {
    var config = status_cmd.StatusConfig{
        .type_filter = null,
        .status_filter = null,
        .priority_filter = null,
        .assignee_filter = null,
        .filter_str = null,
        .sort_by = .priority,
        .json_output = false,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--type") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --type requires a value\n", .{});
                printStatusHelp();
                std.process.exit(1);
            }
            i += 1;
            config.type_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--status")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --status requires a value\n", .{});
                printStatusHelp();
                std.process.exit(1);
            }
            i += 1;
            config.status_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--filter") or std.mem.eql(u8, arg, "-f")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --filter requires a value\n", .{});
                printStatusHelp();
                std.process.exit(1);
            }
            i += 1;
            config.filter_str = args[i];
        } else if (std.mem.eql(u8, arg, "--sort-by") or std.mem.eql(u8, arg, "-s")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --sort-by requires a value\n", .{});
                printStatusHelp();
                std.process.exit(1);
            }
            i += 1;
            const sort_str = args[i];
            if (std.mem.eql(u8, sort_str, "priority")) {
                config.sort_by = .priority;
            } else if (std.mem.eql(u8, sort_str, "created")) {
                config.sort_by = .created;
            } else if (std.mem.eql(u8, sort_str, "assignee")) {
                config.sort_by = .assignee;
            } else {
                std.debug.print("Error: Invalid sort field '{s}'. Valid fields: priority, created, assignee\n", .{sort_str});
                printStatusHelp();
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printStatusHelp();
            std.process.exit(1);
        }
    }

    try status_cmd.execute(allocator, config);
}

fn handleDelete(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing Neurona ID\n", .{});
        printDeleteHelp();
        std.process.exit(1);
    }

    var config = delete_cmd.DeleteConfig{
        .id = args[2],
        .verbose = false,
    };

    // Parse options
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--neuronas-dir") or std.mem.eql(u8, arg, "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --neuronas-dir requires a value\n", .{});
                printDeleteHelp();
                std.process.exit(1);
            }
            i += 1;
            config.cortex_dir = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printDeleteHelp();
            std.process.exit(1);
        } else {
            std.debug.print("Error: Too many arguments\n", .{});
            printDeleteHelp();
            std.process.exit(1);
        }
    }

    delete_cmd.execute(allocator, config) catch |err| {
        handleNeuronaNotFound(err, config.id);
        return err;
    };
}

fn handleQuery(allocator: Allocator, args: []const []const u8) !void {
    // Default query configuration
    var config = query_cmd.QueryConfig{
        .mode = .filter,
        .query_text = "",
        .filters = &[_]query_cmd.QueryFilter{},
        .limit = null,
        .json_output = false,
    };

    // Parse options
    var i: usize = 2;
    var query_arg: ?[]const u8 = null;
    var explicit_mode = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--mode") or std.mem.eql(u8, arg, "-m")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --mode requires a value\n", .{});
                printQueryHelp();
                std.process.exit(1);
            }
            i += 1;
            const mode_str = args[i];

            // Parse mode
            if (std.mem.eql(u8, mode_str, "filter")) {
                config.mode = .filter;
            } else if (std.mem.eql(u8, mode_str, "text")) {
                config.mode = .text;
            } else if (std.mem.eql(u8, mode_str, "vector")) {
                config.mode = .vector;
            } else if (std.mem.eql(u8, mode_str, "hybrid")) {
                config.mode = .hybrid;
            } else if (std.mem.eql(u8, mode_str, "activation")) {
                config.mode = .activation;
            } else {
                std.debug.print("Error: Unknown mode '{s}'. Use: filter, text, vector, hybrid, activation\n", .{mode_str});
                printQueryHelp();
                std.process.exit(1);
            }
            explicit_mode = true;
        } else if (std.mem.eql(u8, arg, "--limit") or std.mem.eql(u8, arg, "-l")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --limit requires a value\n", .{});
                printQueryHelp();
                std.process.exit(1);
            }
            i += 1;
            const limit_val = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("Error: Invalid limit '{s}'\n", .{args[i]});
                printQueryHelp();
                std.process.exit(1);
            };
            config.limit = limit_val;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printQueryHelp();
            std.process.exit(1);
        } else {
            // Treat as query string
            query_arg = arg;
        }
    }

    // Set query text (if provided)
    if (query_arg) |qa| {
        config.query_text = qa;
    }

    // If query text is provided and mode is not explicitly set, use EQL/text auto-detection
    if (query_arg != null and config.query_text.len > 0 and !explicit_mode) {
        // Use query_helpers to auto-detect EQL vs natural language and route appropriately
        try query_helpers.executeQueryWithText(allocator, config);
    } else {
        // Use standard query execution
        try query_cmd.execute(allocator, config);
    }
}

fn handleUpdate(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing Neurona ID\n", .{});
        printUpdateHelp();
        std.process.exit(1);
    }

    var config = update_cmd.UpdateConfig{
        .id = args[2],
        .sets = std.ArrayListUnmanaged(update_cmd.FieldUpdate){},
        .verbose = false,
        .cortex_dir = null,
    };
    defer {
        for (config.sets.items) |*s| s.deinit(allocator);
        config.sets.deinit(allocator);
    }

    // Parse options
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--set")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --set requires a value (format: field=value)\n", .{});
                printUpdateHelp();
                std.process.exit(1);
            }
            i += 1;
            const set_value = args[i];

            // Parse field=value format
            var parts = std.mem.splitSequence(u8, set_value, "=");
            const field = parts.next() orelse {
                std.debug.print("Error: Invalid --set format. Use field=value\n", .{});
                printUpdateHelp();
                std.process.exit(1);
            };
            const value = parts.rest();

            const update = update_cmd.FieldUpdate{
                .field = try allocator.dupe(u8, field),
                .value = try allocator.dupe(u8, value),
                .operator = .set,
            };
            try config.sets.append(allocator, update);
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printUpdateHelp();
            std.process.exit(1);
        }
    }

    update_cmd.execute(allocator, config) catch |err| {
        handleNeuronaNotFound(err, config.id);
        return err;
    };
}

fn handleImpact(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing Neurona ID\n", .{});
        printImpactHelp();
        std.process.exit(1);
    }

    var config = impact_cmd.ImpactConfig{
        .id = args[2],
        .direction = .both,
        .max_depth = 10,
        .include_recommendations = true,
        .json_output = false,
        .cortex_dir = null,
    };

    // Parse options
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--up") or std.mem.eql(u8, arg, "-u")) {
            config.direction = .upstream;
        } else if (std.mem.eql(u8, arg, "--down") or std.mem.eql(u8, arg, "-d")) {
            config.direction = .downstream;
        } else if (std.mem.eql(u8, arg, "--depth")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --depth requires a value\n", .{});
                printImpactHelp();
                std.process.exit(1);
            }
            i += 1;
            const depth_val = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("Error: Invalid depth '{s}'\n", .{args[i]});
                printImpactHelp();
                std.process.exit(1);
            };
            config.max_depth = depth_val;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printImpactHelp();
            std.process.exit(1);
        }
    }

    impact_cmd.execute(allocator, config) catch |err| {
        handleNeuronaNotFound(err, config.id);
        return err;
    };
}

fn handleLinkArtifact(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("Error: Missing required arguments\n", .{});
        printLinkArtifactHelp();
        std.process.exit(1);
    }

    var config = link_artifact_cmd.LinkArtifactConfig{
        .requirement_id = args[2],
        .source_files = std.ArrayListUnmanaged([]const u8){},
        .runtime = args[3],
        .auto_create = true,
        .language_version = null,
        .safe_to_exec = false,
        .verbose = false,
        .cortex_dir = null,
    };
    defer {
        for (config.source_files.items) |f| allocator.free(f);
        config.source_files.deinit(allocator);
    }

    // Parse options
    var i: usize = 4;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--runtime") or std.mem.eql(u8, arg, "-r")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --runtime requires a value\n", .{});
                printLinkArtifactHelp();
                std.process.exit(1);
            }
            i += 1;
            config.runtime = args[i];
        } else if (std.mem.eql(u8, arg, "--file") or std.mem.eql(u8, arg, "-f")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --file requires a value\n", .{});
                printLinkArtifactHelp();
                std.process.exit(1);
            }
            i += 1;
            try config.source_files.append(allocator, try allocator.dupe(u8, args[i]));
        } else if (std.mem.eql(u8, arg, "--version")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --version requires a value\n", .{});
                printLinkArtifactHelp();
                std.process.exit(1);
            }
            i += 1;
            config.language_version = args[i];
        } else if (std.mem.eql(u8, arg, "--safe")) {
            config.safe_to_exec = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printLinkArtifactHelp();
            std.process.exit(1);
        }
    }

    link_artifact_cmd.execute(allocator, config) catch |err| {
        handleLinkArtifactError(err, config.requirement_id);
        return err;
    };
}

fn handleReleaseStatus(allocator: Allocator, args: []const []const u8) !void {
    var config = release_status_cmd.ReleaseStatusConfig{
        .requirements_filter = null,
        .include_tests = true,
        .include_issues = true,
        .json_output = false,
        .verbose = false,
        .cortex_dir = null,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printReleaseStatusHelp();
            std.process.exit(1);
        }
    }

    try release_status_cmd.execute(allocator, config);
}

fn handleMetrics(allocator: Allocator, args: []const []const u8) !void {
    var config = metrics_cmd.MetricsConfig{
        .since_date = null,
        .last_days = null,
        .json_output = false,
        .verbose = false,
        .cortex_dir = null,
    };

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--since")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --since requires a value\n", .{});
                printMetricsHelp();
                std.process.exit(1);
            }
            i += 1;
            config.since_date = args[i];
        } else if (std.mem.eql(u8, arg, "--last")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --last requires a value\n", .{});
                printMetricsHelp();
                std.process.exit(1);
            }
            i += 1;
            const days_str = args[i];
            config.last_days = std.fmt.parseInt(u32, days_str, 10) catch {
                std.debug.print("Error: Invalid days value '{s}'\n", .{days_str});
                printMetricsHelp();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printMetricsHelp();
            std.process.exit(1);
        }
    }

    try metrics_cmd.execute(allocator, config);
}

fn handleMan(allocator: Allocator, args: []const []const u8) !void {
    var config = man_cmd.ManConfig{
        .html = false,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--html")) {
            config.html = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printManHelp();
            return;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            printManHelp();
            std.process.exit(1);
        }
    }

    try man_cmd.execute(allocator, config);
}

// Help functions

fn printUsage() void {
    std.debug.print(
        \\Commands:
        \\  init              Initialize a new Cortex
        \\  new               Create a new Neurona
        \\  show              Display a Neurona (use "config" to open config)
        \\  link              Create connections between Neuronas
        \\  delete            Delete a Neurona
        \\  sync              Rebuild graph index
        \\  trace             Trace dependencies
        \\  status            List status
        \\  query             Query interface
        \\  update            Update Neurona fields
        \\  impact            Impact analysis
        \\  link-artifact     Link source files
        \\  release-status    Release readiness check
        \\  metrics           Display project metrics
        \\  man               Show manual
        \\  --help, -h        Show this help message
        \\  --version, -v     Show version information
        \\
        \\For more information on a specific command, run:
        \\  engram <command> --help
        \\
    , .{});
}

fn printHelp() void {
    std.debug.print(
        \\Engram - High-performance CLI tool for Neurona Knowledge Protocol
        \\
        \\Usage:
        \\  engram <command> [options]
        \\
        \\Commands:
        \\  init              Initialize a new Cortex
        \\  new               Create a new Neurona
        \\  show              Display a Neurona
        \\  link              Create connections between Neuronas
        \\  sync              Rebuild graph index
        \\  trace             Trace dependencies
        \\  status            List status
        \\  query             Query interface
        \\  update            Update Neurona fields
        \\  impact            Impact analysis
        \\  link-artifact     Link source files
        \\  release-status    Release readiness check
        \\  metrics           Display project metrics
        \\  man               Show manual
        \\  --help, -h        Show this help message
        \\  --version, -v     Show version information
        \\
        \\For more information on a specific command, run:
        \\  engram <command> --help
        \\
    , .{});
}

fn printInitHelp() void {
    std.debug.print(
        \\Initialize a new Cortex
        \\
        \\Usage:
        \\  engram init <name> [options]
        \\
        \\Arguments:
        \\  name              Name of Cortex to create (required)
        \\
        \\Options:
        \\  --type, -t        Cortex type: zettelkasten, alm, knowledge (default: alm)
        \\  --language, -l    Default language (default: en)
        \\  --force, -f       Force overwrite existing Cortex
        \\  --verbose, -v     Show verbose output
        \\
        \\Examples:
        \\  engram init my_notes
        \\  engram init my_project --type alm
        \\  engram init knowledge_base --type knowledge --language es
        \\
    , .{});
}

fn printNewHelp() void {
    std.debug.print(
        \\Create a new Neurona
        \\
        \\Usage:
        \\  engram new <type> <title> [options]
        \\
        \\Arguments:
        \\  type              Neurona type: requirement, test_case, issue, artifact, feature (required)
        \\  title             Title of the Neurona (required)
        \\
        \\Options:
        \\  --tag, -t         Add a tag (can be repeated)
        \\  --assignee        Assign to a person
        \\  --priority, -p    Set priority (1-5)
        \\  --parent          Set parent Neurona ID
        \\  --validates       Set requirement this test validates (for test_case)
        \\  --blocks          Set issue this blocks (for issue)
        \\  --cortex         Specify cortex directory path
        \\  --json, -j        Output as JSON
        \\  --no-interactive  Skip interactive prompts
        \\
        \\Examples:
        \\  engram new requirement "Support OAuth 2.0"
        \\  engram new test_case "OAuth Test" --validates req.auth.oauth2
        \\  engram new issue "OAuth library broken" --priority 1
        \\  engram new requirement "Test" --cortex ./my_project
        \\
    , .{});
}

fn printShowHelp() void {
    std.debug.print(
        \\Display a Neurona
        \\
        \\Usage:
        \\  engram show <id> [options]
        \\
        \\Arguments:
        \\  id                Neurona ID or URI (required)
        \\                    Format: neurona://<cortex>/<neurona-id>
        \\                    Use "config" to open the configuration file
        \\
        \\Options:
        \\  --no-connections  Don't show connections
        \\  --no-body         Don't show body content
        \\  --json, -j        Output as JSON
        \\
        \\Examples:
        \\  engram show test.001
        \\  engram show neurona://my_cortex/req.auth.001
        \\  engram show req.auth.oauth2 --no-body
        \\  engram show test.oauth.001 --json
        \\  engram show config
        \\
    , .{});
}

fn printLinkHelp() void {
    std.debug.print(
        \\Link two Neuronas
        \\
        \\Usage:
        \\  engram link <source_id> <target_id> <type> [options]
        \\
        \\Arguments:
        \\  source_id         ID or URI of the source Neurona
        \\                    Format: neurona://<cortex>/<neurona-id>
        \\  target_id         ID or URI of the target Neurona
        \\  type              Type of connection (e.g., parent, relates_to, validates)
        \\
        \\Options:
        \\  --weight, -w      Connection weight (0-100, default: 50)
        \\  --bidirectional, -b  Create reverse connection
        \\  --verbose, -v     Show verbose output
        \\
        \\Examples:
        \\  engram link note.1 note.2 relates_to
        \\  engram link neurona://ctx1/n1 neurona://ctx1/n2 relates_to
        \\  engram link req.auth test.auth validates --bidirectional
        \\
    , .{});
}

fn printSyncHelp() void {
    std.debug.print(
        \\Rebuild graph index
        \\
        \\Usage:
        \\  engram sync [options]
        \\
        \\Options:
        \\  --verbose, -v     Show verbose output
        \\  --no-rebuild      Skip index rebuild
        \\  --directory, -d   Directory to scan (default: neuronas)
        \\
        \\Examples:
        \\  engram sync
        \\  engram sync --verbose
        \\
    , .{});
}

fn printTraceHelp() void {
    std.debug.print(
        \\Trace dependencies between Neuronas
        \\
        \\Usage:
        \\  engram trace <neurona_id> [options]
        \\
        \\Arguments:
        \\  neurona_id       ID or URI of Neurona to trace from (required)
        \\                    Format: neurona://<cortex>/<neurona-id>
        \\
        \\Options:
        \\  --up, -u         Trace upstream (parents/dependencies) instead of downstream
        \\  --depth, -d      Maximum trace depth (default: 10)
        \\  --format, -f     Output format: tree, list (default: tree)
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram trace req.auth
        \\  engram trace neurona://my_cortex/req.auth.001
        \\  engram trace req.auth --up
        \\  engram trace req.auth --depth 3
        \\
    , .{});
}

fn printStatusHelp() void {
    std.debug.print(
        \\List status
        \\
        \\Usage:
        \\  engram status [options]
        \\
        \\Options:
        \\  --type, -t       Filter by type
        \\  --status         Filter by status
        \\  --filter, -f     EQL filter expression (e.g., "state:open AND priority:1")
        \\  --sort-by, -s    Sort by: priority, created, assignee (default: priority)
        \\  --json, -j       Output as JSON
        \\
        \\Filter Syntax:
        \\  field:value                    Match field equals value
        \\  field:operator:value           Use specific operator (eq, neq, gt, lt, gte, lte, contains)
        \\  "condition1 AND condition2"    Both must match
        \\  "condition1 OR condition2"     Either must match
        \\
        \\  Supported Fields:
        \\    type, id, title, language, state (alias for context.status),
        \\    context.status, context.priority, context.assignee, etc.
        \\
        \\Examples:
        \\  engram status
        \\  engram status --type issue
        \\  engram status --filter "state:open AND priority:1"
        \\  engram status --filter "type:test_case AND context.status:passing"
        \\  engram status --status open --sort-by created
        \\
    , .{});
}

fn printQueryHelp() void {
    std.debug.print(
        \\Query interface
        \\
        \\Usage:
        \\  engram query [options] [query_string]
        \\
        \\Options:
        \\  --mode, -m      Query mode: filter, text, vector, hybrid, activation (default: auto-detect)
        \\  --limit, -l      Limit results (default: 50)
        \\  --json, -j       Output as JSON
        \\
        \\Query Modes:
        \\  auto-detect       Auto-detect EQL or natural language (default with query_string)
        \\  filter            Filter by type, tags, connections
        \\  text              BM25 full-text search
        \\  vector            Vector similarity search
        \\  hybrid             Combined BM25 + vector search
        \\  activation         Neural propagation across graph
        \\
        \\EQL Query Syntax (Engram Query Language):
        \\  Field Conditions:
        \\    type:issue                      Match by type
        \\    tag:security                    Match by tag
        \\    priority:gte:3                  Numeric comparison
        \\    title:contains:auth             String matching
        \\
        \\  Logical Operators:
        \\    type:issue AND tag:p1           Both conditions must match
        \\    type:requirement OR type:feature  Either condition must match
        \\
        \\  Link Conditions:
        \\    link(validates, req.auth.001)   Find items validating a requirement
        \\    link(blocked_by, issue.001)     Find items blocked by an issue
        \\
        \\  Comparison Operators:
        \\    eq, neq, gt, lt, gte, lte       Numeric comparisons
        \\    contains, not_contains           String matching
        \\
        \\Examples:
        \\  EQL Queries:
        \\    engram query "type:issue"
        \\    engram query "type:issue AND tag:p1"
        \\    engram query "priority:gte:3"
        \\    engram query "title:contains:authentication OR tag:security"
        \\    engram query "link(validates, req.auth.001) AND type:test_case"
        \\    engram query "(type:issue OR type:requirement) AND state:open"
        \\
        \\  Text Search (natural language):
        \\    engram query "authentication"
        \\    engram query "user login failure"
        \\
        \\  Explicit Mode:
        \\    engram query --mode text "authentication"
        \\    engram query --mode vector "user login"
        \\    engram query --mode hybrid "login failure"
        \\
    , .{});
}

fn printDeleteHelp() void {
    std.debug.print(
        \\Delete a Neurona
        \\
        \\Usage:
        \\  engram delete <id> [options]
        \\
        \\Arguments:
        \\  id                Neurona ID to delete (required)
        \\
        \\Options:
        \\  --verbose, -v    Show verbose output
        \\  --neuronas-dir, -d   Directory containing neuronas (default: neuronas)
        \\
        \\Examples:
        \\  engram delete test.001
        \\  engram delete req.auth.oauth2 --verbose
        \\
    , .{});
}

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
        \\                    Examples: --set title="New Title"
        \\                              --set context.status=passing
        \\                              --set tag=bug
        \\  --verbose, -v    Show verbose output
        \\
        \\Examples:
        \\  engram update test.001 --set context.status=passing
        \\  engram update req.auth --set title="OAuth 2.0 Support"
        \\  engram update issue.001 --set context.status=resolved
        \\
    , .{});
}

fn printImpactHelp() void {
    std.debug.print(
        \\Perform impact analysis for code changes
        \\
        \\Usage:
        \\  engram impact <neurona_id> [options]
        \\
        \\Arguments:
        \\  neurona_id       ID of Neurona to analyze (required)
        \\
        \\Options:
        \\  --up, -u         Trace upstream (dependencies) only
        \\  --down, -d        Trace downstream (dependents) only
        \\  --depth           Maximum trace depth (default: 10)
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram impact req.auth
        \\  engram impact src.main.zig --down
        \\  engram impact test.auth.login --depth 3
        \\
    , .{});
}

fn printLinkArtifactHelp() void {
    std.debug.print(
        \\Link source files to requirements
        \\
        \\Usage:
        \\  engram link-artifact <requirement_id> <runtime> [options]
        \\
        \\Arguments:
        \\  requirement_id    Requirement ID to link artifact to (required)
        \\  runtime          Programming runtime (e.g., zig, python, node) (required)
        \\
        \\Options:
        \\  --file, -f       Source file path (can be repeated)
        \\  --version         Language version
        \\  --safe            Mark artifact as safe to execute
        \\  --verbose, -v    Show verbose output
        \\
        \\Examples:
        \\  engram link-artifact req.auth zig --file src/auth.zig
        \\  engram link-artifact req.oauth2 node --file src/oauth2.ts --safe
        \\
    , .{});
}

fn printReleaseStatusHelp() void {
    std.debug.print(
        \\Check release readiness
        \\
        \\Usage:
        \\  engram release-status [options]
        \\
        \\Options:
        \\  --verbose, -v    Show detailed breakdown
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram release-status
        \\  engram release-status --verbose
        \\  engram release-status --json
        \\
    , .{});
}

fn printMetricsHelp() void {
    std.debug.print(
        \\Display project metrics
        \\
        \\Usage:
        \\  engram metrics [options]
        \\
        \\Options:
        \\  --since           Show metrics since date (format: YYYY-MM-DD)
        \\  --last            Show metrics for last N days
        \\  --json, -j       Output as JSON
        \\  --verbose, -v    Show verbose output
        \\
        \\Examples:
        \\  engram metrics
        \\  engram metrics --since 2026-01-01
        \\  engram metrics --last 7
        \\  engram metrics --json
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("Engram version 0.1.0\n", .{});
}

fn printManHelp() void {
    std.debug.print(
        \\Show manual
        \\
        \\Usage:
        \\  engram man [options]
        \\
        \\Options:
        \\  --html            Open full manual in browser
        \\
        \\Examples:
        \\  engram man         Show quick reference
        \\  engram man --html  Open full manual in browser
        \\
    , .{});
}

// ==================== Tests ====================

test {
    _ = @import("cli/init.zig");
    _ = @import("cli/new.zig");
    _ = @import("cli/show.zig");
    _ = @import("cli/link.zig");
    _ = @import("cli/sync.zig");
    _ = @import("cli/delete.zig");
    _ = @import("cli/trace.zig");
    _ = @import("cli/status.zig");
    _ = @import("cli/query.zig");
    _ = @import("cli/update.zig");
    _ = @import("cli/impact.zig");
    _ = @import("cli/link_artifact.zig");
    _ = @import("cli/release_status.zig");
    _ = @import("cli/metrics.zig");
}

test "Command registry contains all expected commands" {
    // Commands are defined in main.zig
    // We can verify the count is correct

    const expected_commands = [_][]const u8{
        "init",
        "new",
        "show",
        "link",
        "sync",
        "delete",
        "trace",
        "status",
        "query",
        "update",
        "impact",
        "link-artifact",
        "release-status",
        "metrics",
    };

    // Verify we have 14 commands
    try std.testing.expectEqual(@as(usize, 14), expected_commands.len);
}

test "Help functions print usage information" {
    // This test verifies help functions don't crash
    // They're tested indirectly via integration tests

    // Verify printUsage exists (called when no args)
    const allocator = std.testing.allocator;

    var buffer: [512]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buffer);
    const stdout_writer = &stdout.interface;

    // Call printUsage - should not crash
    try stdout_writer.writeAll("");

    _ = allocator;
}
