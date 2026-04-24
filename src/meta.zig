const std = @import("std");
const inflection = @import("inflection");

/// Indicates if the provided type is a VTable.
///
/// A virtual method table is a mecanism used in low-level programming languages
/// to support dynamic dispatch. It allows a program to determine which
/// implementation of a virtual function to call at runtime rather than at
/// compile-time.
///
/// A virtual method table must be a *struct* composed of only runtime function
/// pointers.
pub fn isVTable(comptime T: type) bool {
    return getVTableError(T) == null;
}

test isVTable {
    const AABB = struct {
        min: [3]f64,
        max: [3]f64,
    };

    const VTable = struct {
        clips: *const fn (*const anyopaque, aabb: AABB) bool,
        get_aabb: *const fn (*const anyopaque) AABB,
        set_aabb: *const fn (*anyopaque, aabb: AABB) void,
    };

    try std.testing.expect(!isVTable(i32));
    try std.testing.expect(!isVTable(enum {}));
    try std.testing.expect(isVTable(struct {}));
    try std.testing.expect(isVTable(VTable));
}

/// `Method` describes a method on a virtual method table.
pub const Method = struct {
    /// The name of the field containing the method on the virtual method
    /// table.
    ///
    /// This should be in *snake_case*, as is the convention for Zig struct
    /// field identifiers.
    vtable_name: []const u8,
    /// The name of the declaration containing the method implementation on the
    /// implementing type.
    ///
    /// This will be in *camelCase*, as is the convention for Zig function
    /// names.
    function_name: []const u8,
    /// Indicates if the method is declared as optional.
    is_optional: bool,
    /// Indicates if the first parameter of the virtual method is a constant
    /// pointer.
    is_const: bool,
    /// The type of the virtual method.
    type: type,
};

/// `methods` returns the `Method`s of a virtual method table.
///
/// The order of the methods will be the same as their declarations in the
/// virtual method table.
pub fn methods(comptime VTable: type) []const Method {
    const static = struct {
        comptime {
            if (getVTableError(VTable)) |err| {
                @compileError(err);
            }
        }

        const methods = make_methods: {
            const fields = @typeInfo(VTable).@"struct".fields;

            var result: [fields.len]Method = undefined;

            for (fields, 0..) |field, i| {
                const field_info = @typeInfo(field.type);

                result[i].vtable_name = field.name;
                result[i].function_name = inflection.toCase(.zig_function, result[i].vtable_name);
                result[i].is_optional = field_info == .optional;

                result[i].type = if (result[i].is_optional)
                    @typeInfo(field_info.optional.child).pointer.child
                else
                    field_info.pointer.child;

                const method_info = @typeInfo(result[i].type).@"fn";

                result[i].is_const = @typeInfo(method_info.params[0].type.?).pointer.is_const;
            }

            break :make_methods result;
        };
    };

    return &static.methods;
}

test methods {
    const VTable = struct {
        get_position: *const fn (*const anyopaque) [3]f64,
        set_position: *const fn (*anyopaque, position: [3]f64) anyerror!void,
        print: ?*const fn (*const anyopaque, writer: *std.Io.Writer) anyerror!void,
    };

    try comptime std.testing.expectEqualDeep(
        &[3]Method{
            Method{
                .vtable_name = "get_position",
                .function_name = "getPosition",
                .is_optional = false,
                .is_const = true,
                .type = fn (*const anyopaque) [3]f64,
            },
            Method{
                .vtable_name = "set_position",
                .function_name = "setPosition",
                .is_optional = false,
                .is_const = false,
                .type = fn (*anyopaque, position: [3]f64) anyerror!void,
            },
            Method{
                .vtable_name = "print",
                .function_name = "print",
                .is_optional = true,
                .is_const = true,
                .type = fn (*const anyopaque, writer: *std.Io.Writer) anyerror!void,
            },
        },
        methods(VTable),
    );
}

/// `method` returns the `Method` with the given name.
///
/// The name can either be in *snake_case* or *camelCase* to match either the
/// field name on the virtual method table, or the declaration name on the
/// implementing type.
pub fn method(comptime VTable: type, comptime name: []const u8) Method {
    return comptime for (methods(VTable)) |m| {
        if (std.mem.eql(u8, m.vtable_name, name) or std.mem.eql(u8, m.function_name, name)) {
            return m;
        }
    } else @compileError(std.fmt.comptimePrint(
        "expected method {s} on vtable {}",
        .{ name, VTable },
    ));
}

test method {
    const VTable = struct {
        destroy: ?*const fn (*anyopaque) void,
        get_area: *const fn (*const anyopaque) f64,
    };

    try comptime std.testing.expectEqualDeep(
        Method{
            .vtable_name = "destroy",
            .function_name = "destroy",
            .is_optional = true,
            .is_const = false,
            .type = fn (*anyopaque) void,
        },
        method(VTable, "destroy"),
    );

    try comptime std.testing.expectEqualDeep(
        Method{
            .vtable_name = "get_area",
            .function_name = "getArea",
            .is_optional = false,
            .is_const = true,
            .type = fn (*const anyopaque) f64,
        },
        method(VTable, "get_area"),
    );

    try comptime std.testing.expectEqualDeep(
        Method{
            .vtable_name = "get_area",
            .function_name = "getArea",
            .is_optional = false,
            .is_const = true,
            .type = fn (*const anyopaque) f64,
        },
        method(VTable, "getArea"),
    );
}

pub fn getVTableError(comptime T: type) ?[]const u8 {
    const struct_info = switch (@typeInfo(T)) {
        .@"struct" => |struct_info| struct_info,
        else => |info| return std.fmt.comptimePrint(
            "expected `{}` to be a struct, got: {s}",
            .{ T, @tagName(info) },
        ),
    };

    if (struct_info.is_tuple) {
        return std.fmt.comptimePrint(
            "expected `{}` to be a struct, got: tuple",
            .{T},
        );
    }

    inline for (struct_info.fields) |field| {
        const method_info = switch (@typeInfo(field.type)) {
            .optional => |optional_info| @typeInfo(optional_info.child),
            else => |method_info| method_info,
        };

        const pointer_info = switch (method_info) {
            .pointer => |pointer_info| pointer_info,
            else => return std.fmt.comptimePrint(
                "expected `{}.{s}` to be a constant pointer to a runtime function, got: {}",
                .{ T, field.name, field.type },
            ),
        };

        if (!pointer_info.is_const or pointer_info.size != .one) {
            return std.fmt.comptimePrint(
                "expected `{}.{s}` to be a constant pointer to a runtime function, got: {}",
                .{ T, field.name, field.type },
            );
        }

        const fn_info = switch (@typeInfo(pointer_info.child)) {
            .@"fn" => |fn_info| fn_info,
            else => return std.fmt.comptimePrint(
                "expected `{}.{s}` to be a constant pointer to a runtime function, got: {}",
                .{ T, field.name, field.type },
            ),
        };

        if (fn_info.is_generic) {
            return std.fmt.comptimePrint(
                "expected `{}.{s}` to not be generic, got: {}",
                .{ T, field.name, field.type },
            );
        }

        if (fn_info.is_var_args) {
            return std.fmt.comptimePrint(
                "expected `{}.{s}` to not be variadic, got: {}",
                .{ T, field.name, field.type },
            );
        }

        if (fn_info.params.len <= 0) {
            return std.fmt.comptimePrint(
                "expected `{}.{s}` to have at least one parameter, got: {}",
                .{ T, field.name, field.type },
            );
        }

        const param0_info = @typeInfo(fn_info.params[0].type orelse void);
        if (param0_info != .pointer or param0_info.pointer.size != .one) {
            return std.fmt.comptimePrint(
                "expected `{}.{s}`'s first parameter to be a pointer, got: {}",
                .{ T, field.name, field.type },
            );
        }
    }

    return null;
}

test getVTableError {
    try std.testing.expectEqualStrings(
        "expected `i32` to be a struct, got: int",
        getVTableError(i32).?,
    );

    {
        const VTable = union {};
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable` to be a struct, got: union",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = enum {};
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable` to be a struct, got: enum",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct {};
        try std.testing.expect(getVTableError(VTable) == null);
    }

    {
        const VTable = struct { *const fn (*anyopaque) void, *const fn (*anyopaque, i32) ?i32 };
        try std.testing.expectEqualStrings(
            "expected `struct { *const fn (*anyopaque) void, *const fn (*anyopaque, i32) ?i32 }` to be a struct, got: tuple",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: ?i32 };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to be a constant pointer to a runtime function, got: ?i32",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: bool };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to be a constant pointer to a runtime function, got: bool",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: *fn (*anyopaque) void };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to be a constant pointer to a runtime function, got: *fn (*anyopaque) void",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: *fn (*anyopaque) void };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to be a constant pointer to a runtime function, got: *fn (*anyopaque) void",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: *fn (*anyopaque) void };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to be a constant pointer to a runtime function, got: *fn (*anyopaque) void",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: *const fn (*anyopaque, comptime T: type) void };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to not be generic, got: *const fn (*anyopaque, comptime type) void",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct { method: *const fn (*anyopaque, ...) callconv(.c) void };
        try std.testing.expectEqualStrings(
            "expected `meta.decltest.getVTableError.VTable.method` to not be variadic, got: *const fn (*anyopaque, ...) callconv(.c) void",
            getVTableError(VTable).?,
        );
    }

    {
        const VTable = struct {
            destroy: ?*const fn (*anyopaque) void,
            get_area: *const fn (*const anyopaque) f64,
        };

        try std.testing.expect(getVTableError(VTable) == null);
    }
}
