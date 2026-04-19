const std = @import("std");
const inflection = @import("inflection");

const wrap = @import("wrap.zig").wrap;

pub const VTableKind = union(enum) {
    fat_pointer: void,
    field_parent_ptr: []const u8,
};

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

        pub const VTable = struct {
            area: *const fn (*const anyopaque) f64,
            some_super_long_function_name: *const fn (*anyopaque, i32, [:0]const u8) anyerror!void,
        };

        pub fn area(shape: @This()) f64 {
            return shape.vtable.area(shape.ptr);
        }

        pub fn someSuperLongFunctionName(shape: @This(), i: i32, str: [:0]const u8) anyerror!void {
            return shape.vtable.some_super_long_function_name(shape.ptr, i, str);
        }
    };

    const Circle = struct {
        radius: f64,

        pub fn shape(circle: *@This()) Shape {
            return .{
                .ptr = circle,
                .vtable = create(Shape.VTable, @This(), .fat_pointer),
            };
        }

        pub fn area(circle: *const @This()) f64 {
            return std.math.pi * circle.radius * circle.radius;
        }

        pub fn someSuperLongFunctionName(circle: *@This(), i: i32, str: [:0]const u8) anyerror!void {
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

        pub const VTable = struct {
            area: *const fn (*const Self) f64,
            some_super_long_function_name: *const fn (*Self, i32, [:0]const u8) anyerror!void,
        };

        pub fn area(shape: *Self) f64 {
            return shape.vtable.area(shape);
        }

        pub fn someSuperLongFunctionName(shape: *Self, i: i32, str: [:0]const u8) anyerror!void {
            return shape.vtable.some_super_long_function_name(shape, i, str);
        }
    };

    const Circle = struct {
        shape: Shape = .{ .vtable = create(Shape.VTable, @This(), .{ .field_parent_ptr = "shape" }) },
        radius: f64,

        pub fn area(circle: *const @This()) f64 {
            return std.math.pi * circle.radius * circle.radius;
        }

        pub fn someSuperLongFunctionName(circle: *@This(), i: i32, str: [:0]const u8) anyerror!void {
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
