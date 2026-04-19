const std = @import("std");
const Type = std.builtin.Type;

/// Wraps a function transforming its first argument using the provided
/// transform.
///
/// This is a bit of a pain in the ass to implement, as Zig doesn't have
/// variadic function.
pub fn wrap(comptime Method: type, comptime function: anytype, comptime transform: anytype) Method {
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
