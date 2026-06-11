$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ModulePath = Join-Path $script:RepoRoot 'IntuneWin32AppPublisher.psm1'
Import-Module $script:ModulePath -Force

Describe 'IntuneWin32AppPublisher helpers' {
    InModuleScope IntuneWin32AppPublisher {
        BeforeEach {
            $script:SourceDirectory = Join-Path $TestDrive 'source'
            New-Item -Path $script:SourceDirectory -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $script:SourceDirectory 'install.ps1') -Value 'exit 0'
            Set-Content -Path (Join-Path $script:SourceDirectory 'uninstall.ps1') -Value 'exit 0'
            Set-Content -Path (Join-Path $script:SourceDirectory 'detection.ps1') -Value 'Write-Output "Detected"'
            [System.IO.File]::WriteAllBytes((Join-Path $script:SourceDirectory 'icon.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
        }

        It 'requires the expected install, uninstall, detection, and icon files' {
            Resolve-IntuneWin32PublisherFile -SourceDirectory $script:SourceDirectory -FileName 'install.ps1' -Purpose 'Install script' |
                Should -Be (Join-Path $script:SourceDirectory 'install.ps1')

            { Resolve-IntuneWin32PublisherFile -SourceDirectory $script:SourceDirectory -FileName 'missing.ps1' -Purpose 'Install script' } |
                Should -Throw "*missing.ps1*"
        }

        It 'builds a PowerShell script detection rule from detection.ps1' {
            $rule = ConvertTo-PowerShellScriptDetectionRule -ScriptPath (Join-Path $script:SourceDirectory 'detection.ps1')
            $decodedScript = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rule.scriptContent))

            $rule.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppPowerShellScriptDetection'
            $rule.enforceSignatureCheck | Should -BeFalse
            $rule.runAs32Bit | Should -BeFalse
            $decodedScript | Should -Match 'Detected'
        }

        It 'creates Company Portal icon MIME content from a PNG file' {
            $icon = ConvertTo-IntuneMimeContent -Path (Join-Path $script:SourceDirectory 'icon.png')

            $icon.'@odata.type' | Should -Be '#microsoft.graph.mimeContent'
            $icon.type | Should -Be 'image/png'
            $icon.value | Should -Not -BeNullOrEmpty
        }

        It 'builds the Win32 app body with default settings and supplied metadata' {
            $body = ConvertTo-Win32LobAppBody `
                -DisplayName 'Contoso Tool' `
                -Publisher 'Contoso' `
                -Version '1.2.3' `
                -Description 'Contoso Tool 1.2.3' `
                -FileName 'install.intunewin' `
                -SetupFilePath 'install.ps1' `
                -InstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"' `
                -UninstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"' `
                -DetectionRules @(@{ scriptContent = 'abc' }) `
                -ReturnCodes @(Get-DefaultWin32ReturnCode) `
                -LargeIcon @{ type = 'image/png'; value = 'abc' }

            $body.'@odata.type' | Should -Be '#microsoft.graph.win32LobApp'
            $body.displayName | Should -Be 'Contoso Tool'
            $body.publisher | Should -Be 'Contoso'
            $body.displayVersion | Should -Be '1.2.3'
            $body.installExperience.runAsAccount | Should -Be 'system'
            $body.minimumSupportedOperatingSystem.v10_1607 | Should -BeTrue
            $body.detectionRules.Count | Should -Be 1
            $body.returnCodes.Count | Should -Be 5
            $body.largeIcon.type | Should -Be 'image/png'
        }
    }
}

Describe 'Publish-IntuneWin32App orchestration' {
    InModuleScope IntuneWin32AppPublisher {
        BeforeEach {
            $script:SourceDirectory = Join-Path $TestDrive 'source'
            $script:OutputDirectory = Join-Path $TestDrive 'output'
            New-Item -Path $script:SourceDirectory -ItemType Directory -Force | Out-Null
            New-Item -Path $script:OutputDirectory -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $script:SourceDirectory 'install.ps1') -Value 'exit 0'
            Set-Content -Path (Join-Path $script:SourceDirectory 'uninstall.ps1') -Value 'exit 0'
            Set-Content -Path (Join-Path $script:SourceDirectory 'detection.ps1') -Value 'exit 0'
            [System.IO.File]::WriteAllBytes((Join-Path $script:SourceDirectory 'icon.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10))

            function Connect-MgGraph {}
            function Get-MgContext {}
            function Disconnect-MgGraph {}

            Mock Test-PublisherRequiredModule {}
            Mock Import-Module {}
            Mock Connect-MgGraph {}
            Mock Get-MgContext { [pscustomobject]@{ TenantId = 'tenant-1' } }
            Mock Disconnect-MgGraph {}
            Mock Compress-IntuneWin32PackageFile { Join-Path $script:OutputDirectory 'install.intunewin' }
            Mock Get-IntuneWin32AppByDisplayName { @() }
            Mock Remove-IntuneWin32App {}
            Mock Invoke-IntuneWin32LobUpload {
                [pscustomobject]@{
                    id          = 'app-1'
                    displayName = $DisplayName
                }
            }
        }

        It 'packages the source directory and uploads using existing PowerShell scripts' {
            $result = Publish-IntuneWin32App `
                -SourceDirectory $script:SourceDirectory `
                -Name 'Contoso Tool' `
                -Publisher 'Contoso' `
                -Version '1.2.3' `
                -OutputDirectory $script:OutputDirectory `
                -KeepConnected

            $result.Id | Should -Be 'app-1'
            $result.PackagePath | Should -Be (Join-Path $script:OutputDirectory 'install.intunewin')

            Should -Invoke Invoke-IntuneWin32LobUpload -Times 1 -ParameterFilter {
                $DisplayName -eq 'Contoso Tool' -and
                $Publisher -eq 'Contoso' -and
                $Developer -eq 'Contoso' -and
                $Version -eq '1.2.3' -and
                $Description -eq 'Contoso Tool 1.2.3' -and
                $InstallCommandLine -eq 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"' -and
                $UninstallCommandLine -eq 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"' -and
                $DetectionScriptPath -eq (Join-Path $script:SourceDirectory 'detection.ps1') -and
                $IconPath -eq (Join-Path $script:SourceDirectory 'icon.png')
            }
        }

        It 'blocks duplicate Win32 apps unless Force is used' {
            Mock Get-IntuneWin32AppByDisplayName { @([pscustomobject]@{ id = 'existing-1'; displayName = 'Contoso Tool' }) }

            {
                Publish-IntuneWin32App `
                    -SourceDirectory $script:SourceDirectory `
                    -Name 'Contoso Tool' `
                    -Publisher 'Contoso' `
                    -Version '1.2.3' `
                    -OutputDirectory $script:OutputDirectory `
                    -KeepConnected
            } | Should -Throw "*already exists*"

            Should -Invoke Invoke-IntuneWin32LobUpload -Times 0
        }

        It 'removes duplicate Win32 apps when Force is used' {
            Mock Get-IntuneWin32AppByDisplayName { @([pscustomobject]@{ id = 'existing-1'; displayName = 'Contoso Tool' }) }

            Publish-IntuneWin32App `
                -SourceDirectory $script:SourceDirectory `
                -Name 'Contoso Tool' `
                -Publisher 'Contoso' `
                -Version '1.2.3' `
                -OutputDirectory $script:OutputDirectory `
                -Force `
                -KeepConnected | Out-Null

            Should -Invoke Remove-IntuneWin32App -ParameterFilter {
                $AppId -eq 'existing-1' -and $DisplayName -eq 'Contoso Tool'
            } -Times 1
            Should -Invoke Invoke-IntuneWin32LobUpload -Times 1
        }
    }
}

Describe 'Example app directory' {
    InModuleScope IntuneWin32AppPublisher {
        It 'contains the default source files expected by Publish-IntuneWin32App' {
            $repoRoot = Split-Path -Parent $PSScriptRoot
            $examplePath = Join-Path $repoRoot 'Examples/ContosoSampleApp'

            Resolve-IntuneWin32PublisherFile -SourceDirectory $examplePath -FileName 'install.ps1' -Purpose 'Install script' |
                Should -Be (Join-Path $examplePath 'install.ps1')
            Resolve-IntuneWin32PublisherFile -SourceDirectory $examplePath -FileName 'uninstall.ps1' -Purpose 'Uninstall script' |
                Should -Be (Join-Path $examplePath 'uninstall.ps1')
            Resolve-IntuneWin32PublisherFile -SourceDirectory $examplePath -FileName 'detection.ps1' -Purpose 'Detection script' |
                Should -Be (Join-Path $examplePath 'detection.ps1')
            Resolve-IntuneWin32PublisherFile -SourceDirectory $examplePath -FileName 'icon.png' -Purpose 'Company Portal icon' |
                Should -Be (Join-Path $examplePath 'icon.png')

            $iconBytes = [IO.File]::ReadAllBytes((Join-Path $examplePath 'icon.png'))
            ($iconBytes[0..7] -join ',') | Should -Be '137,80,78,71,13,10,26,10'
        }
    }
}

Describe 'Invoke-IntuneWin32LobUpload Graph requests' {
    InModuleScope IntuneWin32AppPublisher {
        BeforeEach {
            $script:SourceDirectory = Join-Path $TestDrive 'source'
            $script:StagingDirectory = Join-Path $TestDrive 'staging'
            New-Item -Path $script:SourceDirectory -ItemType Directory -Force | Out-Null
            New-Item -Path $script:StagingDirectory -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $script:SourceDirectory 'detection.ps1') -Value 'exit 0'
            [System.IO.File]::WriteAllBytes((Join-Path $script:SourceDirectory 'icon.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
            [System.IO.File]::WriteAllBytes((Join-Path $TestDrive 'package.intunewin'), [byte[]](1, 2, 3))

            [xml]$script:PackageMetadata = @'
<ApplicationInfo>
  <Name>Contoso Tool</Name>
  <FileName>encrypted.bin</FileName>
  <SetupFile>install.ps1</SetupFile>
  <UnencryptedContentSize>123</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>key</EncryptionKey>
    <macKey>mac-key</macKey>
    <initializationVector>iv</initializationVector>
    <mac>mac</mac>
    <fileDigest>digest</fileDigest>
    <fileDigestAlgorithm>SHA256</fileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@

            $script:GraphRequests = [System.Collections.Generic.List[object]]::new()

            Mock Get-IntuneWin32PackageManifest { $script:PackageMetadata }
            Mock Expand-IntuneWin32EncryptedFile {
                $encryptedPath = Join-Path $script:StagingDirectory 'encrypted.bin'
                [System.IO.File]::WriteAllBytes($encryptedPath, [byte[]](1, 2, 3, 4))
                $encryptedPath
            }
            Mock Invoke-IntuneGraphJsonRequest {
                param($Method, $Uri, $Body)

                $script:GraphRequests.Add([pscustomobject]@{
                    Method = $Method
                    Uri    = $Uri
                    Body   = $Body
                })

                if ($Uri -eq 'beta/deviceAppManagement/mobileApps/') {
                    return [pscustomobject]@{ id = 'app-1'; displayName = 'Contoso Tool' }
                }

                if ($Uri -like '*/contentVersions') {
                    return [pscustomobject]@{ id = 'version-1' }
                }

                if ($Uri -like '*/files') {
                    return [pscustomobject]@{ id = 'file-1' }
                }

                [pscustomobject]@{}
            }
            Mock Wait-IntuneWin32FileProcessing {
                param($FileUri, $Stage)
                $null = $FileUri

                if ($Stage -eq 'AzureStorageUriRequest') {
                    return [pscustomobject]@{ azureStorageUri = 'https://storage.example/upload?sas=1' }
                }

                [pscustomobject]@{ uploadState = "$($Stage)Success" }
            }
            Mock Send-AzureStorageFile {}
        }

        It 'posts the Win32 app body, uploads content, and commits the app version' {
            Invoke-IntuneWin32LobUpload `
                -PackagePath (Join-Path $TestDrive 'package.intunewin') `
                -DisplayName 'Contoso Tool' `
                -Publisher 'Contoso' `
                -Version '1.2.3' `
                -Description 'Contoso Tool 1.2.3' `
                -InstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"' `
                -UninstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"' `
                -DetectionScriptPath (Join-Path $script:SourceDirectory 'detection.ps1') `
                -IconPath (Join-Path $script:SourceDirectory 'icon.png') `
                -StagingDirectory $script:StagingDirectory | Out-Null

            $createRequest = $script:GraphRequests | Where-Object Uri -eq 'beta/deviceAppManagement/mobileApps/' | Select-Object -First 1
            $createRequest.Method | Should -Be 'POST'
            $createRequest.Body.displayName | Should -Be 'Contoso Tool'
            $createRequest.Body.publisher | Should -Be 'Contoso'
            $createRequest.Body.displayVersion | Should -Be '1.2.3'
            $createRequest.Body.installCommandLine | Should -Be 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"'
            $createRequest.Body.uninstallCommandLine | Should -Be 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"'
            $createRequest.Body.detectionRules[0].'@odata.type' | Should -Be '#microsoft.graph.win32LobAppPowerShellScriptDetection'
            $createRequest.Body.largeIcon.type | Should -Be 'image/png'

            Should -Invoke Send-AzureStorageFile -ParameterFilter {
                $SasUri -eq 'https://storage.example/upload?sas=1' -and
                $FilePath -like '*encrypted.bin'
            } -Times 1

            ($script:GraphRequests | Where-Object Uri -like '*/commit').Count | Should -Be 1
            ($script:GraphRequests | Where-Object { $_.Method -eq 'PATCH' -and $_.Uri -eq 'beta/deviceAppManagement/mobileApps/app-1' }).Body.committedContentVersion |
                Should -Be 'version-1'
        }
    }
}
