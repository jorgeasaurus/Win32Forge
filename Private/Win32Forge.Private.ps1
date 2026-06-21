$script:Win32LobAppType = 'microsoft.graph.win32LobApp'
$script:DefaultGraphScopes = @('DeviceManagementApps.ReadWrite.All')
$script:DefaultChunkSizeInBytes = 6MB
$script:SasRenewalIntervalMilliseconds = 450000
$script:ComparisonDetectionOperators = @('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')
$script:FileSystemDetectionTypes = @('notConfigured', 'exists', 'modifiedDate', 'createdDate', 'version', 'sizeInMB', 'doesNotExist')
$script:RegistryDetectionTypes = @('notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'version')

function Test-PublisherRequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$CommandName
    )

    $module = Get-Module -ListAvailable -Name $Name | Select-Object -First 1
    if (-not $module) {
        throw "Required PowerShell module '$Name' is not installed. Install it with: Install-Module $Name -Scope CurrentUser"
    }

    Import-Module $Name -ErrorAction Stop

    if ($CommandName -and -not (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$CommandName' was not found after importing module '$Name'."
    }
}

function Resolve-IntuneWin32PublisherPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Container', 'Leaf')]
        [string]$PathType
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $providerPath = $resolved.ProviderPath

    if (-not (Test-Path -LiteralPath $providerPath -PathType $PathType)) {
        throw "Path '$Path' must be a $PathType path."
    }

    $providerPath
}

function Resolve-IntuneWin32PublisherFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Purpose
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($FileName)) {
        $FileName
    }
    else {
        Join-Path $SourceDirectory $FileName
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Purpose file '$FileName' was not found under '$SourceDirectory'."
    }

    (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
}

function Get-SourceRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    [System.IO.Path]::GetRelativePath($SourceDirectory, $FilePath).Replace('\', '/')
}

function Compress-IntuneWin32PackageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory
    )

    Test-PublisherRequiredModule -Name 'SvRooij.ContentPrep.Cmdlet' -CommandName 'New-IntuneWinPackage'

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    # Package into a fresh per-invocation directory so the output file is unambiguous,
    # then move it to the caller-facing output directory.
    $packageDirectory = Join-Path $OutputDirectory ('pkg-' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $packageDirectory -ItemType Directory -Force | Out-Null

    try {
        New-IntuneWinPackage -SourcePath $SourceDirectory -SetupFile $SetupFile -DestinationPath $packageDirectory | Out-Null

        $package = Get-ChildItem -LiteralPath $packageDirectory -Filter '*.intunewin' -File | Select-Object -First 1
        if (-not $package) {
            throw "New-IntuneWinPackage completed, but no .intunewin file was found in '$packageDirectory'."
        }

        $destinationPath = Join-Path $OutputDirectory $package.Name
        Move-Item -LiteralPath $package.FullName -Destination $destinationPath -Force
        (Resolve-Path -LiteralPath $destinationPath).ProviderPath
    }
    finally {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-IntuneWin32PackageManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.Entries | Where-Object { $_.Name -eq 'detection.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw "Package '$PackagePath' does not contain detection.xml."
        }

        $stream = $entry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream)
            try {
                [xml]$xml = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }

    if (-not $xml.ApplicationInfo) {
        throw "Package '$PackagePath' has an invalid detection.xml file."
    }

    $xml
}

function Expand-IntuneWin32EncryptedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
        New-Item -Path $DestinationDirectory -ItemType Directory -Force | Out-Null
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.Entries | Where-Object { $_.Name -eq $FileName } | Select-Object -First 1
        if (-not $entry) {
            throw "Package '$PackagePath' does not contain encrypted content file '$FileName'."
        }

        $destinationPath = Join-Path $DestinationDirectory $FileName
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationPath, $true)
        $destinationPath
    }
    finally {
        $archive.Dispose()
    }
}

function ConvertTo-PowerShellScriptDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [bool]$EnforceSignatureCheck = $false,

        [bool]$RunAs32Bit = $false
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Detection script '$ScriptPath' was not found."
    }

    @{
        '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
        enforceSignatureCheck = $EnforceSignatureCheck
        runAs32Bit            = $RunAs32Bit
        scriptContent         = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($ScriptPath))
    }
}

function Get-DetectionRuleValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [object]$Default
    )

    if ($Rule.Contains($Name)) {
        return $Rule[$Name]
    }

    if ($PSBoundParameters.ContainsKey('Default')) {
        return $Default
    }

    throw "$RuleType detection rule is missing required property '$Name'."
}

function Get-DetectionRuleStringValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [object]$Default
    )

    $parameters = @{
        Rule     = $Rule
        RuleType = $RuleType
        Name     = $Name
    }

    if ($PSBoundParameters.ContainsKey('Default')) {
        $parameters.Default = $Default
    }

    [string](Get-DetectionRuleValue @parameters)
}

function Get-DetectionRuleBooleanValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [bool]$Default = $false
    )

    $value = Get-DetectionRuleValue -Rule $Rule -RuleType $RuleType -Name $Name -Default $Default
    if ($value -isnot [bool]) {
        throw "$RuleType detection rule $Name must be `$true or `$false."
    }

    $value
}

function Get-DetectionRuleEnumValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AllowedValue,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [object]$Default
    )

    $parameters = @{
        Rule     = $Rule
        RuleType = $RuleType
        Name     = $Name
    }

    if ($PSBoundParameters.ContainsKey('Default')) {
        $parameters.Default = $Default
    }

    $value = Get-DetectionRuleStringValue @parameters
    if ($value -cnotin $AllowedValue) {
        throw "Unsupported $Description '$value'."
    }

    $value
}

function ConvertTo-Win32LobAppPowerShellScriptDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultDetectionScript
    )

    $scriptFileName = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'PowerShellScript' -Name 'ScriptPath' -Default $DefaultDetectionScript
    $scriptPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $SourceDirectory -FileName $scriptFileName -Purpose 'Detection script'

    ConvertTo-PowerShellScriptDetectionRule `
        -ScriptPath $scriptPath `
        -EnforceSignatureCheck (Get-DetectionRuleBooleanValue -Rule $Rule -RuleType 'PowerShellScript' -Name 'EnforceSignatureCheck') `
        -RunAs32Bit (Get-DetectionRuleBooleanValue -Rule $Rule -RuleType 'PowerShellScript' -Name 'RunAs32Bit')
}

function ConvertTo-Win32LobAppFileSystemDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    @{
        '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemDetection'
        path                 = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'FileSystem' -Name 'Path'
        fileOrFolderName     = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'FileSystem' -Name 'FileOrFolderName'
        check32BitOn64System = Get-DetectionRuleBooleanValue -Rule $Rule -RuleType 'FileSystem' -Name 'Check32BitOn64System'
        detectionType        = Get-DetectionRuleEnumValue -Rule $Rule -RuleType 'FileSystem' -Name 'DetectionType' -AllowedValue $script:FileSystemDetectionTypes -Description 'file system detection type'
        operator             = Get-DetectionRuleEnumValue -Rule $Rule -RuleType 'FileSystem' -Name 'Operator' -AllowedValue $script:ComparisonDetectionOperators -Description 'file system detection operator' -Default 'notConfigured'
        detectionValue       = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'FileSystem' -Name 'DetectionValue' -Default ''
    }
}

function ConvertTo-Win32LobAppRegistryDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    @{
        '@odata.type'        = '#microsoft.graph.win32LobAppRegistryDetection'
        check32BitOn64System = Get-DetectionRuleBooleanValue -Rule $Rule -RuleType 'Registry' -Name 'Check32BitOn64System'
        keyPath              = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'Registry' -Name 'KeyPath'
        valueName            = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'Registry' -Name 'ValueName' -Default ''
        detectionType        = Get-DetectionRuleEnumValue -Rule $Rule -RuleType 'Registry' -Name 'DetectionType' -AllowedValue $script:RegistryDetectionTypes -Description 'registry detection type'
        operator             = Get-DetectionRuleEnumValue -Rule $Rule -RuleType 'Registry' -Name 'Operator' -AllowedValue $script:ComparisonDetectionOperators -Description 'registry detection operator' -Default 'notConfigured'
        detectionValue       = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'Registry' -Name 'DetectionValue' -Default ''
    }
}

function ConvertTo-Win32LobAppProductCodeDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    @{
        '@odata.type'          = '#microsoft.graph.win32LobAppProductCodeDetection'
        productCode            = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'ProductCode' -Name 'ProductCode'
        productVersionOperator = Get-DetectionRuleEnumValue -Rule $Rule -RuleType 'ProductCode' -Name 'ProductVersionOperator' -AllowedValue $script:ComparisonDetectionOperators -Description 'product version operator' -Default 'notConfigured'
        productVersion         = Get-DetectionRuleStringValue -Rule $Rule -RuleType 'ProductCode' -Name 'ProductVersion' -Default ''
    }
}

function ConvertTo-Win32LobAppDetectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultDetectionScript
    )

    if ($Rule.Contains('@odata.type')) {
        return , $Rule
    }

    if (-not $Rule.Contains('Type')) {
        throw "Detection rule is missing required property 'Type'."
    }

    $ruleType = [string]$Rule['Type']

    switch ($ruleType) {
        'PowerShellScript' {
            ConvertTo-Win32LobAppPowerShellScriptDetectionRule -Rule $Rule -SourceDirectory $SourceDirectory -DefaultDetectionScript $DefaultDetectionScript
            break
        }

        'FileSystem' {
            ConvertTo-Win32LobAppFileSystemDetectionRule -Rule $Rule
            break
        }

        'Registry' {
            ConvertTo-Win32LobAppRegistryDetectionRule -Rule $Rule
            break
        }

        'ProductCode' {
            ConvertTo-Win32LobAppProductCodeDetectionRule -Rule $Rule
            break
        }

        default {
            throw "Unsupported detection rule type '$ruleType'. Use PowerShellScript, FileSystem, Registry, ProductCode, or a raw Graph rule with @odata.type."
        }
    }
}

function ConvertTo-Win32LobAppDetectionRuleSet {
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary[]]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultDetectionScript
    )

    if ($null -eq $Rule -or @($Rule).Count -eq 0) {
        $scriptPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $SourceDirectory -FileName $DefaultDetectionScript -Purpose 'Detection script'
        [object[]]$defaultRule = @(ConvertTo-PowerShellScriptDetectionRule -ScriptPath $scriptPath)
        return , $defaultRule
    }

    [object[]]$convertedRules = @($Rule | ForEach-Object {
            ConvertTo-Win32LobAppDetectionRule -Rule $_ -SourceDirectory $SourceDirectory -DefaultDetectionScript $DefaultDetectionScript
        })
    return , $convertedRules
}

function ConvertTo-IntuneMimeContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Icon file '$Path' was not found."
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $mimeType = switch ($extension) {
        '.png' { 'image/png'; break }
        '.jpg' { 'image/jpeg'; break }
        '.jpeg' { 'image/jpeg'; break }
        default { throw "Unsupported icon file type '$extension'. Use PNG or JPG." }
    }

    @{
        '@odata.type' = '#microsoft.graph.mimeContent'
        type          = $mimeType
        value         = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
}

function ConvertTo-Win32LobAppBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$DisplayName,
        [Parameter(Mandatory = $true)] [string]$Publisher,
        [string]$Developer = '',
        [Parameter(Mandatory = $true)] [string]$Version,
        [Parameter(Mandatory = $true)] [string]$Description,
        [Parameter(Mandatory = $true)] [string]$FileName,
        [Parameter(Mandatory = $true)] [string]$SetupFilePath,
        [Parameter(Mandatory = $true)] [string]$InstallCommandLine,
        [Parameter(Mandatory = $true)] [string]$UninstallCommandLine,
        [Parameter(Mandatory = $true)] [object[]]$DetectionRules,
        [Parameter(Mandatory = $true)] [object[]]$ReturnCodes,
        [hashtable]$LargeIcon
    )

    $body = [ordered]@{
        '@odata.type'                   = '#microsoft.graph.win32LobApp'
        displayName                     = $DisplayName
        description                     = $Description
        publisher                       = $Publisher
        displayVersion                  = $Version
        developer                       = $Developer
        owner                           = ''
        notes                           = ''
        informationUrl                  = $null
        privacyInformationUrl           = $null
        isFeatured                      = $false
        fileName                        = $FileName
        setupFilePath                   = $SetupFilePath
        installCommandLine              = $InstallCommandLine
        uninstallCommandLine            = $UninstallCommandLine
        installExperience               = @{ runAsAccount = 'system' }
        minimumSupportedOperatingSystem = @{ v10_1607 = $true }
        msiInformation                  = $null
        runAs32bit                      = $false
        detectionRules                  = @($DetectionRules)
        returnCodes                     = @($ReturnCodes)
    }

    if ($LargeIcon) {
        $body.largeIcon = $LargeIcon
    }

    $body
}

function Invoke-IntuneGraphJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [object]$Body
    )

    $params = @{
        Method      = $Method
        Uri         = $Uri
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = $Body | ConvertTo-Json -Depth 20
        $params.ContentType = 'application/json'
    }

    Invoke-MgGraphRequest @params
}

function Get-IntuneWin32AppByDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    $escapedName = $DisplayName.Replace("'", "''")
    $filter = [uri]::EscapeDataString("displayName eq '$escapedName'")
    $response = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceAppManagement/mobileApps?`$filter=$filter" -ErrorAction Stop
    @($response.value) | Where-Object { $_.displayName -eq $DisplayName -and $_.'@odata.type' -eq '#microsoft.graph.win32LobApp' }
}

function Remove-IntuneWin32App {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    if ($PSCmdlet.ShouldProcess($DisplayName, 'Remove existing Intune Win32 app')) {
        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceAppManagement/mobileApps/$AppId" -ErrorAction Stop | Out-Null
    }
}

function Wait-IntuneWin32FileProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileUri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Stage,

        [ValidateRange(1, 3600)]
        [int]$MaxAttempts = 600,

        [ValidateRange(1, 300)]
        [int]$DelaySeconds = 5
    )

    $successState = "$($Stage)Success"
    $pendingState = "$($Stage)Pending"

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $FileUri -ErrorAction Stop
        if ($file.uploadState -eq $successState) {
            return $file
        }

        if ($file.uploadState -ne $pendingState) {
            throw "File processing failed at stage '$Stage' with state '$($file.uploadState)'."
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "File processing stage '$Stage' did not complete after $MaxAttempts attempts."
}

function Send-AzureStorageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$SasUri,
        [Parameter(Mandatory = $true)] [string]$FilePath,
        [Parameter(Mandatory = $true)] [string]$FileUri,
        [int64]$ChunkSizeInBytes = $script:DefaultChunkSizeInBytes
    )

    $stream = [System.IO.File]::OpenRead($FilePath)
    $blockIds = [System.Collections.Generic.List[string]]::new()
    $buffer = [byte[]]::new($ChunkSizeInBytes)
    $renewalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $index = 0
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($index.ToString('000000')))
            $blockIds.Add($blockId)

            if ($bytesRead -eq $buffer.Length) {
                $chunk = $buffer
            }
            else {
                $chunk = [byte[]]::new($bytesRead)
                [Array]::Copy($buffer, $chunk, $bytesRead)
            }

            $blockUri = "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))"
            $blockHeaders = @{
                'x-ms-blob-type' = 'BlockBlob'
                'Content-Type'   = 'application/octet-stream'
            }

            Invoke-WebRequest -Uri $blockUri -Method Put -Headers $blockHeaders -Body $chunk -UseBasicParsing -ErrorAction Stop | Out-Null

            if ($stream.Position -lt $stream.Length -and $renewalTimer.ElapsedMilliseconds -ge $script:SasRenewalIntervalMilliseconds) {
                Invoke-MgGraphRequest -Method POST -Uri "$FileUri/renewUpload" -Body '' -ErrorAction Stop | Out-Null
                $renewedFile = Wait-IntuneWin32FileProcessing -FileUri $FileUri -Stage 'AzureStorageUriRenewal'
                $SasUri = $renewedFile.azureStorageUri
                $renewalTimer.Restart()
            }

            $index++
        }
    }
    finally {
        $stream.Dispose()
    }

    $blockList = ($blockIds.ToArray() | ForEach-Object { "<Latest>$_</Latest>" }) -join ''
    $blockListBody = "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList>$blockList</BlockList>"
    Invoke-RestMethod -Uri "$SasUri&comp=blocklist" -Method Put -Body $blockListBody -ContentType 'application/xml' -ErrorAction Stop | Out-Null
}

function Invoke-IntuneWin32LobUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PackagePath,
        [Parameter(Mandatory = $true)] [string]$DisplayName,
        [Parameter(Mandatory = $true)] [string]$Publisher,
        [string]$Developer = '',
        [Parameter(Mandatory = $true)] [string]$Version,
        [Parameter(Mandatory = $true)] [string]$Description,
        [Parameter(Mandatory = $true)] [string]$InstallCommandLine,
        [Parameter(Mandatory = $true)] [string]$UninstallCommandLine,
        [Parameter(Mandatory = $true)] [object[]]$DetectionRules,
        [Parameter(Mandatory = $true)] [string]$IconPath,
        [Parameter(Mandatory = $true)] [string]$StagingDirectory
    )

    $metadata = Get-IntuneWin32PackageManifest -PackagePath $PackagePath
    $appInfo = $metadata.ApplicationInfo
    $encryptionInfo = $appInfo.EncryptionInfo

    $icon = ConvertTo-IntuneMimeContent -Path $IconPath
    $appBody = ConvertTo-Win32LobAppBody `
        -DisplayName $DisplayName `
        -Publisher $Publisher `
        -Developer $Developer `
        -Version $Version `
        -Description $Description `
        -FileName $appInfo.FileName `
        -SetupFilePath $appInfo.SetupFile `
        -InstallCommandLine $InstallCommandLine `
        -UninstallCommandLine $UninstallCommandLine `
        -DetectionRules @($DetectionRules) `
        -ReturnCodes @(
        @{ returnCode = 0; type = 'success' }
        @{ returnCode = 1707; type = 'success' }
        @{ returnCode = 3010; type = 'softReboot' }
        @{ returnCode = 1641; type = 'hardReboot' }
        @{ returnCode = 1618; type = 'retry' }
    ) `
        -LargeIcon $icon

    $mobileApp = Invoke-IntuneGraphJsonRequest -Method POST -Uri 'beta/deviceAppManagement/mobileApps/' -Body $appBody
    if (-not $mobileApp.id) {
        throw 'Graph did not return a mobile app id.'
    }

    $appId = $mobileApp.id
    $contentVersionUri = "beta/deviceAppManagement/mobileApps/$appId/$script:Win32LobAppType/contentVersions"
    $contentVersion = Invoke-IntuneGraphJsonRequest -Method POST -Uri $contentVersionUri -Body @{}
    if (-not $contentVersion.id) {
        throw 'Graph did not return a content version id.'
    }

    $contentFilePath = Expand-IntuneWin32EncryptedFile -PackagePath $PackagePath -FileName $appInfo.FileName -DestinationDirectory $StagingDirectory
    try {
        $encryptedSize = (Get-Item -LiteralPath $contentFilePath).Length
        $fileBody = @{
            '@odata.type' = '#microsoft.graph.mobileAppContentFile'
            name          = $appInfo.FileName
            size          = [int64]$appInfo.UnencryptedContentSize
            sizeEncrypted = [int64]$encryptedSize
            manifest      = $null
            isDependency  = $false
        }

        $contentVersionId = $contentVersion.id
        $fileCreateUri = "beta/deviceAppManagement/mobileApps/$appId/$script:Win32LobAppType/contentVersions/$contentVersionId/files"
        $file = Invoke-IntuneGraphJsonRequest -Method POST -Uri $fileCreateUri -Body $fileBody
        if (-not $file.id) {
            throw 'Graph did not return a content file id.'
        }

        $fileId = $file.id
        $fileUri = "beta/deviceAppManagement/mobileApps/$appId/$script:Win32LobAppType/contentVersions/$contentVersionId/files/$fileId"
        $file = Wait-IntuneWin32FileProcessing -FileUri $fileUri -Stage 'AzureStorageUriRequest'
        Send-AzureStorageFile -SasUri $file.azureStorageUri -FilePath $contentFilePath -FileUri $fileUri

        $fileEncryptionInfo = @{
            fileEncryptionInfo = @{
                encryptionKey        = $encryptionInfo.EncryptionKey
                macKey               = $encryptionInfo.macKey
                initializationVector = $encryptionInfo.initializationVector
                mac                  = $encryptionInfo.mac
                profileIdentifier    = 'ProfileVersion1'
                fileDigest           = $encryptionInfo.fileDigest
                fileDigestAlgorithm  = $encryptionInfo.fileDigestAlgorithm
            }
        }

        $commitFileUri = "$fileUri/commit"
        Invoke-IntuneGraphJsonRequest -Method POST -Uri $commitFileUri -Body $fileEncryptionInfo | Out-Null
        Wait-IntuneWin32FileProcessing -FileUri $fileUri -Stage 'CommitFile' | Out-Null

        $commitAppBody = @{
            '@odata.type'           = "#$script:Win32LobAppType"
            committedContentVersion = $contentVersionId
        }
        Invoke-IntuneGraphJsonRequest -Method PATCH -Uri "beta/deviceAppManagement/mobileApps/$appId" -Body $commitAppBody | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $contentFilePath -PathType Leaf) {
            Remove-Item -LiteralPath $contentFilePath -Force
        }
    }

    $mobileApp
}

function Connect-IntuneGraph {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Microsoft Graph client-secret authentication requires converting the supplied secret to SecureString.')]
    [CmdletBinding()]
    param(
        [string]$TenantId,

        [string]$ClientId,

        [string]$ClientSecret
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $connectParams = @{
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }

    if ($ClientId -or $ClientSecret) {
        if (-not ($TenantId -and $ClientId -and $ClientSecret)) {
            throw 'TenantId, ClientId, and ClientSecret are all required for app-only authentication.'
        }

        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $connectParams.TenantId = $TenantId
        $connectParams.ClientSecretCredential = [pscredential]::new($ClientId, $secureSecret)
    }
    else {
        $connectParams.Scopes = $script:DefaultGraphScopes
        if ($TenantId) {
            $connectParams.TenantId = $TenantId
        }
    }

    Connect-MgGraph @connectParams | Out-Null
    $context = Get-MgContext
    if (-not $context) {
        throw 'Microsoft Graph connection did not return a context.'
    }

    $context
}
