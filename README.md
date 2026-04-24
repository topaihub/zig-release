# zig-release

Zig 项目的跨平台发布工具。自动生成 CHANGELOG、更新版本号、打 tag、推送触发 CI。

零外部依赖，纯 Zig，Windows/Linux/macOS 通用。

## 在你的项目中使用

### 1. 添加依赖

`build.zig.zon`:

```zig
.dependencies = .{
    .@"zig-release" = .{
        .url = "https://github.com/topaihub/zig-release/archive/{COMMIT_HASH}.tar.gz",
        .hash = "...",
    },
},
```

### 2. 添加 release 命令

`build.zig`:

```zig
const release_dep = b.dependency("zig-release", .{});
const zig_release = @import("zig-release");
zig_release.addReleaseStep(b, release_dep, .{});
```

如果需要指定仓库 URL（默认自动从 git remote 检测）：

```zig
zig_release.addReleaseStep(b, release_dep, .{
    .repo_url = "https://github.com/yourname/yourproject",
});
```

### 3. 发布

```bash
zig build release -- patch    # v1.0.0 -> v1.0.1
zig build release -- minor    # v1.0.0 -> v1.1.0
zig build release -- major    # v1.0.0 -> v2.0.0
zig build release -- 2.5.0    # 直接指定版本号
```

## 它做了什么

1. 从 git tag 获取当前版本
2. 计算新版本号
3. 从 git log 生成 CHANGELOG（按 conventional commits 分类，带 emoji）
4. 预览让你确认
5. 更新 `CHANGELOG.md`
6. 更新 `build.zig.zon` 中的版本号
7. git commit → tag → push
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

## 要求

- Zig 0.16.0+
- Git

## License

MIT
