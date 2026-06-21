#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Bootstrap', 'Analyze', 'Test', 'Build', 'CI', 'Clean')]
    [string]$Task = 'Bootstrap'
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

Set-StrictMode -Version Latest

$moduleName = 'Win32Forge'
$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "$moduleName.psd1"
$moduleManifest = Import-PowerShellDataFile -Path $moduleManifestPath
$rootModuleFileName = [System.IO.Path]::GetFileName($moduleManifest.RootModule)
$buildRoot = Join-Path -Path $PSScriptRoot -ChildPath 'build'
$buildDir = Join-Path -Path $buildRoot -ChildPath $moduleName
$testResultsDir = Join-Path -Path $buildRoot -ChildPath 'TestResults'
$testResultsPath = Join-Path -Path $testResultsDir -ChildPath 'TestResults.xml'
$sourceItems = @(
    "$moduleName.psd1"
    $rootModuleFileName
    'Public'
    'Private'
)

function Install-BuildDependency {
    [CmdletBinding()]
    param()

    $requiredModules = @(
        @{ Name = 'Pester'; MinimumVersion = '5.4.0' }
        @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' }
        @{ Name = 'Microsoft.Graph.Authentication'; MinimumVersion = '2.0.0' }
        @{ Name = 'SvRooij.ContentPrep.Cmdlet'; MinimumVersion = '0.4.0' }
    )

    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -Name $module.Name -ListAvailable |
            Where-Object { $_.Version -ge [version]$module.MinimumVersion } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($installedModule) {
            Write-Information "Found $($module.Name) v$($installedModule.Version)"
            continue
        }

        Write-Information "Installing $($module.Name) >= $($module.MinimumVersion)..."
        $installPSResource = Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue
        if ($installPSResource) {
            Install-PSResource -Name $module.Name -Version "[$($module.MinimumVersion), )" -Repository PSGallery -Scope CurrentUser -TrustRepository -AcceptLicense
        }
        else {
            Install-Module -Name $module.Name -MinimumVersion $module.MinimumVersion -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        }

        Write-Information "Installed $($module.Name)"
    }
}

function Invoke-Analyze {
    [CmdletBinding()]
    param()

    Import-Module PSScriptAnalyzer -Force

    $analysisTargets = @(
        $moduleManifestPath
        (Join-Path -Path $PSScriptRoot -ChildPath $rootModuleFileName)
        (Join-Path -Path $PSScriptRoot -ChildPath 'Public')
        (Join-Path -Path $PSScriptRoot -ChildPath 'Private')
        (Join-Path -Path $PSScriptRoot -ChildPath 'Tests')
        (Join-Path -Path $PSScriptRoot -ChildPath 'build.ps1')
    )

    $results = foreach ($analysisTarget in $analysisTargets) {
        Invoke-ScriptAnalyzer -Path $analysisTarget -Recurse -Settings (Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1')
    }

    if (@($results).Count -gt 0) {
        $formattedResults = $results |
            Select-Object -Property RuleName, Severity, ScriptName, Line, Message |
            Format-Table -AutoSize |
            Out-String

        Write-Information $formattedResults.TrimEnd()
        throw "PSScriptAnalyzer found $(@($results).Count) issue(s)."
    }

    Write-Information 'PSScriptAnalyzer found no issues.'
}

function Invoke-Test {
    [CmdletBinding()]
    param()

    Import-Module Pester -Force

    New-Item -Path $testResultsDir -ItemType Directory -Force | Out-Null

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Tests'
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.Run.PassThru = $true
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $testResultsPath
    $configuration.TestResult.OutputFormat = 'NUnitXml'

    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0) {
        throw "Pester reported $($result.FailedCount) failing test(s)."
    }

    Write-Information "Pester completed successfully. Results written to $testResultsPath."
}

function Invoke-BuildModule {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $buildDir) {
        Remove-Item -Path $buildDir -Recurse -Force
    }

    New-Item -Path $buildDir -ItemType Directory -Force | Out-Null

    foreach ($item in $sourceItems) {
        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $item
        $destinationPath = Join-Path -Path $buildDir -ChildPath $item

        if ((Get-Item -LiteralPath $sourcePath).PSIsContainer) {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
        }
        else {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Force
        }
    }

    $manifest = Test-ModuleManifest -Path (Join-Path -Path $buildDir -ChildPath "$moduleName.psd1")
    Write-Information "Staged $($manifest.Name) v$($manifest.Version) to $buildDir."
}

function Clear-BuildArtifact {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $buildRoot) {
        Remove-Item -Path $buildRoot -Recurse -Force
        Write-Information "Removed $buildRoot."
    }
    else {
        Write-Information 'Nothing to clean.'
    }
}

Write-Information "=== $moduleName Build Script ==="
Write-Information "Running task: $Task"

switch ($Task) {
    'Bootstrap' {
        Install-BuildDependency
        Write-Information 'Bootstrap complete.'
    }

    'Analyze' {
        Invoke-Analyze
    }
    'Test' {
        Invoke-Test
    }
    'Build' {
        Invoke-BuildModule
    }
    'CI' {
        Install-BuildDependency
        Invoke-Analyze
        Invoke-Test
        Invoke-BuildModule
    }
    'Clean' {
        Clear-BuildArtifact
    }
}
