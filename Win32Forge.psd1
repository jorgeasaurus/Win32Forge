@{
    RootModule        = 'Win32Forge.psm1'
    ModuleVersion     = '0.1.0'
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
## v0.1.0

- Initial PowerShell Gallery packaging for Win32Forge.
- Exports Publish-IntuneWin32App for packaging and publishing Intune Win32 apps.
'@
        }
    }
}
