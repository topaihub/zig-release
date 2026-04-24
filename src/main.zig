const std = @import("std");

const alloc = std.heap.page_allocator;

const Config = struct {
    repo_url: []const u8 = "",
    bump: []const u8 = "patch",
};

fn getIo() std.Io {
    const t = std.Io.Threaded.global_single_threaded;
    t.allocator = std.heap.page_allocator;
    return t.*.io();
}

fn print(comptime fmt: []const u8, args: anytype) void {
    const out = std.Io.File.stdout();
    var buf: [8192]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    out.writeStreamingAll(getIo(), s) catch {};
}

fn readLine() ?u8 {
    const in = std.Io.File.stdin();
    var buf: [8]u8 = undefined;
    const slice: []u8 = &buf;
    const n = in.readStreaming(getIo(), &.{slice}) catch return null;
    if (n == 0) return null;
    return buf[0];
}

fn git(argv: []const []const u8) ![]const u8 {
    const io = getIo();
    var full: std.ArrayListUnmanaged([]const u8) = .empty;
    try full.append(alloc, "git");
    try full.appendSlice(alloc, argv);

    var child = try std.process.spawn(io, .{ .argv = full.items, .stdout = .pipe, .stderr = .pipe });
    const file = child.stdout.?;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = file.readStreaming(io, &.{&tmp}) catch break;
        if (n == 0) break;
        try buf.appendSlice(alloc, tmp[0..n]);
    }
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.GitFailed,
        else => return error.GitFailed,
    }
    return std.mem.trim(u8, buf.items, " \n\r");
}

fn parseVersion(s: []const u8) [3]u32 {
    const t = std.mem.trim(u8, s, " \n\rv");
    var it = std.mem.splitScalar(u8, t, '.');
    return .{
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
    };
}

fn bumpVersion(v: [3]u32, bump: []const u8) [3]u32 {
    if (std.mem.eql(u8, bump, "major")) return .{ v[0] + 1, 0, 0 };
    if (std.mem.eql(u8, bump, "minor")) return .{ v[0], v[1] + 1, 0 };
    if (std.mem.eql(u8, bump, "patch")) return .{ v[0], v[1], v[2] + 1 };
    return parseVersion(bump);
}

fn fmtVer(v: [3]u32) []const u8 {
    return std.fmt.allocPrint(alloc, "v{d}.{d}.{d}", .{ v[0], v[1], v[2] }) catch "v0.0.0";
}

const Section = struct { prefix: []const u8, label: []const u8 };
const sections = [_]Section{
    .{ .prefix = "feat", .label = "### ✨ 新功能" },
    .{ .prefix = "fix", .label = "### 🐛 Bug 修复" },
    .{ .prefix = "docs", .label = "### 📝 文档" },
    .{ .prefix = "refactor", .label = "### ♻️ 重构" },
    .{ .prefix = "perf", .label = "### ⚡ 性能优化" },
    .{ .prefix = "ci", .label = "### 👷 CI/CD" },
    .{ .prefix = "chore", .label = "### 🔧 其他" },
};

fn generateChangelog(repo_url: []const u8, tag: []const u8, date: []const u8, log: []const u8) []const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const a = alloc;

    buf.appendSlice(a, "## [") catch return "";
    buf.appendSlice(a, tag) catch return "";
    if (repo_url.len > 0) {
        buf.appendSlice(a, "](") catch return "";
        buf.appendSlice(a, repo_url) catch return "";
        buf.appendSlice(a, "/releases/tag/") catch return "";
        buf.appendSlice(a, tag) catch return "";
        buf.appendSlice(a, ")") catch return "";
    } else {
        buf.appendSlice(a, "]") catch return "";
    }
    buf.appendSlice(a, " (") catch return "";
    buf.appendSlice(a, date) catch return "";
    buf.appendSlice(a, ")\n") catch return "";

    for (&sections) |sec| {
        var found = false;
        var lines = std.mem.splitScalar(u8, log, '\n');
        while (lines.next()) |line| {
            if (line.len < 42) continue;
            const msg = line[41..];
            if (std.mem.startsWith(u8, msg, sec.prefix)) {
                if (!found) {
                    buf.appendSlice(a, "\n") catch {};
                    buf.appendSlice(a, sec.label) catch {};
                    buf.appendSlice(a, "\n\n") catch {};
                    found = true;
                }
                buf.appendSlice(a, "- ") catch {};
                buf.appendSlice(a, msg) catch {};
                if (repo_url.len > 0) {
                    buf.appendSlice(a, " ([") catch {};
                    buf.appendSlice(a, line[0..7]) catch {};
                    buf.appendSlice(a, "](") catch {};
                    buf.appendSlice(a, repo_url) catch {};
                    buf.appendSlice(a, "/commit/") catch {};
                    buf.appendSlice(a, line[0..40]) catch {};
                    buf.appendSlice(a, "))") catch {};
                }
                buf.append(a, '\n') catch {};
            }
        }
    }
    return buf.items;
}

fn writeFile(path: []const u8, content: []const u8) void {
    const io = getIo();
    const cwd = std.Io.Dir.cwd();
    const file = cwd.createFile(io, path, .{}) catch return;
    file.writeStreamingAll(io, content) catch {};
    file.close(io);
}

fn readFile(path: []const u8) ?[]const u8 {
    const io = getIo();
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, @enumFromInt(1048576)) catch null;
}

fn detectRepoUrl() []const u8 {
    const remote = git(&.{ "remote", "get-url", "origin" }) catch return "";
    // https://github.com/user/repo.git -> https://github.com/user/repo
    if (std.mem.endsWith(u8, remote, ".git")) return remote[0 .. remote.len - 4];
    return remote;
}

fn parseArgs(init: std.process.Init) Config {
    var args_it = std.process.Args.Iterator.initAllocator(init.minimal.args, alloc) catch return .{};
    _ = args_it.next(); // skip program name

    var cfg = Config{};
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--repo")) {
            cfg.repo_url = args_it.next() orelse "";
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            cfg.bump = arg;
        }
    }
    return cfg;
}

pub fn main(init: std.process.Init) !void {
    const cfg = parseArgs(init);
    const repo_url = if (cfg.repo_url.len > 0) cfg.repo_url else detectRepoUrl();

    const latest = git(&.{ "describe", "--tags", "--abbrev=0" }) catch "v0.0.0";
    const cur = parseVersion(latest);
    const new = bumpVersion(cur, cfg.bump);
    const tag = fmtVer(new);
    const date = git(&.{ "log", "-1", "--format=%cd", "--date=short" }) catch "unknown";

    print("\n当前版本: {s}\n新版本:   {s}\n\n", .{ latest, tag });

    const range = std.fmt.allocPrint(alloc, "{s}..HEAD", .{latest}) catch unreachable;
    const log = git(&.{ "log", "--format=%H %s", range, "--no-merges" }) catch "";
    const changelog = generateChangelog(repo_url, tag, date, log);

    print("--- CHANGELOG 预览 ---\n{s}\n----------------------\n\n确认发布 {s}? (y/N) ", .{ changelog, tag });

    const ch = readLine() orelse return;
    if (ch != 'y' and ch != 'Y') {
        print("已取消\n", .{});
        return;
    }

    // 更新 CHANGELOG.md
    if (readFile("CHANGELOG.md")) |old| {
        const content = std.fmt.allocPrint(alloc, "{s}\n{s}", .{ changelog, old }) catch return;
        writeFile("CHANGELOG.md", content);
    } else {
        const content = std.fmt.allocPrint(alloc, "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n{s}\n", .{changelog}) catch return;
        writeFile("CHANGELOG.md", content);
    }

    // 更新 build.zig.zon 版本号
    if (readFile("build.zig.zon")) |old| {
        const needle = ".version = \"";
        if (std.mem.indexOf(u8, old, needle)) |start| {
            const after = start + needle.len;
            if (std.mem.indexOfScalarPos(u8, old, after, '"')) |end| {
                const ver_str = std.fmt.allocPrint(alloc, "{d}.{d}.{d}", .{ new[0], new[1], new[2] }) catch return;
                const content = std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ old[0..after], ver_str, old[end..] }) catch return;
                writeFile("build.zig.zon", content);
            }
        }
    }

    _ = git(&.{ "add", "CHANGELOG.md", "build.zig.zon" }) catch {};
    const msg = std.fmt.allocPrint(alloc, "chore(release): {s}", .{tag}) catch unreachable;
    _ = git(&.{ "commit", "-m", msg }) catch {};
    _ = git(&.{ "tag", tag }) catch {};
    _ = git(&.{ "push", "origin", "HEAD" }) catch {};
    _ = git(&.{ "push", "origin", tag }) catch {};

    print("\n✓ {s} 已发布！\n", .{tag});
    if (repo_url.len > 0) {
        print("  Release: {s}/releases\n", .{repo_url});
    }
}
