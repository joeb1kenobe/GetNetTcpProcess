# GetNetTcpProcess
PowerShell module that combines Get-NetTCPConnection with process information so you can easily see each port and the process that has it open.

Works in Windows PowerShell 5.1 and PowerShell 7+ on Windows.

## Install

Install the module from the PowerShell Gallery:

```powershell
Install-Module GetNetTcpProcess
```

To use it from a clone of this repository instead:

```powershell
Import-Module .\GetNetTcpProcess\GetNetTcpProcess.psd1
```

Dot-sourcing `GetNetTcpProcess.ps1`, as earlier versions did, still works: it now imports the module.

## Usage

For example:

```powershell
Get-NetTcpProcess                                   # all TCP connections with their process
Get-NetTcpProcess -State Listen                     # listening ports only
Get-NetTcpProcess -State Listen, Established -Parent -CommandLine
Get-NetTcpProcess | Where-Object -Property Port -EQ 445
```

Run from an elevated session to see the path and command line of processes that run as other users (including SYSTEM services).

## Note: Docker Desktop and unusual states

Docker Desktop's `com.docker.backend` process can own thousands of TCP connections, many of them in states that Windows reports with no name (raw value `0`) or in unusual states such as `Bound`, `Closed` and `FinWait1`. For a state with no name, the `State` column shows the raw number (for example `0`) instead of a blank. `-State` matches named states only, so these connections never appear in filtered output.

With that many sockets, the states Windows reports are not stable: two back-to-back `Get-NetTCPConnection -State Listen` calls (or `netstat -ano`) can return different listeners, and an unfiltered query can report a listening socket as `Closed`. `Get-NetTcpProcess -State` therefore passes the state to `Get-NetTCPConnection` rather than filtering afterward, so it returns the same connections that cmdlet would at that moment. To hide Docker's connections:

```powershell
Get-NetTcpProcess | Where-Object -Property ProcessName -NE 'com.docker.backend'
```

## Tests

The tests need Pester 5:

```powershell
Invoke-Pester -Path .\GetNetTcpProcess.Tests.ps1
```
