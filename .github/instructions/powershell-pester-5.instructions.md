---
applyTo: '**/*.Tests.ps1'
description: 'Pester 5 guidance for Win32Forge'
---

# Pester Guidelines

- Import `Win32Forge.psd1` in `BeforeAll`.
- Use `InModuleScope Win32Forge` for private helper coverage.
- Mock Microsoft Graph, Azure Storage, and content packaging calls.
- Verify exported commands through the module manifest.
- Keep tests deterministic and filesystem work under `$TestDrive`.
