## Why

`zig-release` already covers the happy path for a single repository, but its current changelog and versioning behavior is hard-coded:

- commit sections are fixed in source code
- changelog header and link formats are not configurable
- only `CHANGELOG.md` and `build.zig.zon` are updated
- consumer projects still need ad-hoc fixes for runtime version strings

That is not a good organizational baseline for a growing set of Zig projects. We need a reusable release workflow that keeps Zig's zero-dependency approach while offering the same practical flexibility teams already expect from tools like `standard-version`.

## What Changes

- Add optional `zig-release.json` support with safe defaults that preserve current behavior.
- Make changelog generation configurable:
  - section/type mapping
  - header text
  - tag prefix
  - changelog output file
  - commit / compare / issue / user URL templates
  - release commit message format
- Add `versionFiles` so projects can update additional version-bearing files beyond `build.zig.zon`.
- Keep `zig build release -- patch|minor|major` as the primary workflow.
- Use `mowen-cli` as the first consumer example:
  - remove changelog content from README files
  - add a dedicated `CHANGELOG.md`
  - wire runtime `--version` output to a single source of truth

## Capabilities

### New Capabilities

- `configurable-release-workflow`: per-project configurable changelog and version synchronization for Zig releases.

### Modified Capabilities

- `release-step-api`: `addReleaseStep()` remains backward-compatible while gaining optional config-path support if needed.

## Impact

- `zig-release/src/main.zig` for config parsing, templating, changelog generation, and version file updates
- `zig-release/build.zig` public release-step surface
- `zig-release/README.md` and `README_CN.md`
- `mowen-cli` release integration and documentation
