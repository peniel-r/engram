//! Storage interface
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Item = opaque {};

pub const Storage = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub fn deinit(self: Storage) void {
        self.vtable.deinit(self.ctx);
    }
};

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque) void,
    readItem: *const fn (ctx: *anyopaque, allocator: Allocator, id: []const u8) *Item,
    writeItem: *const fn (ctx: *anyopaque, allocator: Allocator, item: *Item) void,
    deleteItem: *const fn (ctx: *anyopaque, allocator: Allocator, id: []const u8) void,
    listItems: *const fn (ctx: *anyopaque, allocator: Allocator) [][]const u8,
};

test "Storage interface can be created" {
    _ = @as(Storage, undefined);
}
