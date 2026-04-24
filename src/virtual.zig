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

test {
    _ = @import("create.zig");
}
