#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $env:ProgramData 'ContosoSampleApp\manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    exit 1
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    if ($manifest.Name -eq 'Contoso Sample App' -and $manifest.Version -eq '1.0.0') {
        Write-Output 'Contoso Sample App 1.0.0 detected.'
        exit 0
    }
}
catch {
    exit 1
}

exit 1
