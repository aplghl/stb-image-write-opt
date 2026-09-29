const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Conservative default: -ffp-contract=off for byte-identical output. On
    // x86-64 add -march=x86-64-v2 to unlock the compiler's SSE4/AVX
    // auto-vectorization of the JPEG encoder (still byte-exact; `make verify`).
    // The SSE2 match kernel is active even at plain x86-64 baseline.
    const flags: []const []const u8 = if (target.result.cpu.arch == .x86_64)
        &.{ "-ffp-contract=off", "-march=x86-64-v2" }
    else
        &.{"-ffp-contract=off"};

    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addIncludePath(b.path("src"));
    lib_mod.addCSourceFile(.{ .file = b.path("lib/stb_image_write.c"), .flags = flags });
    const lib = b.addLibrary(.{
        .name = "stb-image-write-opt",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);
    b.installFile("src/stb_image_write.h", "include/stb_image_write.h");
}
