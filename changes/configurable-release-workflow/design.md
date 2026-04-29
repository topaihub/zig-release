## Context

The current `zig-release` implementation is intentionally small: one source file, no external dependencies, and a single release path driven by git tags. That simplicity is worth preserving, but the configuration surface is too narrow for multi-project adoption.

The design must keep the existing defaults working while allowing repositories to opt into richer release metadata without adding a Node or Python runtime.

## Goals / Non-Goals

**Goals**

- Keep `zig-release` zero-dependency and cross-platform.
- Preserve current behavior when no config file is present.
- Support a repository-local JSON config file.
- Make changelog sections and link formats configurable.
- Support additional synchronized version files.
- Keep `addReleaseStep()` backward-compatible.
- Show one real consumer integration in `mowen-cli`.

**Non-Goals**

- Introduce a template engine, regex engine, or external config parser.
- Rewrite release creation to happen in GitHub Actions instead of the local tool.
- Add semantic analysis for arbitrary source files.
- Replace conventional-commit grouping with fully custom scripting.

## Decisions

1. Use an optional `zig-release.json` file in the project root.
   - Rationale: matches the user's existing workflow expectations and keeps config close to the consuming repo.
   - Compatibility: if the file is absent, the tool uses current built-in defaults.

2. Support a small JSON schema with explicit defaults instead of free-form scripting.
   - Rationale: deterministic behavior is easier to maintain across many Zig projects.
   - Scope: `types`, `header`, `tagPrefix`, `changelogFile`, `commitUrlFormat`, `compareUrlFormat`, `issueUrlFormat`, `userUrlFormat`, `releaseCommitMessageFormat`, `issuePrefixes`, `versionFiles`, and `skip`.

3. Use literal token replacement with `{{token}}` placeholders.
   - Rationale: enough power for common release links and commit messages without a real templating engine.
   - Expected tokens:
     - `{{hash}}`
     - `{{previousTag}}`
     - `{{currentTag}}`
     - `{{version}}`
     - `{{user}}`
     - `{{id}}`

4. Model `versionFiles` as literal replacement rules with a `pattern` that contains `{{version}}`.
   - Example:
     - `{"path":"src/version.zig","pattern":"pub const version = \"{{version}}\";"}`
   - Rationale: this is simpler and safer than regex while still flexible enough for common version constants.

5. Keep `build.zig.zon` version updates as the default release behavior.
   - Rationale: that is the current contract, and most Zig projects should still use it as the canonical source.
   - `versionFiles` are additive, not a replacement for `build.zig.zon`.

6. Use `mowen-cli` to demonstrate the target workflow, but prefer a single runtime version source there.
   - Rationale: `versionFiles` must exist for general consumers, but the first example should show the cleaner pattern: runtime `--version` derived from build metadata rather than a second hand-edited string.

## Config Shape

Proposed `zig-release.json` shape:

```json
{
  "types": [
    { "type": "feat", "section": "✨ 新功能" },
    { "type": "fix", "section": "🐛 Bug 修复" }
  ],
  "header": "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n",
  "tagPrefix": "v",
  "changelogFile": "CHANGELOG.md",
  "commitUrlFormat": "https://github.com/org/repo/commit/{{hash}}",
  "compareUrlFormat": "https://github.com/org/repo/compare/{{previousTag}}...{{currentTag}}",
  "issueUrlFormat": "https://github.com/org/repo/issues/{{id}}",
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

## Risks / Trade-offs

- JSON config drift across projects -> keep the schema narrow and document all defaults.
- Literal replacement can fail if a pattern is ambiguous -> require exactly one `{{version}}` placeholder and exactly one matching span per file.
- Link templating can become inconsistent -> provide stable defaults and validate missing tokens conservatively.
- Backward compatibility risk in `addReleaseStep()` -> keep the old API working unchanged and make new inputs optional.

## Migration Plan

1. Add config loading and default merging to `zig-release`.
2. Move current hard-coded changelog sections into default config values.
3. Replace fixed `CHANGELOG.md` / commit message logic with config-driven paths and templates.
4. Add `versionFiles` support and focused tests.
5. Update docs.
6. Migrate `mowen-cli`:
   - add `zig-release.json`
   - add `CHANGELOG.md`
   - remove changelog sections from README files
   - derive runtime version from build metadata

## Open Questions

- Should `skip` support `commit`, `tag`, or `push` in a follow-up change?
- Should unknown conventional commit types be omitted or grouped under a configurable fallback section?
- Should compare links be preferred over release-tag links in the changelog heading when `compareUrlFormat` is present?
