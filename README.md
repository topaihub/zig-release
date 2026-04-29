[中文](README_CN.md) | English

# zig-release

Cross-platform release tool for Zig projects. Auto-generates CHANGELOG, bumps version, tags, and pushes to trigger CI.

Zero external dependencies. Pure Zig. Works on Windows/Linux/macOS.

## Usage in Your Project

### 1. Add dependency

`build.zig.zon`:

```zig
.@"zig-release" = .{
    .url = "https://github.com/topaihub/zig-release/archive/{COMMIT_HASH}.tar.gz",
    .hash = "...",
},
```

### 2. Add release step

`build.zig`:

```zig
const release_dep = b.dependency("zig-release", .{});
const zig_release = @import("zig-release");
zig_release.addReleaseStep(b, release_dep, .{});
```

To specify a repo URL or a custom config path:

```zig
zig_release.addReleaseStep(b, release_dep, .{
    .repo_url = "https://github.com/yourname/yourproject",
    .config_path = "zig-release.json",
});
```

### 3. Release

```bash
zig build release -- patch    # v1.0.0 -> v1.0.1
zig build release -- minor    # v1.0.0 -> v1.1.0
zig build release -- major    # v1.0.0 -> v2.0.0
zig build release -- 2.5.0    # specify version directly
```

## Configuration

If `zig-release.json` exists in the project root, `zig-release` loads it and merges it with built-in defaults.

Example:

```json
{
  "types": [
    { "type": "feat", "section": "✨ New Features" },
    { "type": "fix", "section": "🐛 Bug Fixes" },
    { "type": "docs", "section": "📝 Documentation" }
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

### Config fields

- `types`: changelog grouping based on conventional commit type
- `header`: text written at the top of a new changelog file
- `tagPrefix`: release tag prefix, default `v`
- `changelogFile`: dedicated changelog file path, default `CHANGELOG.md`
- `commitUrlFormat`: commit link template
- `compareUrlFormat`: release heading compare link template
- `issueUrlFormat`: issue reference link template
- `userUrlFormat`: user mention link template
- `releaseCommitMessageFormat`: release commit message template
- `issuePrefixes`: issue prefixes to recognize, default `["#"]`
- `versionFiles`: additional version-bearing files to update using a literal `pattern` with `{{version}}`
- `skip.changelog`: skip changelog file writes

## What It Does

1. Gets current version from latest git tag
2. Calculates new version
3. Generates `CHANGELOG.md` from git log (grouped by conventional commits, with configurable sections and links)
4. Shows preview and asks for confirmation
5. Updates `CHANGELOG.md`
6. Updates version in `build.zig.zon`
7. Optionally updates additional configured `versionFiles`
7. git commit → tag → push
8. Triggers GitHub Actions / CI build

## Commit Categories

| Prefix | Category |
|--------|----------|
| `feat` | ✨ New Features |
| `fix` | 🐛 Bug Fixes |
| `docs` | 📝 Documentation |
| `refactor` | ♻️ Refactoring |
| `perf` | ⚡ Performance |
| `ci` | 👷 CI/CD |
| `chore` | 🔧 Other |

## Notes

- Existing behavior stays the same if `zig-release.json` is missing.
- The recommended consumer workflow is a dedicated `CHANGELOG.md`; keep release history out of README files.
- `versionFiles` are best used for projects that still need an extra version constant. New projects should prefer a single source of truth from `build.zig.zon`.

## Requirements

- Zig 0.16.0+
- Git

## License

MIT
