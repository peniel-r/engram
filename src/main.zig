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

// Command handlers

fn handleInit(allocator: Allocator, args: []const []const u8) !void {
    var name: ?[]const u8 = null;

    var config = init_cmd.InitConfig{
        .name = undefined,
        .cortex_type = .zettelkasten,
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

    try show_cmd.execute(allocator, config);
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
        .directory = "neuronas",
        .verbose = false,
        .rebuild_index = true,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--no-rebuild")) {
            config.rebuild_index = false;
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

    try trace_cmd.execute(allocator, config);
}

fn handleStatus(allocator: Allocator, args: []const []const u8) !void {
    var config = status_cmd.StatusConfig{
        .type_filter = null,
        .status_filter = null,
        .priority_filter = null,
        .assignee_filter = null,
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
            config.neuronas_dir = args[i];
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

    try delete_cmd.execute(allocator, config);
}

fn handleQuery(allocator: Allocator, args: []const []const u8) !void {
    // Simple query implementation
    var config = query_cmd.QueryConfig{
        .filters = &[_]query_cmd.QueryFilter{},
        .limit = null,
        .json_output = false,
    };

    // Parse options
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--type") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --type requires a value\n", .{});
                printQueryHelp();
                std.process.exit(1);
            }
            i += 1;
            _ = args[i]; // Would build filter in full implementation
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
        }
    }

    try query_cmd.execute(allocator, config);
}

// Help functions

fn printUsage() void {
    std.debug.print(
        \\Commands:
        \\  init              Initialize a new Cortex
        \\  new               Create a new Neurona
        \\  show              Display a Neurona
        \\  link              Create connections between Neuronas
        \\  delete            Delete a Neurona
        \\  sync              Rebuild graph index
        \\  trace             Trace dependencies
        \\  status            List status
        \\  query             Query interface
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
        \\  --type, -t        Cortex type: zettelkasten, alm, knowledge (default: zettelkasten)
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
        \\  --json, -j        Output as JSON
        \\  --no-interactive  Skip interactive prompts
        \\
        \\Examples:
        \\  engram new requirement "Support OAuth 2.0"
        \\  engram new test_case "OAuth Test" --validates req.auth.oauth2
        \\  engram new issue "OAuth library broken" --priority 1
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
        \\  id                Neurona ID (required)
        \\
        \\Options:
        \\  --no-connections  Don't show connections
        \\  --no-body         Don't show body content
        \\  --json, -j        Output as JSON
        \\
        \\Examples:
        \\  engram show test.001
        \\  engram show req.auth.oauth2 --no-body
        \\  engram show test.oauth.001 --json
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
        \\  source_id         ID of the source Neurona
        \\  target_id         ID of the target Neurona
        \\  type              Type of connection (e.g., parent, relates_to, validates)
        \\
        \\Options:
        \\  --weight, -w      Connection weight (0-100, default: 50)
        \\  --bidirectional, -b  Create reverse connection
        \\  --verbose, -v     Show verbose output
        \\
        \\Examples:
        \\  engram link note.1 note.2 relates_to
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
        \\  neurona_id       ID of Neurona to trace from (required)
        \\
        \\Options:
        \\  --up, -u         Trace upstream (parents/dependencies) instead of downstream
        \\  --depth, -d      Maximum trace depth (default: 10)
        \\  --format, -f     Output format: tree, list (default: tree)
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram trace req.auth
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
        \\  --sort-by, -s    Sort by: priority, created, assignee (default: priority)
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram status
        \\  engram status --type issue
        \\  engram status --status open --sort-by created
        \\
    , .{});
}

fn printQueryHelp() void {
    std.debug.print(
        \\Query interface
        \\
        \\Usage:
        \\  engram query [options]
        \\
        \\Options:
        \\  --type, -t       Filter by type
        \\  --limit, -l      Limit results (default: unlimited)
        \\  --json, -j       Output as JSON
        \\
        \\Examples:
        \\  engram query
        \\  engram query --type issue --limit 10
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

fn printVersion() void {
    std.debug.print("Engram version 0.1.0\n", .{});
}
