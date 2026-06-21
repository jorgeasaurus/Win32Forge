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
