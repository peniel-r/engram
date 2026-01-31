const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const ManConfig = struct {
    html: bool = false,
};

pub fn execute(allocator: Allocator, config: ManConfig) !void {
    _ = allocator;

    if (config.html) {
        try launchManualHtml();
    } else {
        try showManual();
    }
}

fn showManual() !void {
    std.debug.print("\n{s}\n\n", .{"========================================================="});
    std.debug.print("{s}{s}{s}\n", .{ "En", "gr", "am" });
    std.debug.print("High-performance CLI tool for Neurona Knowledge Protocol\n", .{});
    std.debug.print("{s}\n\n", .{"========================================================="});

    std.debug.print("QUICK REFERENCE:\n", .{});
    std.debug.print("{s}\n\n", .{"--------------"});

    std.debug.print("  {s:20} {s}\n", .{ "init", "Initialize a new Cortex" });
    std.debug.print("  {s:20} {s}\n", .{ "new", "Create a new Neurona" });
    std.debug.print("  {s:20} {s}\n", .{ "show", "Display a Neurona" });
    std.debug.print("  {s:20} {s}\n", .{ "link", "Create connections" });
    std.debug.print("  {s:20} {s}\n", .{ "sync", "Rebuild graph index" });
    std.debug.print("  {s:20} {s}\n", .{ "trace", "Trace dependencies" });
    std.debug.print("  {s:20} {s}\n", .{ "status", "List status" });
    std.debug.print("  {s:20} {s}\n", .{ "query", "Query interface" });
    std.debug.print("  {s:20} {s}\n", .{ "update", "Update Neurona fields" });
    std.debug.print("  {s:20} {s}\n", .{ "impact", "Impact analysis" });
    std.debug.print("  {s:20} {s}\n", .{ "link-artifact", "Link source files" });
    std.debug.print("  {s:20} {s}\n", .{ "release-status", "Release readiness" });
    std.debug.print("  {s:20} {s}\n", .{ "metrics", "Display project metrics" });
    std.debug.print("  {s:20} {s}\n", .{ "man --html", "Open full manual in browser" });

    std.debug.print("\nGETTING STARTED:\n", .{});
    std.debug.print("{s}\n", .{"----------------"});
    std.debug.print("  engram init my_project --type alm\n", .{});
    std.debug.print("  engram new requirement \"User Login\"\n", .{});
    std.debug.print("  engram new test_case \"Login Test\" --validates req.user-login\n", .{});
    std.debug.print("  engram status\n", .{});

    std.debug.print("\nFOR MORE DETAILS:\n", .{});
    std.debug.print("{s}\n", .{"----------------"});
    std.debug.print("  engram man --html    # Open full manual in browser\n", .{});
    std.debug.print("  engram <cmd> --help  # Get help on specific command\n", .{});
    std.debug.print("\n", .{});
}

fn launchManualHtml() !void {
    // Get the executable path and resolve to the script directory
    const self_exe_path = try std.fs.selfExePathAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(self_exe_path);

    const exe_dir = std.fs.path.dirname(self_exe_path) orelse ".";

    // Script is in the same directory as the executable (for production use in C:\bin)
    // Or two directories up + scripts/ (for development use)
    const script_name = if (builtin.os.tag == .windows) "launch-manual.ps1" else "launch-manual.sh";

    // First try to same directory (production - C:\bin\launch-manual.ps1)
    var script_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ exe_dir, script_name });
    defer std.heap.page_allocator.free(script_path);

    // If not found in exe_dir, try two directories up + scripts (development)
    if (std.fs.cwd().openFile(script_path, .{})) |_| {
        // File exists in exe_dir, use it
    } else |_| {
        // Try development path: zig-out/bin -> .. -> .. -> scripts/
        script_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ exe_dir, "..", "..", "scripts", script_name });
        defer std.heap.page_allocator.free(script_path);
    }

    std.debug.print("Launching manual in browser...\n", .{});
    std.debug.print("Script path: {s}\n", .{script_path});

    // Execute the appropriate script
    if (builtin.os.tag == .windows) {
        // Windows - use PowerShell
        const argv = &[_][]const u8{ "powershell", "-ExecutionPolicy", "Bypass", "-File", script_path };
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = argv,
        }) catch |err| {
            std.debug.print("Error launching manual: {}\n", .{err});
            return err;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);

        // Wait for completion
        _ = result.term;
    } else {
        // Unix-like - use bash
        const argv = &[_][]const u8{ "bash", script_path };
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = argv,
        }) catch |err| {
            std.debug.print("Error launching manual: {}\n", .{err});
            return err;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);

        // Wait for completion
        _ = result.term;
    }
}
