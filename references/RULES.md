# zig-release 开发规则

## 红线

1. **零外部依赖** — 只依赖 Zig 标准库和 git
2. **跨平台** — Windows/Linux/macOS 行为一致
3. **不自动推送** — 必须用户确认后才执行 git push
4. **不修改用户代码** — 只改 CHANGELOG.md 和 build.zig.zon 的版本号

## 验证命令

```bash
zig build
zig build test
```

## 架构

```
zig-release/
├── src/main.zig    # 完整实现（解析参数、git 操作、changelog 生成、文件更新）
├── build.zig       # 构建脚本 + addReleaseStep 公共 API
└── build.zig.zon   # 包元数据
```

## 公共 API

`build.zig` 导出 `addReleaseStep()`，供其他项目在 build.zig 中调用。
修改此函数签名时注意向后兼容。
