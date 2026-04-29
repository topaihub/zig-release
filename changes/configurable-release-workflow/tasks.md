## 1. OpenSpec and config model

- [x] 1.1 Add the OpenSpec change artifacts for configurable release workflow.
- [x] 1.2 Define the runtime config model and defaults for `zig-release.json`.
- [x] 1.3 Add parsing and merge logic so missing config preserves current behavior.

## 2. Configurable changelog generation

- [x] 2.1 Replace hard-coded section labels with config-driven type mappings.
- [x] 2.2 Add token-based templating for changelog header, commit links, compare links, and release commit messages.
- [x] 2.3 Keep conventional-commit grouping semantics stable when config is absent.

## 3. Version synchronization

- [x] 3.1 Preserve automatic `build.zig.zon` version updates.
- [x] 3.2 Add `versionFiles` support using literal `pattern` entries with `{{version}}`.
- [x] 3.3 Fail safely when a configured version pattern is missing or ambiguous.

## 4. Public API, tests, and docs

- [x] 4.1 Keep `addReleaseStep()` backward-compatible and add optional config-path support only if needed.
- [x] 4.2 Extend unit tests for config parsing, templating, changelog generation, and version-file replacement.
- [x] 4.3 Update `README.md` and `README_CN.md` with the new release workflow and config examples.

## 5. Consumer example: mowen-cli

- [x] 5.1 Add a dedicated `CHANGELOG.md` and remove changelog sections from `README.md` and `README_CN.md`.
- [x] 5.2 Add a `zig-release.json` example that matches the repository's conventions.
- [x] 5.3 Change runtime version output to use a single source of truth derived from build metadata.
- [x] 5.4 Verify the updated consumer still passes its build/test/version/help checks.
