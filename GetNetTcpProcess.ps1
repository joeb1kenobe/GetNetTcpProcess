# Kept for compatibility with earlier versions, which were used by
# dot-sourcing this file (. .\GetNetTcpProcess.ps1). The function now lives
# in the GetNetTcpProcess module; prefer Install-Module GetNetTcpProcess.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'GetNetTcpProcess\GetNetTcpProcess.psd1') -Force
