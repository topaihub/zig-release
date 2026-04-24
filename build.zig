const std = @import("std");

pub fn build(b: *std.Build) void {
    const release_exe = b.addExecutable(.{
        .name = "zig-release",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
        }),
    });

    b.installArtifact(release_exe);

    const run = b.addRunArtifact(release_exe);
    if (b.args) |a| run.addArgs(a);
    const run_step = b.step("run", "Run release tool");
    run_step.dependOn(&run.step);
}

/// 供其他项目在 build.zig 中调用，添加 `zig build release -- patch` 命令
pub fn addReleaseStep(
    b: *std.Build,
    dep: *std.Build.Dependency,
    options: struct {
        repo_url: ?[]const u8 = null,
    },
) void {
    const release_step = b.step("release", "Tag and push a new release (-- patch|minor|major)");
    const release_exe = dep.artifact("zig-release");
    const run = b.addRunArtifact(release_exe);
    run.setCwd(b.path("."));
    if (options.repo_url) |url| {
        run.addArg("--repo");
        run.addArg(url);
    }
    if (b.args) |a| run.addArgs(a);
    release_step.dependOn(&run.step);
}
