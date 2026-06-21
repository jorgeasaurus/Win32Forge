#Requires -Version 7.0

. (Join-Path -Path $PSScriptRoot -ChildPath 'Private/Win32Forge.Private.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Public/Publish-IntuneWin32App.ps1')

Export-ModuleMember -Function 'Publish-IntuneWin32App'
