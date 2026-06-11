#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
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

    [string]$Developer,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,

    [ValidateNotNullOrEmpty()]
    [string]$InstallScript = 'install.ps1',

    [ValidateNotNullOrEmpty()]
    [string]$UninstallScript = 'uninstall.ps1',

    [ValidateNotNullOrEmpty()]
    [string]$DetectionScript = 'detection.ps1',

    [ValidateNotNullOrEmpty()]
    [string]$IconFile = 'icon.png',

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneWin32AppPublisher'),

    [string]$TenantId,

    [string]$ClientId,

    [string]$ClientSecret,

    [switch]$Force,

    [switch]$KeepConnected
)

$modulePath = Join-Path $PSScriptRoot 'IntuneWin32AppPublisher.psm1'
Import-Module $modulePath -Force -ErrorAction Stop

Publish-IntuneWin32App @PSBoundParameters
