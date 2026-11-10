@{
    RootModule        = 'Win32Forge.psm1'
    ModuleVersion     = '0.1.2'
    GUID              = '265fb73f-40b9-43f2-8668-fb45c2684656'
    Author            = 'Jorgeasaurus'
    CompanyName       = 'Jorgeasaurus'
    Copyright         = '(c) 2026 Jorgeasaurus. All rights reserved.'
    Description       = 'Packages and publishes Intune Win32 apps through Microsoft Graph.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        @{
            ModuleName    = 'Microsoft.Graph.Authentication'
            ModuleVersion = '2.0.0'
        }
        @{
            ModuleName    = 'SvRooij.ContentPrep.Cmdlet'
            ModuleVersion = '0.4.0'
        }
    )

    FunctionsToExport = @(
        'Publish-IntuneWin32App'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('Intune', 'Win32', 'MicrosoftGraph', 'EndpointManager', 'PSEdition_Core')
            ProjectUri   = 'https://github.com/jorgeasaurus/Win32Forge'
            ReleaseNotes = @'
## v0.1.2

- Simplify detection-rule conversion and internal helpers; behavior is unchanged, but some validation messages are worded differently.
- Rely on the manifest's RequiredModules instead of runtime module checks.
- Redesign the documentation site with tabbed examples and a parameter reference.
- Document that PowerShell script detection cannot be combined with other detection rules.

## v0.1.1

- Fix GitHub-hosted dependency bootstrap for release publishing.
- Bootstrap release dependencies before manifest validation.

## v0.1.0

- Initial PowerShell Gallery packaging for Win32Forge.
- Exports Publish-IntuneWin32App for packaging and publishing Intune Win32 apps.
'@
        }
    }
}
