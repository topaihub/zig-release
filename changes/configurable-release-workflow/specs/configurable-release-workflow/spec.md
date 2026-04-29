## ADDED Requirements

### Requirement: Optional release config file
`zig-release` SHALL support an optional `zig-release.json` file in the target repository root. When the file is absent, the tool SHALL preserve the current default behavior.

#### Scenario: No config file present
- **WHEN** a repository does not contain `zig-release.json`
- **THEN** `zig-release` SHALL use its built-in default changelog sections, header, changelog file path, tag prefix, and release commit message

#### Scenario: Config file present
- **WHEN** a repository contains `zig-release.json`
- **THEN** `zig-release` SHALL merge that file with the built-in defaults and use the configured values for the release

### Requirement: Configurable changelog sections
`zig-release` SHALL support configurable changelog section mapping from conventional commit types to section titles.

#### Scenario: Custom feature section title
- **WHEN** `zig-release.json` maps `feat` to a custom section title
- **THEN** generated changelog entries for `feat:` commits SHALL be grouped under that configured title

#### Scenario: Default grouping still works
- **WHEN** no custom type mapping is provided
- **THEN** `feat`, `fix`, `docs`, `refactor`, `perf`, `ci`, and `chore` SHALL continue to group under the existing default sections

### Requirement: Configurable changelog links and header
`zig-release` SHALL support configurable changelog header text and URL templates for commit links and compare links.

#### Scenario: Configured commit URL format
- **WHEN** `commitUrlFormat` is configured
- **THEN** commit references in generated changelog entries SHALL use that template with `{{hash}}` substituted

#### Scenario: Configured compare URL format
- **WHEN** `compareUrlFormat` is configured
- **THEN** the generated release heading SHALL link the release title using `{{previousTag}}` and `{{currentTag}}`

#### Scenario: Configured header text
- **WHEN** `zig-release` creates a new changelog file
- **THEN** it SHALL use the configured `header` text before the first generated release entry

### Requirement: Configurable release commit message
`zig-release` SHALL support a configurable release commit message template.

#### Scenario: Custom release commit message
- **WHEN** `releaseCommitMessageFormat` is configured
- **THEN** the release commit message SHALL use that template with `{{currentTag}}` substituted

### Requirement: Additional version file synchronization
`zig-release` SHALL support synchronizing version strings in additional files through `versionFiles`.

#### Scenario: Additional version file updated
- **WHEN** `versionFiles` contains an entry with `path` and a `pattern` containing `{{version}}`
- **THEN** `zig-release` SHALL update the matched version span in that file to the new release version

#### Scenario: Default package version still updates
- **WHEN** a release is executed
- **THEN** `zig-release` SHALL continue updating `.version` in `build.zig.zon`

#### Scenario: Invalid version file rule fails safely
- **WHEN** a `versionFiles` rule does not match exactly one version span
- **THEN** `zig-release` SHALL fail the release before commit/tag/push rather than silently writing a partial result

### Requirement: Dedicated changelog file workflow
Consumer repositories using `zig-release` SHALL be able to keep release history in `CHANGELOG.md` without duplicating that history inside README files.

#### Scenario: Consumer repository uses dedicated changelog
- **WHEN** a consumer repository adopts `zig-release` with a configured changelog file
- **THEN** the release workflow SHALL write release history to `CHANGELOG.md` and SHALL not require README-embedded changelog sections
