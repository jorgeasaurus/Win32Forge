- [x] Read the `powershell-module-scaffold` skill and compare it to the current repo.
- [x] Apply scaffold support needed for packaging, CI, analyzer, tests, and release.
- [x] Restore build bootstrap behavior and align CI with the module workflow.
- [x] Verify analyzer, tests, build, workflow YAML, and docs checks.
- [x] Record review results.

## Review

- Kept scaffold essentials for module packaging, CI, analyzer settings, tests, and PowerShell Gallery release.
- Removed duplicate editor support, formatter wrapper, and workflow trigger docs during release polish.
- Kept `build.ps1` default bootstrap behavior while keeping the leaner module loader/runtime structure.
- Verified parser pass on 11 PowerShell files, PSScriptAnalyzer, 13 Pester tests, module build, workflow YAML, docs anchors/copy targets, manifest validation, and final cleanup of generated `build/`.

## Release polish

- [x] Split GitHub Pages CSS and JavaScript out of `docs/index.html`.
- [x] Tighten detection rule parameter typing and conversion structure.
- [x] Remove repeated dependency bootstrap from build task runs and CI.
- [x] Delete duplicate repo-local editor, formatter, and workflow trigger scaffolding.
- [x] Verify parser, analyzer, tests, build, docs links/assets, and clean generated output.

## Release polish review

- Split `docs/index.html` into `docs/index.html`, `docs/styles.css`, and `docs/app.js`; no docs links, assets, or copy targets are missing.
- Refactored detection rule conversion into shared validators plus per-rule converters, and changed `DetectionRule` to `IDictionary[]`.
- Changed CI to run `./build.ps1 -Task CI` once per OS; individual `Analyze`, `Test`, and `Build` tasks no longer bootstrap dependencies.
- Deleted duplicate VS Code workspace/tasks, formatter wrapper, and workflow trigger mini-doc.
- Verified parser pass, PSScriptAnalyzer, 13 Pester tests, `./build.ps1 -Task CI`, default bootstrap, workflow YAML, built manifest, docs references, and cleanup of generated `build/`.

## README page alignment

- [x] Rewrite `README.md` to match the GitHub Pages tone and coverage.
- [x] Verify README links, PowerShell examples, and release command references.
- [x] Add IntuneHydrationKit-style status badges to `README.md`.

## Release push

- [x] Verify release tag matches `Win32Forge.psd1`.
- [x] Run release CI locally.
- [x] Commit release-ready changes.
- [x] Tag release.
- [x] Push `main` and release tag.

## GitHub Actions follow-up

- [x] Inspect failed CI, release, and Pages runs.
- [x] Fix dependency bootstrap for GitHub-hosted runners.
- [x] Bootstrap release job before manifest validation.
- [x] Enable GitHub Pages configuration from the Pages workflow.
- [x] Verify workflows and local CI.

## GitHub Actions follow-up review

- Fixed runner dependency install by using `Install-PSResource` when available and keeping `Install-Module` as the fallback.
- Fixed future tag releases by checking out the repository and bootstrapping dependencies before artifact manifest validation.
- Enabled GitHub Pages as a workflow-backed site and verified the docs deploy at `https://jorgeasaurus.github.io/Win32Forge/`.
- Verified main CI and Pages are green; the historical `v0.1.0` tag run remains failed because that tag points to the pre-fix commit.

## v0.1.1 release

- [x] Bump manifest version and release notes to `0.1.1`.
- [x] Verify manifest version, parser, and CI.
- [x] Commit, tag `v0.1.1`, and push `main` plus the tag.
- [x] Watch the release workflow.

## v0.1.1 release review

- Pushed `main` and annotated tag `v0.1.1`.
- Verified local CI, manifest version, and main CI.
- Added the `PSGALLERY_API_KEY` repository secret and reran the release workflow.
- Verified the release workflow published to PowerShell Gallery and created the GitHub Release.
- Verified `Find-Module -Name Win32Forge -RequiredVersion 0.1.1 -Repository PSGallery` returns `Win32Forge 0.1.1`.

## Social card update

- [x] Add the provided social card as a docs asset.
- [x] Wire the GitHub Pages site to use the card for Open Graph and Twitter previews.
- [x] Show the card on the website and README.
- [x] Set the GitHub repository homepage to the Pages site.
- [x] Verify docs references, image dimensions, and git status.

## Contoso README examples

- [x] Match README commands to `Examples/ContosoSampleApp`.
- [x] Fix file and PowerShell script detection examples.
- [x] Verify Markdown PowerShell snippets parse.
- [x] Record the docs accuracy lesson.

## Contoso README examples review

- Updated the README sample tree, explicit script/icon command, and detection examples to target `Examples/ContosoSampleApp`.
- Changed file and raw Graph detection to look for `C:\ProgramData\ContosoSampleApp\manifest.json`, which `install.ps1` creates.
- Verified README PowerShell snippets parse and Contoso detection examples run through `Publish-IntuneWin32App -WhatIf`.

## Permissions docs

- [x] Confirm the module's Graph scope and Intune app operations.
- [x] Add required permissions and roles to `README.md`.
- [x] Add required permissions and roles to the GitHub Pages docs.
- [x] Verify docs snippets and HTML structure.

## Permissions docs review

- Documented `DeviceManagementApps.ReadWrite.All` with admin consent for delegated and app-only auth.
- Documented the Intune RBAC side: `Application Manager`, `Intune Administrator`, or a custom `Mobile apps` role with create/read/update, plus delete for `-Force`.
- Verified README PowerShell snippets, Pages copy targets, docs references, `git diff --check`, and full local CI.
