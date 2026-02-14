//! Storage interface
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Neurona = opaque {};

pub const Storage = struct {
    ctx: *anyopaque,
    vtable: *const VTable,
};

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque) void,
};
