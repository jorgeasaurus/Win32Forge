$script:Win32LobAppType = 'microsoft.graph.win32LobApp'
$script:ChunkSizeInBytes = 6MB
$script:SasRenewalIntervalMilliseconds = 450000
$script:ComparisonDetectionOperators = @('notConfigured', 'equal', 'notEqual', 'greaterThan', 'greaterThanOrEqual', 'lessThan', 'lessThanOrEqual')
$script:FileSystemDetectionTypes = @('notConfigured', 'exists', 'modifiedDate', 'createdDate', 'version', 'sizeInMB', 'doesNotExist')
$script:RegistryDetectionTypes = @('notConfigured', 'exists', 'doesNotExist', 'string', 'integer', 'version')

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

    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.Entries | Where-Object { $_.Name -eq 'detection.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw "Package '$PackagePath' does not contain detection.xml."
        }

        # Disposing the reader also disposes the entry stream.
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try {
            [xml]$xml = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
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

    New-Item -Path $DestinationDirectory -ItemType Directory -Force | Out-Null

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

function Get-DetectionRuleValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [object]$Default,

        [string[]]$AllowedValue,

        [switch]$Boolean
    )

    $ruleType = $Rule['Type']
    $value = if ($Rule.Contains($Name)) {
        $Rule[$Name]
    }
    elseif ($PSBoundParameters.ContainsKey('Default')) {
        $Default
    }
    elseif ($Boolean) {
        $false
    }
    else {
        throw "$ruleType detection rule is missing required property '$Name'."
    }

    if ($Boolean) {
        if ($value -isnot [bool]) {
            throw "$ruleType detection rule $Name must be `$true or `$false."
        }

        return $value
    }

    $value = [string]$value
    if ($AllowedValue -and $value -cnotin $AllowedValue) {
        throw "Unsupported $ruleType detection rule $Name '$value'."
    }

    $value
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

    $operators = $script:ComparisonDetectionOperators

    switch ([string]$Rule['Type']) {
        'PowerShellScript' {
            $scriptFileName = Get-DetectionRuleValue -Rule $Rule -Name 'ScriptPath' -Default $DefaultDetectionScript
            $scriptPath = Resolve-IntuneWin32PublisherFile -SourceDirectory $SourceDirectory -FileName $scriptFileName -Purpose 'Detection script'
            @{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                enforceSignatureCheck = Get-DetectionRuleValue -Rule $Rule -Name 'EnforceSignatureCheck' -Boolean
                runAs32Bit            = Get-DetectionRuleValue -Rule $Rule -Name 'RunAs32Bit' -Boolean
                scriptContent         = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($scriptPath))
            }
        }

        'FileSystem' {
            @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemDetection'
                path                 = Get-DetectionRuleValue -Rule $Rule -Name 'Path'
                fileOrFolderName     = Get-DetectionRuleValue -Rule $Rule -Name 'FileOrFolderName'
                check32BitOn64System = Get-DetectionRuleValue -Rule $Rule -Name 'Check32BitOn64System' -Boolean
                detectionType        = Get-DetectionRuleValue -Rule $Rule -Name 'DetectionType' -AllowedValue $script:FileSystemDetectionTypes
                operator             = Get-DetectionRuleValue -Rule $Rule -Name 'Operator' -AllowedValue $operators -Default 'notConfigured'
                detectionValue       = Get-DetectionRuleValue -Rule $Rule -Name 'DetectionValue' -Default ''
            }
        }

        'Registry' {
            @{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryDetection'
                check32BitOn64System = Get-DetectionRuleValue -Rule $Rule -Name 'Check32BitOn64System' -Boolean
                keyPath              = Get-DetectionRuleValue -Rule $Rule -Name 'KeyPath'
                valueName            = Get-DetectionRuleValue -Rule $Rule -Name 'ValueName' -Default ''
                detectionType        = Get-DetectionRuleValue -Rule $Rule -Name 'DetectionType' -AllowedValue $script:RegistryDetectionTypes
                operator             = Get-DetectionRuleValue -Rule $Rule -Name 'Operator' -AllowedValue $operators -Default 'notConfigured'
                detectionValue       = Get-DetectionRuleValue -Rule $Rule -Name 'DetectionValue' -Default ''
            }
        }

        'ProductCode' {
            @{
                '@odata.type'          = '#microsoft.graph.win32LobAppProductCodeDetection'
                productCode            = Get-DetectionRuleValue -Rule $Rule -Name 'ProductCode'
                productVersionOperator = Get-DetectionRuleValue -Rule $Rule -Name 'ProductVersionOperator' -AllowedValue $operators -Default 'notConfigured'
                productVersion         = Get-DetectionRuleValue -Rule $Rule -Name 'ProductVersion' -Default ''
            }
        }

        default {
            throw "Unsupported detection rule type '$_'. Use PowerShellScript, FileSystem, Registry, ProductCode, or a raw Graph rule with @odata.type."
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

    if (-not $Rule) {
        $Rule = @(@{ Type = 'PowerShellScript' })
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

function Wait-IntuneWin32FileProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileUri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Stage
    )

    $maxAttempts = 600
    $successState = "$($Stage)Success"
    $pendingState = "$($Stage)Pending"

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $FileUri -ErrorAction Stop
        if ($file.uploadState -eq $successState) {
            return $file
        }

        if ($file.uploadState -ne $pendingState) {
            throw "File processing failed at stage '$Stage' with state '$($file.uploadState)'."
        }

        Start-Sleep -Seconds 5
    }

    throw "File processing stage '$Stage' did not complete after $maxAttempts attempts."
}

function Send-AzureStorageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$SasUri,
        [Parameter(Mandatory = $true)] [string]$FilePath,
        [Parameter(Mandatory = $true)] [string]$FileUri
    )

    $stream = [System.IO.File]::OpenRead($FilePath)
    $blockIds = [System.Collections.Generic.List[string]]::new()
    $buffer = [byte[]]::new($script:ChunkSizeInBytes)
    $renewalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $blockHeaders = @{
        'x-ms-blob-type' = 'BlockBlob'
        'Content-Type'   = 'application/octet-stream'
    }

    try {
        $index = 0
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($index.ToString('000000')))
            $blockIds.Add($blockId)

            $chunk = $buffer
            if ($bytesRead -lt $buffer.Length) {
                $chunk = [byte[]]::new($bytesRead)
                [Array]::Copy($buffer, $chunk, $bytesRead)
            }
            $blockUri = "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))"
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

    $blockList = ($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join ''
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

    $appBody = [ordered]@{
        '@odata.type'                   = "#$script:Win32LobAppType"
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
        fileName                        = $appInfo.FileName
        setupFilePath                   = $appInfo.SetupFile
        installCommandLine              = $InstallCommandLine
        uninstallCommandLine            = $UninstallCommandLine
        installExperience               = @{ runAsAccount = 'system' }
        minimumSupportedOperatingSystem = @{ v10_1607 = $true }
        msiInformation                  = $null
        runAs32bit                      = $false
        detectionRules                  = @($DetectionRules)
        returnCodes                     = @(
            @{ returnCode = 0; type = 'success' }
            @{ returnCode = 1707; type = 'success' }
            @{ returnCode = 3010; type = 'softReboot' }
            @{ returnCode = 1641; type = 'hardReboot' }
            @{ returnCode = 1618; type = 'retry' }
        )
        largeIcon                       = ConvertTo-IntuneMimeContent -Path $IconPath
    }

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
        $fileCreateUri = "$contentVersionUri/$contentVersionId/files"
        $file = Invoke-IntuneGraphJsonRequest -Method POST -Uri $fileCreateUri -Body $fileBody
        if (-not $file.id) {
            throw 'Graph did not return a content file id.'
        }

        $fileUri = "$fileCreateUri/$($file.id)"
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

        Invoke-IntuneGraphJsonRequest -Method POST -Uri "$fileUri/commit" -Body $fileEncryptionInfo | Out-Null
        Wait-IntuneWin32FileProcessing -FileUri $fileUri -Stage 'CommitFile' | Out-Null

        $commitAppBody = @{
            '@odata.type'           = "#$script:Win32LobAppType"
            committedContentVersion = $contentVersionId
        }
        Invoke-IntuneGraphJsonRequest -Method PATCH -Uri "beta/deviceAppManagement/mobileApps/$appId" -Body $commitAppBody | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $contentFilePath -Force -ErrorAction SilentlyContinue
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

    $connectParams = @{
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }

    if ($TenantId) {
        $connectParams.TenantId = $TenantId
    }

    if ($ClientId -or $ClientSecret) {
        if (-not ($TenantId -and $ClientId -and $ClientSecret)) {
            throw 'TenantId, ClientId, and ClientSecret are all required for app-only authentication.'
        }

        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $connectParams.ClientSecretCredential = [pscredential]::new($ClientId, $secureSecret)
    }
    else {
        $connectParams.Scopes = 'DeviceManagementApps.ReadWrite.All'
    }

    Connect-MgGraph @connectParams | Out-Null
    $context = Get-MgContext
    if (-not $context) {
        throw 'Microsoft Graph connection did not return a context.'
    }

    $context
}
