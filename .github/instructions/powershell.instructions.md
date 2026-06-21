---
applyTo: '**/*.ps1,**/*.psm1'
description: 'PowerShell coding guidance for Win32Forge'
---

# PowerShell Guidelines

- Use approved `Verb-Noun` command names and PascalCase parameters.
- Return objects instead of formatted text.
- Use `SupportsShouldProcess` for commands that create, update, or delete external resources.
- Mock Microsoft Graph and packaging calls in tests.
- Keep runtime behavior in `Public/` or `Private/`; keep `Win32Forge.psm1` as the loader.
