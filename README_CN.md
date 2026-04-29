中文 | [English](README.md)

# zig-release

Zig 项目的跨平台发布工具。自动生成 CHANGELOG、更新版本号、打 tag、推送触发 CI。

零外部依赖，纯 Zig，Windows/Linux/macOS 通用。

## 在你的项目中使用

### 1. 添加依赖

`build.zig.zon`:

```zig
.@"zig-release" = .{
    .url = "https://github.com/topaihub/zig-release/archive/{COMMIT_HASH}.tar.gz",
    .hash = "...",
},
```

### 2. 添加 release 命令

`build.zig`:

```zig
const release_dep = b.dependency("zig-release", .{});
const zig_release = @import("zig-release");
zig_release.addReleaseStep(b, release_dep, .{});
```

如果需要指定仓库 URL 或自定义配置路径：

```zig
zig_release.addReleaseStep(b, release_dep, .{
    .repo_url = "https://github.com/yourname/yourproject",
    .config_path = "zig-release.json",
});
```

### 3. 发布

```bash
zig build release -- patch    # v1.0.0 -> v1.0.1
zig build release -- minor    # v1.0.0 -> v1.1.0
zig build release -- major    # v1.0.0 -> v2.0.0
zig build release -- 2.5.0    # 直接指定版本号
```

## 配置

如果项目根目录存在 `zig-release.json`，`zig-release` 会读取它，并与内置默认值合并。

示例：

```json
{
  "types": [
    { "type": "feat", "section": "✨ 新功能" },
    { "type": "fix", "section": "🐛 Bug 修复" },
    { "type": "docs", "section": "📝 文档" }
  ],
  "header": "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n",
  "tagPrefix": "v",
  "changelogFile": "CHANGELOG.md",
  "commitUrlFormat": "https://github.com/yourname/yourproject/commit/{{hash}}",
  "compareUrlFormat": "https://github.com/yourname/yourproject/compare/{{previousTag}}...{{currentTag}}",
  "issueUrlFormat": "https://github.com/yourname/yourproject/issues/{{id}}",
  "userUrlFormat": "https://github.com/{{user}}",
  "releaseCommitMessageFormat": "chore(release): {{currentTag}}",
  "issuePrefixes": ["#"],
  "versionFiles": [
    {
      "path": "src/version.zig",
      "pattern": "pub const version = \"{{version}}\";"
    }
  ],
  "skip": {
    "changelog": false
  }
}
```

### 配置字段

- `types`：按 conventional commit 类型分组 changelog
- `header`：新建 changelog 文件时写入顶部的文本
- `tagPrefix`：tag 前缀，默认 `v`
- `changelogFile`：专用 changelog 文件路径，默认 `CHANGELOG.md`
- `commitUrlFormat`：commit 链接模板
- `compareUrlFormat`：版本标题 compare 链接模板
- `issueUrlFormat`：issue 引用链接模板
- `userUrlFormat`：用户提及链接模板
- `releaseCommitMessageFormat`：release commit 消息模板
- `issuePrefixes`：识别 issue 的前缀，默认 `["#"]`
- `versionFiles`：额外需要同步版本号的文件，使用包含 `{{version}}` 的字面量 `pattern`
- `skip.changelog`：跳过 changelog 文件写入

## 它做了什么

1. 从 git tag 获取当前版本
2. 计算新版本号
3. 从 git log 生成 `CHANGELOG.md`（按 conventional commits 分类，支持自定义分组和链接）
4. 预览让你确认
5. 更新 `CHANGELOG.md`
6. 更新 `build.zig.zon` 中的版本号
7. 按配置更新额外的 `versionFiles`
8. git commit → tag → push
8. 触发 GitHub Actions / CI 构建发布

## Commit 分类

| 前缀 | 分类 |
|------|------|
| `feat` | ✨ 新功能 |
| `fix` | 🐛 Bug 修复 |
| `docs` | 📝 文档 |
| `refactor` | ♻️ 重构 |
| `perf` | ⚡ 性能优化 |
| `ci` | 👷 CI/CD |
| `chore` | 🔧 其他 |

## 说明

- 如果没有 `zig-release.json`，现有行为保持不变。
- 推荐消费端使用独立的 `CHANGELOG.md`，不要把发布历史嵌进 README。
- `versionFiles` 适合仍然需要额外版本常量的项目；新项目更推荐把 `build.zig.zon` 作为唯一版本来源。

## 要求

- Zig 0.16.0+
- Git

## License

MIT
