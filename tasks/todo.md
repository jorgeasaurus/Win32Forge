- [x] Inspect current project and git remote names.
- [x] Audit legacy project-name references.
- [x] Rename project identity to `Win32Forge`.
- [x] Verify tests or syntax checks.
- [x] Rename GitHub repository/remote and local checkout.

## Review

- No tracked legacy project-name references remain.
- `Invoke-Pester -Path Tests -CI`: 9 passed, 0 failed.
- GitHub repo: `jorgeasaurus/Win32Forge`; `origin` updated to the new URL.
