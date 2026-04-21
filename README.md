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
zig fetch --save git+https://github.com/brodeuralexis/zig-virtual#v1.0.0
```

You can then modify your `build.zig` to import it like so:

```zig
const virtual_dep = b.dependency("virtual", .{ target = target, .optimize = optimize });
const virtual_mod = virtual_dep.module("virtual");

exe.root_module.addImport("virtual", virtual_mod);
```
