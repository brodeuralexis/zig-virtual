const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const inflection_dep = b.dependency("inflection", .{
        .target = target,
        .optimize = optimize,
    });
    const inflection_mod = inflection_dep.module("inflection");

    const virtual_mod = b.addModule("virtual", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/virtual.zig"),
    });

    virtual_mod.addImport("inflection", inflection_mod);

    const tests = b.addTest(.{ .root_module = virtual_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Tests the library.");
    test_step.dependOn(&run_tests.step);

    const docs_step = b.step("docs", "Generate documentation.");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    b.default_step.dependOn(test_step);
}
