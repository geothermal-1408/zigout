const std = @import("std");

pub fn build(b: *std.Build) void {
    
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "zig-breakout",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addObjectFile(.{ .cwd_relative = "/usr/local/lib/libraylib.a" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });

    exe.linkSystemLibrary("c");
    exe.linkFramework("OpenGL");
    exe.linkFramework("Cocoa");
    exe.linkFramework("IOKit");
    exe.linkFramework("CoreVideo");

    b.installArtifact(exe);
 
    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&exe.step);
}
