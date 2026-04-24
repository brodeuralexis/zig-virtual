const std = @import("std");
const inflection = @import("inflection");

const virtual = @import("virtual.zig");

/// Creates a compile-time known `VTable` wrapping a type `T`, with `kind`
/// describing the kind of virtual table we are dealing with.
///
/// ## Virtual Table
///
/// A virtual method table is a mecanism used in low-level programming languages
/// to support dynamic dispatch. It allows a program to determine which
/// implementation of a virtual function to call at runtime rather than at
/// compile-time.
///
/// The virtual table must be a *struct* containing only constant pointers to
/// functions:
///
/// ```zig
/// const Shape = struct {
///     ptr: *const anyopaque,
///     vtable: *const VTable,
///
///     const VTable = struct {
///         area: *const fn (*anyopaque) f64,
///     };
/// };
/// ```
///
/// The `create` function is able to instantiate a virtual table for an
/// implementing type, reducing the amount of boilerplate code one must write:
///
/// ```zig
/// const Circle = struct {
///     radius: f64,
///
///     fn area(circle: *Circle) f64 {
///         return std.math.pi * circle.radius * circle.radius;
///     }
/// };
///
/// var circle = Circle{ .radius = 42 };
///
/// const shape = Shape{
///     .ptr = &circle,
///     .vtable = virtual.create(Shape.VTable, Circle, .fat_pointer),
/// };
/// ```
///
/// ## Name Mapping
///
/// In Zig, naming conventions are different for *struct* fields and function
/// names.  `create` accounts for this by inflecting the function name in
/// *camelCase* from the virtual table's method name in *snake_case*:
///
/// ```zig
/// const VTable = struct {
///     some_long_method_name: *const fn (*anyopaque) void,
/// };
///
/// const Impl = struct {
///     // NOTE: This maps to `VTable.some_long_method_name`.
///     fn someLongMethodName(impl: *Impl) void { ... }
/// };
/// ```
///
/// To ensure that inflection is done correctly, we suggest using only C
/// compatible identifiers using ASCII characters.
///
/// ## Optional Method
///
/// When using `create`, virtual table methods may be defined as optional. If
/// the method is not defined on the implementing type, it is set to `null` on
/// the returned virtual table instance:
///
/// ```zig
/// const VTable = struct {
///     optional_method: ?*const fn (*anyopaque) u32,
/// };
///
/// const Impl = struct {};
///
/// const vtable = virtual.create(VTable, Impl, .fat_pointer);
/// std.debug.assert(vtable.optional_method == null);
/// ```
///
/// ## Const Correctness
///
/// When designing interfaces, it is oftentimes useful to be able to ensure that
/// a virtual method cannot modify the implementation on which it operates.  The
/// `create` function ensures that const is enforced correctly on implementing
/// types:
///
/// ```zig
/// const VTable = struct {
///     some_constant_method: *const fn(*const anyopaque, arg: u32) anyerror!void,
/// };
///
/// const Impl = struct {
///     // NOTE: It would be a compile error to use `impl: *Impl` here.
///     fn someConstantMethod(impl: *const Impl, arg: u32) anyerror!void {
///         ...
///     }
/// };
/// ```
///
/// ## Fat Pointer Interfaces
///
/// Fat pointer interfaces wrap both a pointer to the virtual table and a
/// pointer to the implementation in the interface:
///
/// ```zig
/// const Shape = struct {
///     vtable: *const VTable,
///     ptr: *anyopaque,
///
///     const VTable = struct {
///         area: *const fn(shape: *anyopaque) f64,
///     };
/// };
/// ```
///
/// The `create` function can be used to create a virtual table for such a type:
///
/// ```zig
/// const Circle = struct {
///     radius: f64,
///
///     fn area(circle: *Circle) f64 {
///         return std.math.pi * circle.radius * circle.radius;
///     }
///
///     fn shape(circle: *Circle) Shape {
///         return .{ .vtable = virtual.create(Shape.VTable, Circle, .fat_pointer), .ptr = circle };
///     }
/// };
/// ```
///
/// ## Polymorphic Interfaces
///
/// Polymorphic interfaces use composition to emulate inheritance, embedding the
/// interface as a field on the implementing type:
///
/// ```zig
/// const Shape = struct {
///     vtable: *const VTable,
///
///     const VTable = struct {
///         area: *const fn(shape: *Shape) f64,
///     };
/// };
/// ```
///
/// The `create` function can also be used to create a virtual table for such a
/// type:
///
/// ```zig
/// const Circle = struct {
///     shape: Shape = .{ .vtable = virtual.create(Shape.VTable, Circle, .{ .field_parent_ptr = "shape" }) },
///     radius: f64,
///
///     fn area(circle: *Circle) f64 {
///         return std.math.pi * circle.radius * circle.radius;
///     }
/// };
/// ```
pub fn create(comptime VTable: type, comptime T: type, comptime kind: virtual.VTableKind) *const VTable {
    const static = struct {
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
                if (MethodKind.extract(method)) |method_kind| {
                    const Method = method_kind.toType();
                    const function_name = inflection.toCase(.zig_function, method.name);
                    const transform = if (method_kind.isConst()) transforms.constant else transforms.mutable;

                    switch (method_kind) {
                        .required => {
                            @field(result, method.name) = wrap(
                                Method,
                                @field(T, function_name),
                                transform,
                            );
                        },
                        .optional => {
                            if (@hasDecl(T, function_name)) {
                                @field(result, method.name) = wrap(
                                    Method,
                                    @field(T, function_name),
                                    transform,
                                );
                            } else {
                                @field(result, method.name) = null;
                            }
                        },
                    }
                } else {
                    @compileError(
                        std.fmt.comptimePrint(
                            \\ A vtable must only contain function pointers, got:                        
                            \\   {s}: {},
                        ,
                            .{ method.name, method.type },
                        ),
                    );
                }
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
            volume: ?*const fn (*const anyopaque) f64,
            some_super_long_function_name: *const fn (*anyopaque, i32, [:0]const u8) anyerror!void,
        };

        fn area(shape: @This()) f64 {
            return shape.vtable.area(shape.ptr);
        }

        fn volume(shape: @This()) ?f64 {
            return if (shape.vtable.volume) |volume_fn|
                volume_fn(shape.ptr)
            else
                null;
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

    try std.testing.expectEqual(
        null,
        circle.shape().volume(),
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
            volume: ?*const fn (*const Self) f64,
            some_super_long_function_name: *const fn (*Self, i32, [:0]const u8) anyerror!void,
        };

        fn area(shape: *Self) f64 {
            return shape.vtable.area(shape);
        }

        fn volume(shape: *Self) ?f64 {
            return if (shape.vtable.volume) |volume_fn|
                volume_fn(shape)
            else
                null;
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

    try std.testing.expectEqual(
        null,
        circle.shape.volume(),
    );

    try std.testing.expectError(
        error.Expected,
        circle.shape.someSuperLongFunctionName(42, "Hello"),
    );
}

const MethodKind = union(enum) {
    required: type,
    optional: type,

    fn toInfo(comptime method_kind: MethodKind) std.builtin.Type.Fn {
        return switch (method_kind) {
            inline else => |value| @typeInfo(value).@"fn",
        };
    }

    fn toType(comptime method_kind: MethodKind) type {
        return switch (method_kind) {
            inline else => |value| value,
        };
    }

    fn extract(comptime method: std.builtin.Type.StructField) ?MethodKind {
        const method_info = @typeInfo(method.type);

        return switch (method_info) {
            .pointer => |pointer_info| MethodKind{ .required = doExtract(pointer_info) orelse return null },
            .optional => |optional_info| switch (@typeInfo(optional_info.child)) {
                .pointer => |pointer_info| MethodKind{ .optional = doExtract(pointer_info) orelse return null },
                else => null,
            },
            else => null,
        };
    }

    fn doExtract(comptime pointer_info: std.builtin.Type.Pointer) ?type {
        if (!pointer_info.is_const) {
            return null;
        }

        if (@typeInfo(pointer_info.child) != .@"fn") {
            return null;
        }

        return pointer_info.child;
    }

    fn isConst(comptime method_kind: MethodKind) bool {
        const method_info = method_kind.toInfo();

        return method_info.params.len > 0 and
            method_info.params[0].type != null and
            @typeInfo(method_info.params[0].type.?) == .pointer and
            @typeInfo(method_info.params[0].type.?).pointer.is_const;
    }
};

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
