# GetNetTcpProcess

`Get-NetTcpProcess` shows which process owns each TCP port on a Windows machine. It's a PowerShell version of `netstat -ano` that returns objects you can filter, sort, group and export. It combines `Get-NetTCPConnection` with process information from `Win32_Process`. Each connection comes back with its local and remote endpoints, its TCP state, and the owning process's name, ID and path. The parent process and command line are available on request. Use it to find out what's listening on a port, which program opened a connection, or which processes hold the most sockets.

## Install

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/GetNetTcpProcess):

```powershell
Install-PSResource -Name GetNetTcpProcess        # PowerShell 7.4+, or with Microsoft.PowerShell.PSResourceGet
Install-Module -Name GetNetTcpProcess -Scope CurrentUser   # PowerShellGet, e.g. Windows PowerShell 5.1
```

From a clone of this repository:

```powershell
Import-Module .\GetNetTcpProcess\GetNetTcpProcess.psd1
```

Dot-sourcing `GetNetTcpProcess.ps1`, as earlier versions did, still works: it now imports the module.

## Requirements

- Windows. The module uses `Get-NetTCPConnection` and CIM, which are Windows-only.
- Windows PowerShell 5.1, or PowerShell 7 or later.
- An elevated session (Run as administrator) to see the `Path`, `ProcessCommandLine` and parent of processes that run as SYSTEM or as another user. Without one, those properties may be empty for services and elevated processes. Everything else works without elevation.

## Parameters

| Parameter | Description |
|---|---|
| `-State <String[]>` | Returns only connections in the given TCP states. Accepts one or more of `Closed`, `Listen`, `SynSent`, `SynReceived`, `Established`, `FinWait1`, `FinWait2`, `CloseWait`, `Closing`, `LastAck`, `TimeWait`, `DeleteTCB`, `Bound`, for example `-State Listen, Established`. A state with no connections returns nothing, without an error. |
| `-Parent` | Adds `ParentProcessId` and `ParentProcess`. |
| `-CommandLine` | Adds `ProcessCommandLine`. |

See the [command reference](docs/Get-NetTcpProcess.md) for details, or run `Get-Help Get-NetTcpProcess -Full`.

## Output

One object per TCP connection:

| Property | Type | When | Description |
|---|---|---|---|
| `Address` | IPAddress | Always | Local IP address. |
| `Port` | Int32 | Always | Local port. |
| `ProcessName` | String | Always | Owning process name, without `.exe`. |
| `ProcessId` | Int32 | Always | Owning process ID. |
| `Path` | String | Always | Path of the process's executable. May be empty without elevation. |
| `ProcessCommandLine` | String | With `-CommandLine` | Command line of the process. May be empty without elevation. |
| `ParentProcessId` | Int32 | With `-Parent` | Parent process ID. |
| `ParentProcess` | String | With `-Parent` | Parent process name. Empty if the parent has exited, its PID was reused, or the parent PID is 0 or the process itself. |
| `State` | String | Always | TCP state, or the raw number for a state with no name (see [Known behavior](#known-behavior)). |
| `RemoteAddress` | IPAddress | Always | Remote IP address. |
| `RemotePort` | Int32 | Always | Remote port. |

## Examples

The output below is illustrative.

**What's using port 445?**

```powershell
Get-NetTcpProcess | Where-Object -Property Port -EQ 445
```
```
Address       : ::
Port          : 445
ProcessName   : System
ProcessId     : 4
Path          :
State         : Listen
RemoteAddress : ::
RemotePort    : 0
```

**All listening ports, with the process that started each owner**

```powershell
Get-NetTcpProcess -State Listen -Parent | Sort-Object -Property Port |
    Format-Table -Property Port, Address, ProcessName, ProcessId, ParentProcess
```
```
Port Address   ProcessName ProcessId ParentProcess
---- -------   ----------- --------- -------------
 135 0.0.0.0   svchost          1104 services
 445 ::        System              4
5432 127.0.0.1 postgres         6120 services
```

**Which processes own the most connections?**

```powershell
Get-NetTcpProcess | Group-Object -Property ProcessName -NoElement |
    Sort-Object -Property Count -Descending | Select-Object -First 10
```
```
Count Name
----- ----
  118 chrome
   23 svchost
    9 Code
```

**All connections owned by one process**

```powershell
Get-NetTcpProcess | Where-Object -Property ProcessName -EQ 'svchost' |
    Format-Table -Property ProcessId, Port, State, RemoteAddress, RemotePort
```
```
ProcessId  Port State       RemoteAddress RemotePort
---------  ---- -----       ------------- ----------
     1104   135 Listen      0.0.0.0                0
     2280 49702 Established 203.0.113.10         443
```

**What are processes connected to?**

```powershell
Get-NetTcpProcess -State Established |
    Format-Table -Property ProcessName, ProcessId, Port, RemoteAddress, RemotePort
```
```
ProcessName ProcessId  Port RemoteAddress RemotePort
----------- ---------  ---- ------------- ----------
chrome           8812 51234 203.0.113.25         443
Code             5040 51240 203.0.113.80         443
```

**Command lines of listening processes**

```powershell
Get-NetTcpProcess -State Listen -CommandLine |
    Format-List -Property Port, ProcessName, ProcessCommandLine
```
```
Port               : 135
ProcessName        : svchost
ProcessCommandLine : C:\Windows\system32\svchost.exe -k RPCSS -p
```

**Export to CSV**

```powershell
Get-NetTcpProcess -State Listen -Parent -CommandLine |
    Export-Csv -Path .\listeners.csv -NoTypeInformation
```

**A compact table with the columns you choose**

```powershell
Get-NetTcpProcess -State Listen | Sort-Object -Property Port |
    Format-Table -Property Port, Address, ProcessName, ProcessId, Path -AutoSize
```
```
Port Address ProcessName ProcessId Path
---- ------- ----------- --------- ----
 135 0.0.0.0 svchost          1104 C:\Windows\system32\svchost.exe
 445 ::      System              4
```

## Known behavior

- **States with no name show as a number.** Windows reports some connections with a state that has no name. `State` then shows the raw value, usually `0`, instead of a blank. `-State` can't select these connections.
- **The TCP table can change between queries, especially with Docker Desktop.** Docker Desktop's `com.docker.backend` can own thousands of connections, many with no-name or unusual states (`Bound`, `Closed`, `FinWait1`). With that many sockets, Windows' own answers aren't stable. The same socket can be reported as `Listen` in one call and `Closed`, `FinWait1` or `0` in the next, and `netstat -ano` shows the same churn. `-State` passes the state to `Get-NetTCPConnection`, so it returns what that cmdlet returns at that moment. To find a specific port reliably, leave out `-State` and filter on `Port`, as in the first example. To hide Docker's connections:

  ```powershell
  Get-NetTcpProcess | Where-Object -Property ProcessName -NE 'com.docker.backend'
  ```

- **`Format-Table` drops columns that don't fit.** Each object has 8 to 11 properties, so PowerShell shows them as a list by default. `Format-Table` silently drops the columns that don't fit the window. Choose the columns with `-Property`, as in the examples, or use `Format-List`, `Out-GridView` or `Export-Csv` to see everything.

## More

- [Command reference](docs/Get-NetTcpProcess.md)
- [Changelog](CHANGELOG.md)
- [License](LICENSE) (MIT)
- [PowerShell Gallery page](https://www.powershellgallery.com/packages/GetNetTcpProcess)

## Tests

The tests need Pester 5:

```powershell
Invoke-Pester -Path .\GetNetTcpProcess.Tests.ps1
```
