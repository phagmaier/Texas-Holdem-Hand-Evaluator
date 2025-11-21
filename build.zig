const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Create the Module
    // This defines your library (root.zig) and its dependencies.
    // We capture it in 'poker_mod' so we can use it later.
    const poker_mod = b.addModule("PokerEval", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Create the Tests
    // Instead of redefining the file path, we just tell the test runner:
    // "Test the module I defined above."
    const lib_unit_tests = b.addTest(.{
        .root_module = poker_mod,
    });

    // 3. Create the Run Step
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

