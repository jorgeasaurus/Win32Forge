# Win32Forge

Intune Win32 apps, without the maze.

Win32Forge takes an app folder, packaging scripts, and an icon, then turns them into a ready-to-upload `.intunewin` package with the Intune metadata wired in. It handles the repeatable packaging and Microsoft Graph upload work between your source folder and Intune.

Package. Publish. Deploy.

<p align="center">
  <img src="docs/assets/win32forge-social-card.jpg" alt="Win32Forge packaging pipeline social card" width="960">
</p>

<p align="center">
  <a href="https://github.com/jorgeasaurus/Win32Forge/actions/workflows/ci.yml"><img src="https://github.com/jorgeasaurus/Win32Forge/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://www.powershellgallery.com/packages/Win32Forge"><img src="https://img.shields.io/powershellgallery/v/Win32Forge?label=PSGallery&color=blue" alt="PowerShell Gallery Version"></a>
  <a href="https://www.powershellgallery.com/packages/Win32Forge"><img src="https://img.shields.io/powershellgallery/dt/Win32Forge?label=Downloads&color=green" alt="PowerShell Gallery Downloads"></a>
  <img src="https://img.shields.io/badge/PowerShell-7.0%2B-blue?logo=powershell&logoColor=white" alt="PowerShell 7.0+">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20untested-lightgrey" alt="Platform: Windows, macOS, Linux untested">
</p>

<p align="center">
  <a href="https://github.com/jorgeasaurus/Win32Forge/stargazers"><img src="https://img.shields.io/github/stars/jorgeasaurus/Win32Forge?style=social" alt="GitHub Stars"></a>
  <a href="https://github.com/jorgeasaurus/Win32Forge/commits/main"><img src="https://img.shields.io/github/last-commit/jorgeasaurus/Win32Forge" alt="Last Commit"></a>
  <a href="https://github.com/jorgeasaurus/Win32Forge/releases/latest"><img src="https://img.shields.io/github/v/release/jorgeasaurus/Win32Forge?label=Latest%20Release" alt="Latest Release"></a>
</p>

Documentation site: <https://jorgeasaurus.github.io/Win32Forge/>

## What it handles

Win32Forge is the packaging pipeline for a Win32 app:

1. Prepare a source folder with the app payload, install script, uninstall script, detection rule, and icon.
2. Build the `.intunewin` package Intune expects.
3. Add the app name, publisher, version, install command, uninstall command, and detection rules.
4. Upload the package through Microsoft Graph so it appears in Intune as a Win32 app.

## Before publishing

You need PowerShell 7, two helper modules, an Intune tenant, and permission to create Intune Win32 apps. Win32Forge works on Windows and macOS; Linux should work but is not tested yet.

```powershell
Install-Module Win32Forge -Scope CurrentUser
Import-Module Win32Forge
```

```powershell
Install-Module Microsoft.Graph.Authentication, SvRooij.ContentPrep.Cmdlet -Scope CurrentUser
```

## Permissions and roles

Win32Forge creates, uploads, updates, and optionally replaces Intune Win32 apps through Microsoft Graph.

| Scenario | Required access |
|---|---|
| Tenant | Active Microsoft Intune license for the tenant |
| Interactive sign-in | Microsoft Graph delegated permission `DeviceManagementApps.ReadWrite.All` with admin consent |
| Intune admin role | Built-in `Application Manager`, `Intune Administrator`, or a custom Intune role with `Mobile apps` `Create`, `Read`, and `Update`; add `Delete` when using `-Force` |
| App-only authentication | Microsoft Graph application permission `DeviceManagementApps.ReadWrite.All` with admin consent |

For least privilege, use `Application Manager` or a custom Intune role for day-to-day publishing instead of a tenant-wide administrator role.

## Your app folder

Use one source folder with the files Win32Forge needs to package and publish the app. The examples below use the repo sample app.

```text
Examples/ContosoSampleApp/
|-- install.ps1      # creates C:\ProgramData\ContosoSampleApp
|-- uninstall.ps1    # removes the sample app folder
|-- detection.ps1    # checks manifest.json name and version
|-- icon.png         # Company Portal icon
`-- sample-app.txt   # packaged payload
```

File names are configurable with parameters. See [Examples/ContosoSampleApp](Examples/ContosoSampleApp) for a working sample.

## Publish an app

### Interactive sign-in

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0'
```

### Dry run

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -WhatIf
```

### Replace an existing app

Use `-Force` when replacing an existing app with the same display name.

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.1.0' `
    -Force
```

### Specific tenant

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -TenantId 'contoso.onmicrosoft.com'
```

### App-only authentication

`TenantId`, `ClientId`, and `ClientSecret` are required together.

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -TenantId '00000000-0000-0000-0000-000000000000' `
    -ClientId '11111111-1111-1111-1111-111111111111' `
    -ClientSecret $env:INTUNE_CLIENT_SECRET
```

### Explicit sample scripts, icon, and output folder

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -InstallScript 'install.ps1' `
    -UninstallScript 'uninstall.ps1' `
    -DetectionScript 'detection.ps1' `
    -IconFile 'icon.png' `
    -OutputDirectory ./build
```

### Keep Graph connected

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -KeepConnected
```

## Detection rules

Default behavior uses `detection.ps1`. The Contoso sample installer writes `C:\ProgramData\ContosoSampleApp\manifest.json`, and the detection examples below target that real output.

Use `-DetectionRule` when you need file system, registry, product code, PowerShell script options, or a raw Graph detection rule. Registry and product code rules are for apps that create those artifacts; the Contoso sample is file/script based.

### PowerShell script detection

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -DetectionRule @{
        Type = 'PowerShellScript'
        ScriptPath = 'detection.ps1'
        EnforceSignatureCheck = $false
        RunAs32Bit = $false
    }
```

### File system detection

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -DetectionRule @{
        Type = 'FileSystem'
        Path = 'C:\ProgramData\ContosoSampleApp'
        FileOrFolderName = 'manifest.json'
        DetectionType = 'exists'
        Check32BitOn64System = $false
    }
```

### Raw Graph file detection

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -DetectionRule @{
        '@odata.type' = '#microsoft.graph.win32LobAppFileSystemDetection'
        path = 'C:\ProgramData\ContosoSampleApp'
        fileOrFolderName = 'manifest.json'
        check32BitOn64System = $false
        detectionType = 'exists'
        operator = 'notConfigured'
        detectionValue = ''
    }
```

### Multiple detection rules

```powershell
Publish-IntuneWin32App `
    -SourceDirectory ./Examples/ContosoSampleApp `
    -Name 'Contoso Sample App' `
    -Publisher 'Contoso' `
    -Version '1.0.0' `
    -DetectionRule @(
        @{
            Type = 'FileSystem'
            Path = 'C:\ProgramData\ContosoSampleApp'
            FileOrFolderName = 'manifest.json'
            DetectionType = 'exists'
            Check32BitOn64System = $false
        }
        @{
            Type = 'PowerShellScript'
            ScriptPath = 'detection.ps1'
            EnforceSignatureCheck = $false
            RunAs32Bit = $false
        }
    )
```

## Output

Returns an object with `DisplayName`, `Id`, `Version`, `PackagePath`, and `TenantId`.

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `SourceDirectory` | Yes | - | Folder containing the app payload and scripts |
| `Name` | Yes | - | Intune display name |
| `Publisher` | Yes | - | Publisher name |
| `Developer` | No | `Publisher` value | Developer name shown in Intune |
| `Version` | Yes | - | App version string |
| `InstallScript` | No | `install.ps1` | Install script, relative to source directory |
| `UninstallScript` | No | `uninstall.ps1` | Uninstall script |
| `DetectionScript` | No | `detection.ps1` | Default detection script |
| `DetectionRule` | No | - | Structured detection rule object(s): `PowerShellScript`, `FileSystem`, `Registry`, `ProductCode`, or raw Graph rule |
| `IconFile` | No | `icon.png` | Company Portal icon |
| `OutputDirectory` | No | temp dir | Where the `.intunewin` package is written |
| `TenantId` | No | - | Entra tenant ID; required with `ClientId`/`ClientSecret` |
| `ClientId` | No | - | App registration ID for app-only auth |
| `ClientSecret` | No | - | Client secret for app-only auth |
| `Force` | No | - | Delete and replace an existing app with the same name |
| `KeepConnected` | No | - | Skip `Disconnect-MgGraph` on completion |

## Build and release

```powershell
./build.ps1 -Task CI
```

To publish, set the `PSGALLERY_API_KEY` repository secret, update `Win32Forge.psd1`, then push a matching tag such as `v0.1.1`.
