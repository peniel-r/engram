const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// Import Phase 3 CLI utilities
const HumanOutput = @import("output/human.zig").HumanOutput;

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
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("\n{s}\n\n", .{"========================================================="});
    try stdout.print("{s}{s}{s}\n", .{ "En", "gr", "am" });
    try stdout.print("High-performance CLI tool for Neurona Knowledge Protocol\n", .{});
    try stdout.print("{s}\n\n", .{"========================================================="});

    try stdout.print("QUICK REFERENCE:\n", .{});
    try stdout.print("{s}\n\n", .{"--------------"});

    try stdout.print("  {s:20} {s}\n", .{ "init", "Initialize a new Cortex" });
    try stdout.print("  {s:20} {s}\n", .{ "new", "Create a new Neurona" });
    try stdout.print("  {s:20} {s}\n", .{ "show", "Display a Neurona" });
    try stdout.print("  {s:20} {s}\n", .{ "link", "Create connections" });
    try stdout.print("  {s:20} {s}\n", .{ "sync", "Rebuild graph index" });
    try stdout.print("  {s:20} {s}\n", .{ "trace", "Trace dependencies" });
    try stdout.print("  {s:20} {s}\n", .{ "status", "List status" });
    try stdout.print("  {s:20} {s}\n", .{ "query", "Query interface" });
    try stdout.print("  {s:20} {s}\n", .{ "update", "Update Neurona fields" });
    try stdout.print("  {s:20} {s}\n", .{ "impact", "Impact analysis" });
    try stdout.print("  {s:20} {s}\n", .{ "link-artifact", "Link source files" });
    try stdout.print("  {s:20} {s}\n", .{ "release-status", "Release readiness" });
    try stdout.print("  {s:20} {s}\n", .{ "metrics", "Display project metrics" });
    try stdout.print("  {s:20} {s}\n", .{ "man --html", "Open full manual in browser" });

    try stdout.print("\nGETTING STARTED:\n", .{});
    try stdout.print("{s}\n", .{"----------------"});
    try stdout.print("  engram init my_project --type alm\n", .{});
    try stdout.print("  engram new requirement \"User Login\"\n", .{});
    try stdout.print("  engram new test_case \"Login Test\" --validates req.user-login\n", .{});
    try stdout.print("  engram status\n", .{});

    try stdout.print("\nFOR MORE DETAILS:\n", .{});
    try stdout.print("{s}\n", .{"----------------"});
    try stdout.print("  engram man --html    # Open full manual in browser\n", .{});
    try stdout.print("  engram <cmd> --help  # Get help on specific command\n", .{});
    try stdout.print("\n", .{});
    try stdout.flush();
}

fn launchManualHtml() !void {
    const self_exe_path = try std.fs.selfExePathAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(self_exe_path);

    const exe_dir = std.fs.path.dirname(self_exe_path) orelse ".";

    const script_name = if (builtin.os.tag == .windows) "launch-manual.ps1" else "launch-manual.sh";

    var script_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ exe_dir, script_name });
    defer std.heap.page_allocator.free(script_path);

    if (std.fs.cwd().openFile(script_path, .{})) |_| {} else |_| {
        script_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ exe_dir, "..", "..", "scripts", script_name });
        defer std.heap.page_allocator.free(script_path);
    }

    try HumanOutput.printInfo("Launching manual in browser...");

    if (builtin.os.tag == .windows) {
        const argv = &[_][]const u8{ "powershell", "-ExecutionPolicy", "Bypass", "-File", script_path };
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = argv,
        }) catch |err| {
            try HumanOutput.printError("Error launching manual: {}");
            return err;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        _ = result.term;
    } else {
        const argv = &[_][]const u8{ "bash", script_path };
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = argv,
        }) catch |err| {
            try HumanOutput.printError("Error launching manual: {}");
            return err;
        };
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        _ = result.term;
    }
}
