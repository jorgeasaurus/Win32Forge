function Publish-IntuneWin32App {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Publisher,

        [string]$Developer = $Publisher,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [ValidateNotNullOrEmpty()]
        [string]$InstallScript = 'install.ps1',

        [ValidateNotNullOrEmpty()]
        [string]$UninstallScript = 'uninstall.ps1',

        [ValidateNotNullOrEmpty()]
        [string]$DetectionScript = 'detection.ps1',

        [System.Collections.IDictionary[]]$DetectionRule,

        [ValidateNotNullOrEmpty()]
        [string]$IconFile = 'icon.png',

        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'Win32Forge'),

        [string]$TenantId,

        [string]$ClientId,

        [string]$ClientSecret,

        [switch]$Force,

        [switch]$KeepConnected
    )

    $sourcePath = Resolve-IntuneWin32PublisherPath -Path $SourceDirectory -PathType Container
    $installScriptPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $sourcePath -FileName $InstallScript -Purpose 'Install script'
    $uninstallScriptPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $sourcePath -FileName $UninstallScript -Purpose 'Uninstall script'
    $iconPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $sourcePath -FileName $IconFile -Purpose 'Company Portal icon'
    $detectionRules = ConvertTo-Win32LobAppDetectionRuleSet -Rule $DetectionRule -SourceDirectory $sourcePath -DefaultDetectionScript $DetectionScript

    $relativeInstallScript = Get-SourceRelativePath -SourceDirectory $sourcePath -FilePath $installScriptPath
    $relativeUninstallScript = Get-SourceRelativePath -SourceDirectory $sourcePath -FilePath $uninstallScriptPath
    $installCommandLine = "powershell.exe -ExecutionPolicy Bypass -File `"$($relativeInstallScript.Replace('"', '\"'))`""
    $uninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass -File `"$($relativeUninstallScript.Replace('"', '\"'))`""

    $description = "$Name $Version"
    $stagingDirectory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))

    try {
        if ($PSCmdlet.ShouldProcess($Name, 'Package source files and create Intune Win32 app')) {
            Test-PublisherRequiredModule -Name 'Microsoft.Graph.Authentication'

            $packagePath = Compress-IntuneWin32PackageFile -SourceDirectory $sourcePath -SetupFile $relativeInstallScript -OutputDirectory $OutputDirectory
            $context = Connect-IntuneGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

            $existingApps = @(Get-IntuneWin32AppByDisplayName -DisplayName $Name)
            if ($existingApps.Count -gt 0 -and -not $Force) {
                throw "A Win32 app named '$Name' already exists. Re-run with -Force to replace it."
            }

            foreach ($existingApp in $existingApps) {
                Remove-IntuneWin32App -AppId $existingApp.id -DisplayName $existingApp.displayName -Confirm:$false
            }

            $app = Invoke-IntuneWin32LobUpload `
                -PackagePath $packagePath `
                -DisplayName $Name `
                -Publisher $Publisher `
                -Developer $Developer `
                -Version $Version `
                -Description $description `
                -InstallCommandLine $installCommandLine `
                -UninstallCommandLine $uninstallCommandLine `
                -DetectionRules $detectionRules `
                -IconPath $iconPath `
                -StagingDirectory $stagingDirectory

            [pscustomobject]@{
                DisplayName = $app.displayName
                Id          = $app.id
                Version     = $Version
                PackagePath = $packagePath
                TenantId    = $context.TenantId
            }
        }
    }
    finally {
        if (-not $KeepConnected -and (Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue)) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        if (Test-Path -LiteralPath $stagingDirectory -PathType Container) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }
}
