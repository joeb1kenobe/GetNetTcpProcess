---
external help file: GetNetTcpProcess-help.xml
Module Name: GetNetTcpProcess
online version: https://github.com/joeb1kenobe/GetNetTcpProcess/blob/main/docs/Get-NetTcpProcess.md
schema: 2.0.0
---

# Get-NetTcpProcess

## SYNOPSIS
Lists TCP connections together with the process that owns each one.

## SYNTAX

```
Get-NetTcpProcess [[-State] <String[]>] [-CommandLine] [-Parent] [<CommonParameters>]
```

## DESCRIPTION
Get-NetTcpProcess shows which process owns each TCP port: a PowerShell version of `netstat -ano` that returns objects. It combines `Get-NetTCPConnection` with process information from the `Win32_Process` CIM class, and returns one object per connection with the local and remote endpoints, the TCP state, and the owning process's name, ID and path. Use `-Parent` and `-CommandLine` to add the parent process and the command line.

It works in Windows PowerShell 5.1 and PowerShell 7+ on Windows.

## EXAMPLES

### Example 1: Find the process using a port
```powershell
Get-NetTcpProcess | Where-Object -Property Port -EQ 445
```

Shows which process has local port 445 open.

### Example 2: List listening ports with their parent process
```powershell
Get-NetTcpProcess -State Listen -Parent | Sort-Object -Property Port | Format-Table -Property Port, Address, ProcessName, ProcessId, ParentProcess
```

Lists all listening ports in port order, with the owning process and the process that started it.

### Example 3: Count connections per process
```powershell
Get-NetTcpProcess | Group-Object -Property ProcessName -NoElement | Sort-Object -Property Count -Descending | Select-Object -First 10
```

Shows the ten processes that own the most TCP connections.

### Example 4: List a process's connections
```powershell
Get-NetTcpProcess | Where-Object -Property ProcessName -EQ 'svchost' | Format-Table -Property ProcessId, Port, State, RemoteAddress, RemotePort
```

Lists every connection owned by a process, by process name (without `.exe`).

### Example 5: Show what processes are connected to
```powershell
Get-NetTcpProcess -State Established | Format-Table -Property ProcessName, ProcessId, Port, RemoteAddress, RemotePort
```

Lists established connections with the remote address and port each process is connected to.

### Example 6: Show the command line of listening processes
```powershell
Get-NetTcpProcess -State Listen -CommandLine | Format-List -Property Port, ProcessName, ProcessCommandLine
```

Shows the full command line of each listening process.

### Example 7: Export to CSV
```powershell
Get-NetTcpProcess -State Listen -Parent -CommandLine | Export-Csv -Path .\listeners.csv -NoTypeInformation
```

Saves all listening ports, with parent and command line, to a CSV file.

### Example 8: Show a compact table
```powershell
Get-NetTcpProcess -State Listen | Sort-Object -Property Port | Format-Table -Property Port, Address, ProcessName, ProcessId, Path -AutoSize
```

Shows listening ports as a compact table with the columns you choose.

## PARAMETERS

### -State
Returns only connections in the given TCP states. Accepts one or more of: `Closed`, `Listen`, `SynSent`, `SynReceived`, `Established`, `FinWait1`, `FinWait2`, `CloseWait`, `Closing`, `LastAck`, `TimeWait`, `DeleteTCB`, `Bound`.

The states are passed to `Get-NetTCPConnection`, so the result is what that cmdlet returns for the same states. A state with no connections returns nothing, without an error. Connections whose state has no name (shown as a number, such as `0`) cannot be selected with `-State`.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Accepted values: Closed, Listen, SynSent, SynReceived, Established, FinWait1, FinWait2, CloseWait, Closing, LastAck, TimeWait, DeleteTCB, Bound

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -CommandLine
Adds the `ProcessCommandLine` property: the command line used to start the owning process.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Parent
Adds the `ParentProcessId` and `ParentProcess` (the parent's process name) properties.

`ParentProcess` is empty when the parent has exited, when its PID now belongs to a newer, unrelated process, or when the parent PID is 0 or the process's own PID (as for the System Idle Process and System).

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## INPUTS

### None
You cannot pipe objects to Get-NetTcpProcess.

## OUTPUTS

### System.Management.Automation.PSCustomObject
One object per TCP connection, with these properties:

| Property | Type | Description |
|---|---|---|
| Address | IPAddress | Local IP address. |
| Port | Int32 | Local port. |
| ProcessName | String | Owning process name, without `.exe`. |
| ProcessId | Int32 | Owning process ID. |
| Path | String | Path of the process's executable. |
| ProcessCommandLine | String | Command line of the process. Only with `-CommandLine`. |
| ParentProcessId | Int32 | Parent process ID. Only with `-Parent`. |
| ParentProcess | String | Parent process name. Only with `-Parent`. |
| State | String | TCP state, or the raw number for a state with no name. |
| RemoteAddress | IPAddress | Remote IP address. |
| RemotePort | Int32 | Remote port. |

## NOTES
Without an elevated (Run as administrator) session, `Path`, `ProcessCommandLine` and the parent of processes that run as another user, including SYSTEM services, may be empty.

Some connections have a state that Windows reports with no name. `State` then shows the raw number, such as `0`, instead of a blank.

On machines with many sockets, such as those running Docker Desktop, the TCP table can change between queries: the same socket may be reported as `Listen` in one call and `Closed` or `0` in the next.

Objects have more than four properties, so PowerShell shows them as a list by default. `Format-Table` drops columns that do not fit the window, so pick the columns you need with `-Property`.

Copyright (c) 2023-2026 Joe Brown (joeb1kenobe). Licensed under the MIT License; see the [LICENSE](https://github.com/joeb1kenobe/GetNetTcpProcess/blob/main/LICENSE) file. Bug reports and pull requests are welcome at https://github.com/joeb1kenobe/GetNetTcpProcess

## RELATED LINKS

[Online version](https://github.com/joeb1kenobe/GetNetTcpProcess/blob/main/docs/Get-NetTcpProcess.md)

[Get-NetTCPConnection](https://learn.microsoft.com/powershell/module/nettcpip/get-nettcpconnection)

[GetNetTcpProcess on GitHub](https://github.com/joeb1kenobe/GetNetTcpProcess)
