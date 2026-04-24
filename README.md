<div align="center">

![checks](https://img.shields.io/github/check-runs/brodeuralexis/zig-virtual/trunk)
[![documentation](https://img.shields.io/badge/zig--virtual-documentation-blue)](https://brodeuralexis.github.io/zig-virtual/)
[![license](https://img.shields.io/badge/license-MIT-lightgrey)](./LICENSE)

</div>

# Virtual

A library of utilities for dealing with virtual method tables in Zig.

## Installation

Run the following command to add the latest tagged release to your
`build.zig.zon` file:

``` shell
zig fetch --save git+https://github.com/brodeuralexis/zig-virtual#v1.2.0
```

You can then modify your `build.zig` to import it like so:

```zig
const virtual_dep = b.dependency("virtual", .{ target = target, .optimize = optimize });
const virtual_mod = virtual_dep.module("virtual");

exe.root_module.addImport("virtual", virtual_mod);
```

## Example

```zig
const Shape = struct {
    vtable: *const VTable,
    ptr: *anyopaque,

    const VTable = struct {
        area: *const fn(*anyopaque) f64,
    };

    fn area(shape: Shape) f64 {
        return shape.vtable.area(shape.ptr);
    }
};

const Circle = struct {
    radius: f64,

    fn shape(circle: *Circle) Shape {
        return .{
            .vtable = virtual.create(Shape.VTable, Circle, .fat_pointer),
            .ptr = circle,
        };
    }

    fn area(circle: *Circle) f64 {
        return std.math.pi * circle.radius * circle.radius;
    }
};

var circle = Circle{ .radius = 42 };
const shape = circle.shape();

try std.testing.expectEqual(5541.76944093, shape.area());
```
