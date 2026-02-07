// File: src/utils/error_reporter.zig
// Unified error reporting for CLI commands

const std = @import("std");

/// Unified error reporting for CLI commands
pub const ErrorReporter = struct {
    /// Report not found error with context
    pub fn notFound(resource_type: []const u8, id: []const u8) void {
        std.debug.print("Error: {s} '{s}' not found\n", .{ resource_type, id });
        std.debug.print("\nHint: Check spelling or use 'engram list' to see available {s}s\n", .{resource_type});
    }

    /// Report not found error with custom command
    pub fn notFoundWithCommand(resource_type: []const u8, id: []const u8, command: []const u8) void {
        std.debug.print("Error: {s} '{s}' not found\n", .{ resource_type, id });
        std.debug.print("\nHint: Run 'engram {s}' to see available {s}s\n", .{ command, resource_type });
    }

    /// Report Neurona not found error
    pub fn neuronaNotFound(id: []const u8) void {
        notFound("Neurona", id);
    }

    /// Report Cortex not found error
    pub fn cortexNotFound() void {
        std.debug.print("Error: No cortex found in current directory or within 3 directory levels.\n", .{});
        std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
        std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
    }

    /// Report validation error
    pub fn validation(field: []const u8, value: []const u8, error_type: []const u8) void {
        std.debug.print("Error: Invalid {s}: {s}\n", .{ field, value });
        std.debug.print("Expected: {s}\n", .{error_type});
    }

    /// Report missing argument
    pub fn missingArgument(arg: []const u8) void {
        std.debug.print("Error: Missing required argument: '{s}'\n", .{arg});
    }

    /// Report unknown flag
    pub fn unknownFlag(flag: []const u8, command: []const u8) void {
        std.debug.print("Error: Unknown flag '{s}' for command '{s}'\n", .{ flag, command });
        std.debug.print("Use '{s} --help' for more information\n", .{command});
    }

    /// Report invalid connection type
    pub fn invalidConnectionType(connection_type: []const u8) void {
        std.debug.print("Error: Invalid connection type '{s}'.\n", .{connection_type});
        std.debug.print("\nValid types: validates, blocks, references, related_to, depends_on\n", .{});
    }

    /// Report invalid neurona type
    pub fn invalidNeuronaType(neurona_type: []const u8) void {
        std.debug.print("Error: Invalid neurona type '{s}'.\n", .{neurona_type});
        std.debug.print("\nValid types: requirement, test_case, issue, concept, decision\n", .{});
    }

    /// Report that a resource must be a specific type
    pub fn mustBeType(resource: []const u8, expected_type: []const u8) void {
        std.debug.print("Error: '{s}' is not a {s}\n", .{ resource, expected_type });
    }

    /// Report missing file or directory
    pub fn fileNotFound(path: []const u8) void {
        std.debug.print("Error: File or directory not found: {s}\n", .{path});
    }

    /// Report query string required error
    pub fn queryStringRequired(search_type: []const u8) void {
        std.debug.print("Error: {s} search requires a query string\n", .{search_type});
        std.debug.print("\nUsage: engram query \"<query>\"\n", .{});
    }

    /// Report GloVe cache not found
    pub fn gloVeCacheNotFound(path: []const u8) void {
        std.debug.print("Error: GloVe cache not found at {s}\n", .{path});
        std.debug.print("\nNote: Run 'engram sync' to build the index\n", .{});
    }

    /// Report success message
    pub fn success(action: []const u8, resource: []const u8) void {
        std.debug.print("Successfully {s} {s}.\n", .{ action, resource });
    }

    /// Report generic error with details
    pub fn genericError(message: []const u8) void {
        std.debug.print("Error: {s}\n", .{message});
    }

    /// Report warning message
    pub fn warning(message: []const u8) void {
        std.debug.print("Warning: {s}\n", .{message});
    }

    /// Report info message
    pub fn info(message: []const u8) void {
        std.debug.print("Info: {s}\n", .{message});
    }
};

// Tests
test "ErrorReporter - notFound" {
    // Should print formatted error message
    ErrorReporter.notFound("Neurona", "req.001");
}

test "ErrorReporter - notFoundWithCommand" {
    // Should print formatted error with command hint
    ErrorReporter.notFoundWithCommand("Neurona", "req.001", "status");
}

test "ErrorReporter - neuronaNotFound" {
    // Should use generic notFound
    ErrorReporter.neuronaNotFound("req.001");
}

test "ErrorReporter - cortexNotFound" {
    // Should print cortex-specific error
    ErrorReporter.cortexNotFound();
}

test "ErrorReporter - validation" {
    // Should print validation error
    ErrorReporter.validation("priority", "high", "number 1-5");
}

test "ErrorReporter - missingArgument" {
    // Should print missing argument error
    ErrorReporter.missingArgument("--output");
}

test "ErrorReporter - unknownFlag" {
    // Should print unknown flag error
    ErrorReporter.unknownFlag("--unknown", "show");
}

test "ErrorReporter - invalidConnectionType" {
    // Should print invalid connection type error
    ErrorReporter.invalidConnectionType("invalid_type");
}

test "ErrorReporter - invalidNeuronaType" {
    // Should print invalid neurona type error
    ErrorReporter.invalidNeuronaType("invalid_type");
}

test "ErrorReporter - mustBeType" {
    // Should print type check error
    ErrorReporter.mustBeType("req.001", "requirement");
}

test "ErrorReporter - fileNotFound" {
    // Should print file not found error
    ErrorReporter.fileNotFound("/path/to/file");
}

test "ErrorReporter - queryStringRequired" {
    // Should print query string required error
    ErrorReporter.queryStringRequired("Text");
}

test "ErrorReporter - gloVeCacheNotFound" {
    // Should print GloVe cache error
    ErrorReporter.gloVeCacheNotFound("/path/to/cache");
}

test "ErrorReporter - success" {
    // Should print success message
    ErrorReporter.success("deleted", "Neurona 'req.001'");
}

test "ErrorReporter - warning" {
    // Should print warning message
    ErrorReporter.warning("This is a warning");
}

test "ErrorReporter - info" {
    // Should print info message
    ErrorReporter.info("This is info");
}

test "ErrorReporter - genericError" {
    // Should print generic error
    ErrorReporter.genericError("Something went wrong");
}
