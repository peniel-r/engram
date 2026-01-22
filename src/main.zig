const std = @import("std");
const Allocator = std.mem.Allocator;
const init_cmd = @import("cli/init.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check if we have enough arguments
    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    // Route to appropriate command
    if (std.mem.eql(u8, command, "init")) {
        try handleInit(allocator, args);
    } else if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printHelp();
    } else if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

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
                std.process.exit(1);
            }
            i += 1;
            const type_str = args[i];
            const cortex_type = init_cmd.CortexType.fromString(type_str);
            if (cortex_type == null) {
                std.debug.print("Error: Invalid cortex type '{s}'. Valid types: zettelkasten, alm, knowledge\n", .{type_str});
                std.process.exit(1);
            }
            config.cortex_type = cortex_type.?;
        } else if (std.mem.eql(u8, arg, "--language") or std.mem.eql(u8, arg, "-l")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --language requires a value\n", .{});
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

    // Execute init command
    try init_cmd.execute(allocator, config);
}

fn printUsage() void {
    std.debug.print(
        \\Engram - High-performance CLI tool for Neurona Knowledge Protocol
        \\
        \\Usage:
        \\  engram <command> [options]
        \\
        \\Commands:
        \\  init              Initialize a new Cortex
        \\  --help, -h        Show this help message
        \\  --version, -v     Show version information
        \\
        \\Run 'engram init --help' for more information on init command.
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
        \\  engram init my_cortex --verbose
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("Engram version 0.1.0\n", .{});
}
