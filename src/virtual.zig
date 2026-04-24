//! A library of helpers for dealing with virtual method calls in Zig.

const std = @import("std");

/// The kind of virtual table to build.
pub const VTableKind = union(enum) {
    /// The virtual table is part of a fat pointer, where the first arguments of
    /// methods is an `anyopaque` pointer.
    fat_pointer: void,
    /// The virtual table is part of a polymorphic type and embedded as a field
    /// in the implementing type.
    ///
    /// This encodes the name of the field on the implementing type containg
    /// the polymorhic interface.
    field_parent_ptr: []const u8,
};

pub const create = @import("create.zig").create;

pub const isVTable = @import("meta.zig").isVTable;
pub const Method = @import("meta.zig").Method;
pub const method = @import("meta.zig").method;
pub const methods = @import("meta.zig").methods;

test {
    _ = @import("create.zig");
    _ = @import("meta.zig");
}
