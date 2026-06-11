#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$appRoot = Join-Path $env:ProgramData 'ContosoSampleApp'

if (Test-Path -LiteralPath $appRoot -PathType Container) {
    Remove-Item -LiteralPath $appRoot -Recurse -Force
}

exit 0
