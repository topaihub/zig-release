const std = @import("std");

const ChangelogType = struct {
    type_name: []const u8,
    section: []const u8,
};

const VersionFileRule = struct {
    path: []const u8,
    pattern: []const u8,
};

const SkipConfig = struct {
    changelog: bool = false,
};

const ReleaseConfig = struct {
    types: []const ChangelogType,
    header: []const u8,
    tag_prefix: []const u8,
    changelog_file: []const u8,
    commit_url_format: []const u8,
    compare_url_format: []const u8,
    issue_url_format: []const u8,
    user_url_format: []const u8,
    release_commit_message_format: []const u8,
    issue_prefixes: []const []const u8,
    version_files: []const VersionFileRule,
    skip: SkipConfig,
};

const CliConfig = struct {
    repo_url: []const u8 = "",
    bump: []const u8 = "patch",
    config_path: []const u8 = "zig-release.json",
};

const TemplateValues = struct {
    hash: ?[]const u8 = null,
    previousTag: ?[]const u8 = null,
    currentTag: ?[]const u8 = null,
    version: ?[]const u8 = null,
    user: ?[]const u8 = null,
    id: ?[]const u8 = null,
};

const default_types = [_]ChangelogType{
    .{ .type_name = "feat", .section = "✨ 新功能" },
    .{ .type_name = "fix", .section = "🐛 Bug 修复" },
    .{ .type_name = "docs", .section = "📝 文档" },
    .{ .type_name = "refactor", .section = "♻️ 重构" },
    .{ .type_name = "perf", .section = "⚡ 性能优化" },
    .{ .type_name = "ci", .section = "👷 CI/CD" },
    .{ .type_name = "chore", .section = "🔧 其他" },
};

const default_issue_prefixes = [_][]const u8{"#"};
const empty_version_files = [_]VersionFileRule{};

const Errors = error{
    InvalidConfig,
    MissingVersionPlaceholder,
    MultipleVersionPlaceholders,
    UnknownTemplateToken,
    MissingTemplateValue,
    VersionPatternNotFound,
    AmbiguousVersionPattern,
    GitFailed,
};

var io_instance: ?std.Io = null;

fn defaultReleaseConfig() ReleaseConfig {
    return .{
        .types = default_types[0..],
        .header = "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n",
        .tag_prefix = "v",
        .changelog_file = "CHANGELOG.md",
        .commit_url_format = "",
        .compare_url_format = "",
        .issue_url_format = "",
        .user_url_format = "",
        .release_commit_message_format = "chore(release): {{currentTag}}",
        .issue_prefixes = default_issue_prefixes[0..],
        .version_files = empty_version_files[0..],
        .skip = .{},
    };
}

fn getIo() std.Io {
    if (io_instance) |io| return io;
    const threaded = std.Io.Threaded.global_single_threaded;
    threaded.allocator = std.heap.page_allocator;
    const io = threaded.*.io();
    io_instance = io;
    return io;
}

fn print(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.allocPrint(alloc, fmt, args) catch return;
    std.Io.File.stdout().writeStreamingAll(getIo(), s) catch {};
}

fn readLine() ?u8 {
    var buf: [8]u8 = undefined;
    const slice: []u8 = &buf;
    const n = std.Io.File.stdin().readStreaming(getIo(), &.{slice}) catch return null;
    if (n == 0) return null;
    return buf[0];
}

fn git(alloc: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    const io = getIo();
    var full: std.ArrayListUnmanaged([]const u8) = .empty;
    defer full.deinit(alloc);
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
        .exited => |code| if (code != 0) return Errors.GitFailed,
        else => return Errors.GitFailed,
    }
    return std.mem.trim(u8, buf.items, " \n\r");
}

pub fn parseVersion(s: []const u8, tag_prefix: []const u8) [3]u32 {
    var trimmed = std.mem.trim(u8, s, " \n\r");
    if (tag_prefix.len > 0 and std.mem.startsWith(u8, trimmed, tag_prefix)) {
        trimmed = trimmed[tag_prefix.len..];
    } else if (std.mem.startsWith(u8, trimmed, "v")) {
        trimmed = trimmed[1..];
    }
    var it = std.mem.splitScalar(u8, trimmed, '.');
    return .{
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
        std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0,
    };
}

pub fn bumpVersion(v: [3]u32, bump: []const u8, tag_prefix: []const u8) [3]u32 {
    if (std.mem.eql(u8, bump, "major")) return .{ v[0] + 1, 0, 0 };
    if (std.mem.eql(u8, bump, "minor")) return .{ v[0], v[1] + 1, 0 };
    if (std.mem.eql(u8, bump, "patch")) return .{ v[0], v[1], v[2] + 1 };
    return parseVersion(bump, tag_prefix);
}

fn formatVersion(alloc: std.mem.Allocator, v: [3]u32) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{d}.{d}.{d}", .{ v[0], v[1], v[2] });
}

fn formatTag(alloc: std.mem.Allocator, tag_prefix: []const u8, v: [3]u32) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}{d}.{d}.{d}", .{ tag_prefix, v[0], v[1], v[2] });
}

/// Matches "type:", "type(scope):", but not "typewriter" or "fixture".
fn matchesType(msg: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, msg, prefix)) return false;
    if (msg.len <= prefix.len) return false;
    const next = msg[prefix.len];
    return next == ':' or next == '(';
}

fn parseJsonObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => Errors.InvalidConfig,
    };
}

fn parseJsonArray(value: std.json.Value) !std.json.Array {
    return switch (value) {
        .array => |items| items,
        else => Errors.InvalidConfig,
    };
}

fn parseJsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => Errors.InvalidConfig,
    };
}

fn parseJsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |flag| flag,
        else => Errors.InvalidConfig,
    };
}

fn dupString(alloc: std.mem.Allocator, text: []const u8) ![]const u8 {
    return try alloc.dupe(u8, text);
}

fn parseTypes(alloc: std.mem.Allocator, value: std.json.Value) ![]const ChangelogType {
    const array = try parseJsonArray(value);
    const items = try alloc.alloc(ChangelogType, array.items.len);
    for (array.items, 0..) |entry, i| {
        const object = try parseJsonObject(entry);
        const type_name = try parseJsonString(object.get("type") orelse return Errors.InvalidConfig);
        const section = try parseJsonString(object.get("section") orelse return Errors.InvalidConfig);
        items[i] = .{
            .type_name = try dupString(alloc, type_name),
            .section = try dupString(alloc, section),
        };
    }
    return items;
}

fn parseIssuePrefixes(alloc: std.mem.Allocator, value: std.json.Value) ![]const []const u8 {
    const array = try parseJsonArray(value);
    const items = try alloc.alloc([]const u8, array.items.len);
    for (array.items, 0..) |entry, i| {
        items[i] = try dupString(alloc, try parseJsonString(entry));
    }
    return items;
}

fn parseVersionFiles(alloc: std.mem.Allocator, value: std.json.Value) ![]const VersionFileRule {
    const array = try parseJsonArray(value);
    const items = try alloc.alloc(VersionFileRule, array.items.len);
    for (array.items, 0..) |entry, i| {
        const object = try parseJsonObject(entry);
        const path = try parseJsonString(object.get("path") orelse return Errors.InvalidConfig);
        const pattern = try parseJsonString(object.get("pattern") orelse return Errors.InvalidConfig);
        items[i] = .{
            .path = try dupString(alloc, path),
            .pattern = try dupString(alloc, pattern),
        };
    }
    return items;
}

fn mergeReleaseConfigObject(alloc: std.mem.Allocator, cfg: *ReleaseConfig, root: std.json.ObjectMap) !void {
    if (root.get("types")) |value| {
        cfg.types = try parseTypes(alloc, value);
    }
    if (root.get("header")) |value| {
        cfg.header = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("tagPrefix")) |value| {
        cfg.tag_prefix = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("changelogFile")) |value| {
        cfg.changelog_file = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("commitUrlFormat")) |value| {
        cfg.commit_url_format = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("compareUrlFormat")) |value| {
        cfg.compare_url_format = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("issueUrlFormat")) |value| {
        cfg.issue_url_format = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("userUrlFormat")) |value| {
        cfg.user_url_format = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("releaseCommitMessageFormat")) |value| {
        cfg.release_commit_message_format = try dupString(alloc, try parseJsonString(value));
    }
    if (root.get("issuePrefixes")) |value| {
        cfg.issue_prefixes = try parseIssuePrefixes(alloc, value);
    }
    if (root.get("versionFiles")) |value| {
        cfg.version_files = try parseVersionFiles(alloc, value);
    }
    if (root.get("skip")) |value| {
        const skip_object = try parseJsonObject(value);
        if (skip_object.get("changelog")) |skip_value| {
            cfg.skip.changelog = try parseJsonBool(skip_value);
        }
    }
}

fn loadReleaseConfig(alloc: std.mem.Allocator, config_path: []const u8) !ReleaseConfig {
    var cfg = defaultReleaseConfig();
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        getIo(),
        config_path,
        alloc,
        std.Io.Limit.limited(1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => return cfg,
        else => return err,
    };

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, bytes, .{});
    const root = try parseJsonObject(parsed.value);
    try mergeReleaseConfigObject(alloc, &cfg, root);
    return cfg;
}

fn templateValue(values: TemplateValues, token: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, token, "hash")) return values.hash;
    if (std.mem.eql(u8, token, "previousTag")) return values.previousTag;
    if (std.mem.eql(u8, token, "currentTag")) return values.currentTag;
    if (std.mem.eql(u8, token, "version")) return values.version;
    if (std.mem.eql(u8, token, "user")) return values.user;
    if (std.mem.eql(u8, token, "id")) return values.id;
    return null;
}

fn renderTemplate(alloc: std.mem.Allocator, template: []const u8, values: TemplateValues) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var i: usize = 0;
    while (i < template.len) {
        if (i + 1 < template.len and template[i] == '{' and template[i + 1] == '{') {
            const end_rel = std.mem.indexOf(u8, template[i + 2 ..], "}}") orelse return Errors.UnknownTemplateToken;
            const end = i + 2 + end_rel;
            const token = template[i + 2 .. end];
            const value = templateValue(values, token) orelse return Errors.MissingTemplateValue;
            try buf.appendSlice(alloc, value);
            i = end + 2;
            continue;
        }
        try buf.append(alloc, template[i]);
        i += 1;
    }

    const out = try alloc.dupe(u8, buf.items);
    buf.deinit(alloc);
    return out;
}

fn defaultCommitUrl(alloc: std.mem.Allocator, repo_url: []const u8, hash: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}/commit/{s}", .{ repo_url, hash });
}

fn defaultReleaseUrl(alloc: std.mem.Allocator, repo_url: []const u8, current_tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}/releases/tag/{s}", .{ repo_url, current_tag });
}

fn defaultCompareUrl(alloc: std.mem.Allocator, repo_url: []const u8, previous_tag: []const u8, current_tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}/compare/{s}...{s}", .{ repo_url, previous_tag, current_tag });
}

fn isUserChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

fn matchIssueAt(message: []const u8, index: usize, prefixes: []const []const u8) ?struct {
    matched_len: usize,
    id: []const u8,
    display: []const u8,
} {
    for (prefixes) |prefix| {
        if (!std.mem.startsWith(u8, message[index..], prefix)) continue;
        var cursor = index + prefix.len;
        const start = cursor;
        while (cursor < message.len and std.ascii.isDigit(message[cursor])) : (cursor += 1) {}
        if (cursor == start) continue;
        return .{
            .matched_len = cursor - index,
            .id = message[start..cursor],
            .display = message[index..cursor],
        };
    }
    return null;
}

fn matchUserAt(message: []const u8, index: usize) ?struct {
    matched_len: usize,
    user: []const u8,
    display: []const u8,
} {
    if (message[index] != '@') return null;
    if (index > 0 and isUserChar(message[index - 1])) return null;

    var cursor = index + 1;
    const start = cursor;
    while (cursor < message.len and isUserChar(message[cursor])) : (cursor += 1) {}
    if (cursor == start) return null;
    return .{
        .matched_len = cursor - index,
        .user = message[start..cursor],
        .display = message[index..cursor],
    };
}

fn linkifyMessage(alloc: std.mem.Allocator, message: []const u8, config: ReleaseConfig) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var i: usize = 0;
    while (i < message.len) {
        if (config.issue_url_format.len > 0) {
            if (matchIssueAt(message, i, config.issue_prefixes)) |issue| {
                const url = try renderTemplate(alloc, config.issue_url_format, .{ .id = issue.id });
                defer alloc.free(url);
                try buf.appendSlice(alloc, "[");
                try buf.appendSlice(alloc, issue.display);
                try buf.appendSlice(alloc, "](");
                try buf.appendSlice(alloc, url);
                try buf.appendSlice(alloc, ")");
                i += issue.matched_len;
                continue;
            }
        }

        if (config.user_url_format.len > 0) {
            if (matchUserAt(message, i)) |user| {
                const url = try renderTemplate(alloc, config.user_url_format, .{ .user = user.user });
                defer alloc.free(url);
                try buf.appendSlice(alloc, "[");
                try buf.appendSlice(alloc, user.display);
                try buf.appendSlice(alloc, "](");
                try buf.appendSlice(alloc, url);
                try buf.appendSlice(alloc, ")");
                i += user.matched_len;
                continue;
            }
        }

        try buf.append(alloc, message[i]);
        i += 1;
    }

    const out = try alloc.dupe(u8, buf.items);
    buf.deinit(alloc);
    return out;
}

fn generateChangelog(
    alloc: std.mem.Allocator,
    config: ReleaseConfig,
    repo_url: []const u8,
    previous_tag: []const u8,
    current_tag: []const u8,
    version: []const u8,
    date: []const u8,
    log: []const u8,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    try buf.appendSlice(alloc, "## [");
    try buf.appendSlice(alloc, current_tag);
    if (config.compare_url_format.len > 0) {
        const compare_url = try renderTemplate(alloc, config.compare_url_format, .{
            .previousTag = previous_tag,
            .currentTag = current_tag,
            .version = version,
        });
        defer alloc.free(compare_url);
        try buf.appendSlice(alloc, "](");
        try buf.appendSlice(alloc, compare_url);
        try buf.appendSlice(alloc, ")");
    } else if (repo_url.len > 0) {
        const release_url = try defaultReleaseUrl(alloc, repo_url, current_tag);
        defer alloc.free(release_url);
        try buf.appendSlice(alloc, "](");
        try buf.appendSlice(alloc, release_url);
        try buf.appendSlice(alloc, ")");
    } else {
        try buf.appendSlice(alloc, "]");
    }
    try buf.appendSlice(alloc, " (");
    try buf.appendSlice(alloc, date);
    try buf.appendSlice(alloc, ")\n");

    for (config.types) |section| {
        var found = false;
        var lines = std.mem.splitScalar(u8, log, '\n');
        while (lines.next()) |line| {
            if (line.len < 42) continue;
            const hash = line[0..40];
            const msg = line[41..];
            if (!matchesType(msg, section.type_name)) continue;

            if (!found) {
                try buf.appendSlice(alloc, "\n### ");
                try buf.appendSlice(alloc, section.section);
                try buf.appendSlice(alloc, "\n\n");
                found = true;
            }

            const linked_message = try linkifyMessage(alloc, msg, config);
            defer alloc.free(linked_message);
            try buf.appendSlice(alloc, "- ");
            try buf.appendSlice(alloc, linked_message);

            if (config.commit_url_format.len > 0) {
                const commit_url = try renderTemplate(alloc, config.commit_url_format, .{ .hash = hash });
                defer alloc.free(commit_url);
                try buf.appendSlice(alloc, " ([");
                try buf.appendSlice(alloc, hash[0..7]);
                try buf.appendSlice(alloc, "](");
                try buf.appendSlice(alloc, commit_url);
                try buf.appendSlice(alloc, "))");
            } else if (repo_url.len > 0) {
                const commit_url = try defaultCommitUrl(alloc, repo_url, hash);
                defer alloc.free(commit_url);
                try buf.appendSlice(alloc, " ([");
                try buf.appendSlice(alloc, hash[0..7]);
                try buf.appendSlice(alloc, "](");
                try buf.appendSlice(alloc, commit_url);
                try buf.appendSlice(alloc, "))");
            }

            try buf.append(alloc, '\n');
        }
    }

    const out = try alloc.dupe(u8, buf.items);
    buf.deinit(alloc);
    return out;
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const io = getIo();
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, content);
}

fn readFile(alloc: std.mem.Allocator, path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(getIo(), path, alloc, std.Io.Limit.limited(1024 * 1024)) catch null;
}

fn detectRepoUrl(alloc: std.mem.Allocator) []const u8 {
    const remote = git(alloc, &.{ "remote", "get-url", "origin" }) catch return "";
    if (std.mem.endsWith(u8, remote, ".git")) return remote[0 .. remote.len - 4];
    return remote;
}

fn parseArgs(init: std.process.Init, alloc: std.mem.Allocator) CliConfig {
    var args_it = std.process.Args.Iterator.initAllocator(init.minimal.args, alloc) catch return .{};
    _ = args_it.next();

    var cfg = CliConfig{};
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--repo")) {
            cfg.repo_url = args_it.next() orelse "";
        } else if (std.mem.eql(u8, arg, "--config")) {
            cfg.config_path = args_it.next() orelse cfg.config_path;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            cfg.bump = arg;
        }
    }
    return cfg;
}

fn splitPattern(pattern: []const u8) !struct { prefix: []const u8, suffix: []const u8 } {
    const placeholder = "{{version}}";
    const first = std.mem.indexOf(u8, pattern, placeholder) orelse return Errors.MissingVersionPlaceholder;
    if (std.mem.indexOfPos(u8, pattern, first + placeholder.len, placeholder) != null) {
        return Errors.MultipleVersionPlaceholders;
    }
    return .{
        .prefix = pattern[0..first],
        .suffix = pattern[first + placeholder.len ..],
    };
}

fn replaceVersionByPattern(alloc: std.mem.Allocator, content: []const u8, pattern: []const u8, version: []const u8) ![]const u8 {
    const parts = try splitPattern(pattern);

    var match_start: ?usize = null;
    var match_end: ?usize = null;
    var search_from: usize = 0;

    while (std.mem.indexOfPos(u8, content, search_from, parts.prefix)) |prefix_start| {
        const value_start = prefix_start + parts.prefix.len;
        const suffix_rel = std.mem.indexOfPos(u8, content, value_start, parts.suffix) orelse {
            search_from = prefix_start + 1;
            continue;
        };

        if (match_start != null) return Errors.AmbiguousVersionPattern;

        match_start = value_start;
        match_end = suffix_rel;
        search_from = prefix_start + 1;
    }

    if (match_start == null or match_end == null) return Errors.VersionPatternNotFound;

    return std.fmt.allocPrint(alloc, "{s}{s}{s}", .{
        content[0..match_start.?],
        version,
        content[match_end.?..],
    });
}

fn updateFileVersion(alloc: std.mem.Allocator, path: []const u8, pattern: []const u8, version: []const u8) !void {
    const content = readFile(alloc, path) orelse return error.FileNotFound;
    const updated = try replaceVersionByPattern(alloc, content, pattern, version);
    try writeFile(path, updated);
}

fn trimLeadingNewlines(text: []const u8) []const u8 {
    var index: usize = 0;
    while (index < text.len and (text[index] == '\r' or text[index] == '\n')) : (index += 1) {}
    return text[index..];
}

fn updateChangelogFile(alloc: std.mem.Allocator, config: ReleaseConfig, changelog: []const u8) !void {
    if (config.skip.changelog) return;

    if (readFile(alloc, config.changelog_file)) |old| {
        if (config.header.len > 0 and std.mem.startsWith(u8, old, config.header)) {
            const rest = trimLeadingNewlines(old[config.header.len..]);
            const content = if (rest.len > 0)
                try std.fmt.allocPrint(alloc, "{s}{s}\n\n{s}\n", .{ config.header, changelog, rest })
            else
                try std.fmt.allocPrint(alloc, "{s}{s}\n", .{ config.header, changelog });
            try writeFile(config.changelog_file, content);
            return;
        }

        const content = try std.fmt.allocPrint(alloc, "{s}\n\n{s}\n", .{ changelog, old });
        try writeFile(config.changelog_file, content);
        return;
    }

    const content = if (config.header.len > 0)
        try std.fmt.allocPrint(alloc, "{s}{s}\n", .{ config.header, changelog })
    else
        try std.fmt.allocPrint(alloc, "{s}\n", .{changelog});
    try writeFile(config.changelog_file, content);
}

fn appendUnique(alloc: std.mem.Allocator, items: *std.ArrayListUnmanaged([]const u8), value: []const u8) !void {
    for (items.items) |existing| {
        if (std.mem.eql(u8, existing, value)) return;
    }
    try items.append(alloc, value);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const cli = parseArgs(init, alloc);
    const cfg = try loadReleaseConfig(alloc, cli.config_path);
    const repo_url = if (cli.repo_url.len > 0) cli.repo_url else detectRepoUrl(alloc);

    const latest_tag = git(alloc, &.{ "describe", "--tags", "--abbrev=0" }) catch try std.fmt.allocPrint(alloc, "{s}0.0.0", .{cfg.tag_prefix});
    const current = parseVersion(latest_tag, cfg.tag_prefix);
    const next = bumpVersion(current, cli.bump, cfg.tag_prefix);
    const version = try formatVersion(alloc, next);
    const current_tag = try formatTag(alloc, cfg.tag_prefix, next);
    const date = git(alloc, &.{ "log", "-1", "--format=%cd", "--date=short" }) catch "unknown";

    print(alloc, "\n当前版本: {s}\n新版本:   {s}\n\n", .{ latest_tag, current_tag });

    const range = try std.fmt.allocPrint(alloc, "{s}..HEAD", .{latest_tag});
    const log = git(alloc, &.{ "log", "--format=%H %s", range, "--no-merges" }) catch "";
    const changelog = try generateChangelog(alloc, cfg, repo_url, latest_tag, current_tag, version, date, log);

    print(alloc, "--- CHANGELOG 预览 ---\n{s}\n----------------------\n\n确认发布 {s}? (y/N) ", .{ changelog, current_tag });

    const ch = readLine() orelse return;
    if (ch != 'y' and ch != 'Y') {
        print(alloc, "已取消\n", .{});
        return;
    }

    try updateChangelogFile(alloc, cfg, changelog);
    try updateFileVersion(alloc, "build.zig.zon", ".version = \"{{version}}\"", version);
    for (cfg.version_files) |rule| {
        try updateFileVersion(alloc, rule.path, rule.pattern, version);
    }

    var add_paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer add_paths.deinit(alloc);
    if (!cfg.skip.changelog) try appendUnique(alloc, &add_paths, cfg.changelog_file);
    try appendUnique(alloc, &add_paths, "build.zig.zon");
    for (cfg.version_files) |rule| {
        try appendUnique(alloc, &add_paths, rule.path);
    }

    var add_args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer add_args.deinit(alloc);
    try add_args.append(alloc, "add");
    try add_args.appendSlice(alloc, add_paths.items);
    _ = try git(alloc, add_args.items);

    const commit_message = try renderTemplate(alloc, cfg.release_commit_message_format, .{
        .currentTag = current_tag,
        .previousTag = latest_tag,
        .version = version,
    });
    _ = try git(alloc, &.{ "commit", "-m", commit_message });
    _ = try git(alloc, &.{ "tag", current_tag });
    _ = try git(alloc, &.{ "push", "origin", "HEAD" });
    _ = try git(alloc, &.{ "push", "origin", current_tag });

    print(alloc, "\n✓ {s} 已发布！\n", .{current_tag});
    if (repo_url.len > 0) {
        print(alloc, "  Release: {s}/releases\n", .{repo_url});
    }
}

test "parseVersion trims prefix" {
    try std.testing.expectEqual([3]u32{ 1, 2, 3 }, parseVersion("v1.2.3", "v"));
    try std.testing.expectEqual([3]u32{ 1, 2, 3 }, parseVersion("release-1.2.3", "release-"));
    try std.testing.expectEqual([3]u32{ 0, 0, 0 }, parseVersion("", "v"));
}

test "bumpVersion" {
    try std.testing.expectEqual([3]u32{ 1, 2, 4 }, bumpVersion(.{ 1, 2, 3 }, "patch", "v"));
    try std.testing.expectEqual([3]u32{ 1, 3, 0 }, bumpVersion(.{ 1, 2, 3 }, "minor", "v"));
    try std.testing.expectEqual([3]u32{ 2, 0, 0 }, bumpVersion(.{ 1, 2, 3 }, "major", "v"));
    try std.testing.expectEqual([3]u32{ 5, 0, 0 }, bumpVersion(.{ 1, 2, 3 }, "5.0.0", "v"));
}

test "matchesType" {
    try std.testing.expect(matchesType("feat: add feature", "feat"));
    try std.testing.expect(matchesType("feat(scope): add feature", "feat"));
    try std.testing.expect(matchesType("fix: bug", "fix"));
    try std.testing.expect(!matchesType("feature: not a match", "feat"));
    try std.testing.expect(!matchesType("fixture: not a match", "fix"));
    try std.testing.expect(!matchesType("fe", "feat"));
}

test "renderTemplate substitutes known tokens" {
    const output = try renderTemplate(std.testing.allocator, "compare/{{previousTag}}...{{currentTag}}", .{
        .previousTag = "v1.0.0",
        .currentTag = "v1.1.0",
    });
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("compare/v1.0.0...v1.1.0", output);
}

test "replaceVersionByPattern updates one span" {
    const updated = try replaceVersionByPattern(
        std.testing.allocator,
        "pub const version = \"0.1.0\";\n",
        "pub const version = \"{{version}}\";",
        "0.2.0",
    );
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("pub const version = \"0.2.0\";\n", updated);
}

test "replaceVersionByPattern rejects ambiguous matches" {
    try std.testing.expectError(
        Errors.AmbiguousVersionPattern,
        replaceVersionByPattern(
            std.testing.allocator,
            "version = \"0.1.0\"\nversion = \"0.1.0\"\n",
            "version = \"{{version}}\"",
            "0.2.0",
        ),
    );
}

test "loadReleaseConfig parses custom sections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(),
        \\{
        \\  "types": [
        \\    { "type": "feat", "section": "新功能" }
        \\  ],
        \\  "releaseCommitMessageFormat": "release: {{currentTag}}",
        \\  "versionFiles": [
        \\    { "path": "src/version.zig", "pattern": "pub const version = \"{{version}}\";" }
        \\  ]
        \\}
    , .{});

    var cfg = defaultReleaseConfig();
    try mergeReleaseConfigObject(arena.allocator(), &cfg, try parseJsonObject(parsed.value));
    try std.testing.expectEqual(@as(usize, 1), cfg.types.len);
    try std.testing.expectEqualStrings("feat", cfg.types[0].type_name);
    try std.testing.expectEqualStrings("新功能", cfg.types[0].section);
    try std.testing.expectEqualStrings("release: {{currentTag}}", cfg.release_commit_message_format);
    try std.testing.expectEqual(@as(usize, 1), cfg.version_files.len);
}

test "generateChangelog uses config-driven links and sections" {
    const cfg = ReleaseConfig{
        .types = &.{.{ .type_name = "feat", .section = "新功能" }},
        .header = "",
        .tag_prefix = "v",
        .changelog_file = "CHANGELOG.md",
        .commit_url_format = "https://example.com/commit/{{hash}}",
        .compare_url_format = "https://example.com/compare/{{previousTag}}...{{currentTag}}",
        .issue_url_format = "https://example.com/issues/{{id}}",
        .user_url_format = "https://example.com/{{user}}",
        .release_commit_message_format = "chore(release): {{currentTag}}",
        .issue_prefixes = &[_][]const u8{"#"},
        .version_files = &.{},
        .skip = .{},
    };

    const log =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa feat: add thing for #12 by @sol\n" ++
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb fix: ignored";

    const result = try generateChangelog(
        std.testing.allocator,
        cfg,
        "https://example.com/repo",
        "v1.0.0",
        "v1.1.0",
        "1.1.0",
        "2026-04-29",
        log,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "### 新功能") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "compare/v1.0.0...v1.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "issues/12") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "example.com/sol") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "fix: ignored") == null);
}

test "formatTag" {
    const tag = try formatTag(std.testing.allocator, "v", .{ 2, 1, 0 });
    defer std.testing.allocator.free(tag);
    try std.testing.expectEqualStrings("v2.1.0", tag);
}
