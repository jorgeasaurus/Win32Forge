# Win32Forge

Packages a source folder as an `.intunewin` file and publishes it to Intune as a Win32 app via Microsoft Graph.

## Requirements

- PowerShell 7.0+
- Modules: `Microsoft.Graph.Authentication`, `SvRooij.ContentPrep.Cmdlet`
- Graph permission: `DeviceManagementApps.ReadWrite.All`

```powershell
Install-Module Microsoft.Graph.Authentication, SvRooij.ContentPrep.Cmdlet -Scope CurrentUser
```

## Source folder layout

The source directory must contain (names configurable via parameters):

```
MyApp/
├── install.ps1      # install script (becomes the setup file)
├── uninstall.ps1    # uninstall script
├── detection.ps1    # detection script
├── icon.png         # Company Portal icon
└── ...              # any other payload files
```

See [Examples/ContosoSampleApp](Examples/ContosoSampleApp) for a working sample.

## Examples

### Interactive sign-in (delegated auth)

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0'
```

### Interactive sign-in against a specific tenant

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -TenantId 'contoso.onmicrosoft.com'
```

### App-only authentication (client secret)

`TenantId`, `ClientId`, and `ClientSecret` are all required together.

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -TenantId '00000000-0000-0000-0000-000000000000' `
    -ClientId '11111111-1111-1111-1111-111111111111' `
    -ClientSecret $env:INTUNE_CLIENT_SECRET
```

### Replace an existing app with the same name

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.1.0' `
    -Force
```

### Custom script/icon names and output directory

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./MyApp `
    -Name 'My App' `
    -Publisher 'Contoso' `
    -Version '2.0.0' `
    -InstallScript 'deploy/install-myapp.ps1' `
    -UninstallScript 'deploy/uninstall-myapp.ps1' `
    -DetectionScript 'deploy/detect-myapp.ps1' `
    -IconFile 'assets/myapp.png' `
    -OutputDirectory ./build
```

### Dry run

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -WhatIf
```

### Keep the Graph session open after publishing

```powershell
./Publish-IntuneWin32App.ps1 `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -KeepConnected
```

## Output

Returns an object with `DisplayName`, `Id`, `Version`, `PackagePath`, and `TenantId`.

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `SourceDirectory` | Yes | — | Folder containing the app payload and scripts |
| `Name` | Yes | — | Intune display name |
| `Publisher` | Yes | — | Publisher name |
| `Developer` | No | `Publisher` value | Developer name shown in Intune |
| `Version` | Yes | — | App version string |
| `InstallScript` | No | `install.ps1` | Install script, relative to source directory |
| `UninstallScript` | No | `uninstall.ps1` | Uninstall script |
| `DetectionScript` | No | `detection.ps1` | Detection script |
| `IconFile` | No | `icon.png` | Company Portal icon |
| `OutputDirectory` | No | temp dir | Where the `.intunewin` package is written |
| `TenantId` | No | — | Entra tenant ID; required with `ClientId`/`ClientSecret` |
| `ClientId` | No | — | App registration ID for app-only auth |
| `ClientSecret` | No | — | Client secret for app-only auth |
| `Force` | No | — | Delete and replace an existing app with the same name |
| `KeepConnected` | No | — | Skip `Disconnect-MgGraph` on completion |
