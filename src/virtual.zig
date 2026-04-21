//! A library of helpers for dealing with virtual method calls in Zig.

const std = @import("std");
const inflection = @import("inflection");

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

/// Creates a compile-time known `VTable` wrapping a type `T`, with `kind`
/// describing the kind of virtual table we are dealing with.
pub fn create(comptime VTable: type, comptime T: type, comptime kind: VTableKind) *const VTable {
    const static = struct {
        fn isConstMethod(comptime Method: type) bool {
            const method_info = @typeInfo(Method).@"fn";

            return method_info.params.len > 0 and
                method_info.params[0].type != null and
                @typeInfo(method_info.params[0].type.?) == .pointer and
                @typeInfo(method_info.params[0].type.?).pointer.is_const;
        }

        const transforms = switch (kind) {
            .fat_pointer => struct {
                fn constant(ptr: *const anyopaque) *const T {
                    return @ptrCast(@alignCast(ptr));
                }

                fn mutable(ptr: *anyopaque) *T {
                    return @ptrCast(@alignCast(ptr));
                }
            },
            .field_parent_ptr => |field_name| struct {
                fn constant(ptr: *const @FieldType(T, field_name)) *const T {
                    return @fieldParentPtr(field_name, ptr);
                }

                fn mutable(ptr: *@FieldType(T, field_name)) *T {
                    return @fieldParentPtr(field_name, ptr);
                }
            },
        };

        const methods = std.meta.fields(VTable);

        const vtable = make_vtable: {
            var result: VTable = undefined;

            for (methods) |method| {
                const method_info = @typeInfo(method.type);

                if (method_info != .pointer or
                    !method_info.pointer.is_const or
                    @typeInfo(method_info.pointer.child) != .@"fn")
                {
                    @compileError(
                        std.fmt.comptimePrint(
                            \\ A vtable must only contain function pointers, got:
                            \\  
                            \\   {s}: {},
                        ,
                            .{ method.name, method.type },
                        ),
                    );
                }

                const Method = method_info.pointer.child;
                const function_name = inflection.toCase(.zig_function, method.name);
                const transform = if (isConstMethod(Method)) transforms.constant else transforms.mutable;

                @field(result, method.name) = wrap(
                    Method,
                    @field(T, function_name),
                    transform,
                );
            }

            break :make_vtable result;
        };
    };

    return &static.vtable;
}

test "vtable using a fat pointer" {
    const Shape = struct {
        vtable: *const VTable,
        ptr: *anyopaque,

        const VTable = struct {
            area: *const fn (*const anyopaque) f64,
            some_super_long_function_name: *const fn (*anyopaque, i32, [:0]const u8) anyerror!void,
        };

        fn area(shape: @This()) f64 {
            return shape.vtable.area(shape.ptr);
        }

        fn someSuperLongFunctionName(shape: @This(), i: i32, str: [:0]const u8) anyerror!void {
            return shape.vtable.some_super_long_function_name(shape.ptr, i, str);
        }
    };

    const Circle = struct {
        radius: f64,

        fn shape(circle: *@This()) Shape {
            return .{
                .ptr = circle,
                .vtable = create(Shape.VTable, @This(), .fat_pointer),
            };
        }

        fn area(circle: *const @This()) f64 {
            return std.math.pi * circle.radius * circle.radius;
        }

        fn someSuperLongFunctionName(circle: *@This(), i: i32, str: [:0]const u8) anyerror!void {
            _ = circle;

            try std.testing.expectEqual(42, i);
            try std.testing.expectEqualStrings("Hello", str);

            return error.Expected;
        }
    };

    var circle = Circle{ .radius = 42 };

    try std.testing.expectApproxEqRel(
        std.math.pi * 42.0 * 42.0,
        circle.shape().area(),
        std.math.sqrt(std.math.floatEps(f64)),
    );

    try std.testing.expectError(
        error.Expected,
        circle.shape().someSuperLongFunctionName(42, "Hello"),
    );
}

test "vtable using field parent" {
    const Shape = struct {
        const Self = @This();

        vtable: *const VTable,

        const VTable = struct {
            area: *const fn (*const Self) f64,
            some_super_long_function_name: *const fn (*Self, i32, [:0]const u8) anyerror!void,
        };

        fn area(shape: *Self) f64 {
            return shape.vtable.area(shape);
        }

        fn someSuperLongFunctionName(shape: *Self, i: i32, str: [:0]const u8) anyerror!void {
            return shape.vtable.some_super_long_function_name(shape, i, str);
        }
    };

    const Circle = struct {
        shape: Shape = .{ .vtable = create(Shape.VTable, @This(), .{ .field_parent_ptr = "shape" }) },
        radius: f64,

        fn area(circle: *const @This()) f64 {
            return std.math.pi * circle.radius * circle.radius;
        }

        fn someSuperLongFunctionName(circle: *@This(), i: i32, str: [:0]const u8) anyerror!void {
            _ = circle;

            try std.testing.expectEqual(42, i);
            try std.testing.expectEqualStrings("Hello", str);

            return error.Expected;
        }
    };

    var circle = Circle{ .radius = 42 };

    try std.testing.expectApproxEqRel(
        std.math.pi * 42.0 * 42.0,
        circle.shape.area(),
        std.math.sqrt(std.math.floatEps(f64)),
    );

    try std.testing.expectError(
        error.Expected,
        circle.shape.someSuperLongFunctionName(42, "Hello"),
    );
}

fn wrap(comptime Method: type, comptime function: anytype, comptime transform: anytype) Method {
    const method_info = @typeInfo(Method).@"fn";

    return switch (method_info.params.len) {
        0 => struct {
            fn wrapper() (method_info.return_type orelse void) {
                return function();
            }
        },
        1 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                );
            }
        },
        2 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                );
            }
        },
        3 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                );
            }
        },
        4 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                );
            }
        },
        5 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                );
            }
        },
        6 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                );
            }
        },
        7 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                );
            }
        },
        8 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                );
            }
        },
        9 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                );
            }
        },
        10 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                );
            }
        },
        11 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                );
            }
        },
        12 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
                arg_11: method_info.params[11].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                    arg_11,
                );
            }
        },
        13 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
                arg_11: method_info.params[11].type.?,
                arg_12: method_info.params[12].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                    arg_11,
                    arg_12,
                );
            }
        },
        14 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
                arg_11: method_info.params[11].type.?,
                arg_12: method_info.params[12].type.?,
                arg_13: method_info.params[13].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                    arg_11,
                    arg_12,
                    arg_13,
                );
            }
        },
        15 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
                arg_11: method_info.params[11].type.?,
                arg_12: method_info.params[12].type.?,
                arg_13: method_info.params[13].type.?,
                arg_14: method_info.params[14].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                    arg_11,
                    arg_12,
                    arg_13,
                    arg_14,
                );
            }
        },
        16 => struct {
            fn wrapper(
                arg_0: method_info.params[0].type.?,
                arg_1: method_info.params[1].type.?,
                arg_2: method_info.params[2].type.?,
                arg_3: method_info.params[3].type.?,
                arg_4: method_info.params[4].type.?,
                arg_5: method_info.params[5].type.?,
                arg_6: method_info.params[6].type.?,
                arg_7: method_info.params[7].type.?,
                arg_8: method_info.params[8].type.?,
                arg_9: method_info.params[9].type.?,
                arg_10: method_info.params[10].type.?,
                arg_11: method_info.params[11].type.?,
                arg_12: method_info.params[12].type.?,
                arg_13: method_info.params[13].type.?,
                arg_14: method_info.params[14].type.?,
                arg_15: method_info.params[15].type.?,
            ) (method_info.return_type orelse void) {
                return function(
                    @call(.always_inline, transform, .{arg_0}),
                    arg_1,
                    arg_2,
                    arg_3,
                    arg_4,
                    arg_5,
                    arg_6,
                    arg_7,
                    arg_8,
                    arg_9,
                    arg_10,
                    arg_11,
                    arg_12,
                    arg_13,
                    arg_14,
                    arg_15,
                );
            }
        },
        else => @compileError(
            std.fmt.comptimePrint(
                \\ Wow, your method has more than 16 arguments ({} to be exact).
                \\ 
                \\ Unfortunately, Zig doesn't allow variadic functions, so we need to create a wrapper for any number of arguments.
                \\ We decided that 16 arguments was more than enough.
            ,
                .{method_info.params.len},
            ),
        ),
    }.wrapper;
}
