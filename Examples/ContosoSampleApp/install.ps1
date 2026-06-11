#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$appRoot = Join-Path $env:ProgramData 'ContosoSampleApp'
$payloadSource = Join-Path $PSScriptRoot 'sample-app.txt'
$payloadDestination = Join-Path $appRoot 'sample-app.txt'
$manifestPath = Join-Path $appRoot 'manifest.json'
$logPath = Join-Path $appRoot 'install.log'

New-Item -Path $appRoot -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath $payloadSource -Destination $payloadDestination -Force

$manifest = [ordered]@{
    Name        = 'Contoso Sample App'
    Version     = '1.0.0'
    InstalledOn = (Get-Date).ToString('o')
}

$manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8
"Installed Contoso Sample App 1.0.0" | Add-Content -LiteralPath $logPath -Encoding UTF8

exit 0
