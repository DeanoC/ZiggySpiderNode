const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ziggy_spider_protocol_dep = b.dependency("ziggy_spider_protocol", .{
        .target = target,
        .optimize = optimize,
    });
    const spiderweb_node_mod = ziggy_spider_protocol_dep.module("spiderweb_node");

    const node_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    node_main_mod.addImport("spiderweb_node", spiderweb_node_mod);

    const spider_node = b.addExecutable(.{
        .name = "spiderweb-fs-node",
        .root_module = node_main_mod,
    });
    spider_node.linkLibC();
    b.installArtifact(spider_node);

    const echo_driver_mod = b.createModule(.{
        .root_source_file = b.path("examples/drivers/echo_driver.zig"),
        .target = target,
        .optimize = optimize,
    });
    const echo_driver = b.addExecutable(.{
        .name = "spiderweb-echo-driver",
        .root_module = echo_driver_mod,
    });
    echo_driver.linkLibC();
    b.installArtifact(echo_driver);

    const run_cmd = b.addRunArtifact(spider_node);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run spiderweb-fs-node");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("spiderweb_node", spiderweb_node_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run node wrapper tests");
    test_step.dependOn(&run_tests.step);
}
