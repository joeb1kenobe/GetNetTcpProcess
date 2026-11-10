<#
.SYNOPSIS
Lists TCP connections together with the process that owns each one.

.DESCRIPTION
Get-NetTcpProcess shows which process owns each TCP port: a PowerShell
version of netstat -ano that returns objects. It combines
Get-NetTCPConnection with process information from the Win32_Process CIM
class, and returns one object per connection with the local and remote
endpoints, the TCP state, and the owning process's name, ID and path.
Use -Parent and -CommandLine to add the parent process and the command line.

It works in Windows PowerShell 5.1 and PowerShell 7+ on Windows.

.PARAMETER State
Returns only connections in the given TCP states. Accepts one or more of:
Closed, Listen, SynSent, SynReceived, Established, FinWait1, FinWait2,
CloseWait, Closing, LastAck, TimeWait, DeleteTCB, Bound.

The states are passed to Get-NetTCPConnection, so the result is what that
cmdlet returns for the same states. A state with no connections returns
nothing, without an error. Connections whose state has no name (shown as a
number, such as 0) cannot be selected with -State.

.PARAMETER Parent
Adds the ParentProcessId and ParentProcess (the parent's process name)
properties.

ParentProcess is empty when the parent has exited, when its PID now belongs
to a newer, unrelated process, or when the parent PID is 0 or the process's
own PID (as for the System Idle Process and System).

.PARAMETER CommandLine
Adds the ProcessCommandLine property: the command line used to start the
owning process.

.EXAMPLE
Get-NetTcpProcess | Where-Object -Property Port -EQ 445

Shows which process has local port 445 open.

.EXAMPLE
Get-NetTcpProcess -State Listen -Parent | Sort-Object -Property Port | Format-Table -Property Port, Address, ProcessName, ProcessId, ParentProcess

Lists all listening ports in port order, with the owning process and the
process that started it.

.EXAMPLE
Get-NetTcpProcess | Group-Object -Property ProcessName -NoElement | Sort-Object -Property Count -Descending | Select-Object -First 10

Shows the ten processes that own the most TCP connections.

.EXAMPLE
Get-NetTcpProcess | Where-Object -Property ProcessName -EQ 'svchost' | Format-Table -Property ProcessId, Port, State, RemoteAddress, RemotePort

Lists every connection owned by a process, by process name (without .exe).

.EXAMPLE
Get-NetTcpProcess -State Established | Format-Table -Property ProcessName, ProcessId, Port, RemoteAddress, RemotePort

Lists established connections with the remote address and port each
process is connected to.

.EXAMPLE
Get-NetTcpProcess -State Listen -CommandLine | Format-List -Property Port, ProcessName, ProcessCommandLine

Shows the full command line of each listening process.

.EXAMPLE
Get-NetTcpProcess -State Listen -Parent -CommandLine | Export-Csv -Path .\listeners.csv -NoTypeInformation

Saves all listening ports, with parent and command line, to a CSV file.

.EXAMPLE
Get-NetTcpProcess -State Listen | Sort-Object -Property Port | Format-Table -Property Port, Address, ProcessName, ProcessId, Path -AutoSize

Shows listening ports as a compact table with the columns you choose.

.INPUTS
None. You cannot pipe objects to Get-NetTcpProcess.

.OUTPUTS
System.Management.Automation.PSCustomObject

One object per TCP connection, with these properties:
Address (local IP address), Port (local port), ProcessName, ProcessId,
Path, ProcessCommandLine (only with -CommandLine), ParentProcessId and
ParentProcess (only with -Parent), State, RemoteAddress and RemotePort.

.NOTES
Without an elevated (Run as administrator) session, Path,
ProcessCommandLine and the parent of processes that run as another user,
including SYSTEM services, may be empty.

Some connections have a state that Windows reports with no name. State then
shows the raw number, such as 0, instead of a blank.

On machines with many sockets, such as those running Docker Desktop, the TCP
table can change between queries: the same socket may be reported as
Listen in one call and Closed or 0 in the next.

Objects have more than four properties, so PowerShell shows them as a list
by default. Format-Table drops columns that do not fit the window, so pick
the columns you need with -Property.

Code by Joe Brown (joeb1kenobe). Feel free to use this code, but do not
republish it as your own. If you discover a bug or see a way to improve the
code, please submit a pull request at
https://github.com/joeb1kenobe/GetNetTcpProcess

.LINK
https://github.com/joeb1kenobe/GetNetTcpProcess/blob/main/docs/Get-NetTcpProcess.md

.LINK
Get-NetTCPConnection

.LINK
https://github.com/joeb1kenobe/GetNetTcpProcess
#>
function Get-NetTcpProcess
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [ValidateSet('Closed', 'Listen', 'SynSent', 'SynReceived', 'Established',
            'FinWait1', 'FinWait2', 'CloseWait', 'Closing', 'LastAck',
            'TimeWait', 'DeleteTCB', 'Bound')]
        [string[]]
        $State,

        [switch]
        $CommandLine,

        [switch]
        $Parent
    )

    # Let Get-NetTCPConnection filter by state. Filtering its unfiltered output
    # afterward is unreliable: with thousands of sockets (e.g. Docker Desktop),
    # the unfiltered query can report listening sockets as Closed.
    #
    # With -State, a state that has no connections produces an ObjectNotFound
    # error, which only means "no results". An advanced function's
    # -ErrorVariable collects errors from inner commands even when they are
    # caught or silenced, so run the query in a nested pipeline, whose errors
    # stay in its own Streams.Error. -ErrorAction Continue keeps a caller's
    # $ErrorActionPreference = 'Stop' from turning "no results" into a throw.
    $pipeline = [powershell]::Create([System.Management.Automation.RunspaceMode]::CurrentRunspace)
    try
    {
        $null = $pipeline.AddCommand('Get-NetTCPConnection').AddParameter('ErrorAction', 'Continue')
        if ($State)
        {
            $null = $pipeline.AddParameter('State', $State)
        }
        $connections = @($pipeline.Invoke())
        foreach ($connectionError in $pipeline.Streams.Error)
        {
            if ($connectionError.CategoryInfo.Category -ne [System.Management.Automation.ErrorCategory]::ObjectNotFound)
            {
                $PSCmdlet.WriteError($connectionError)
            }
        }
    }
    catch [System.Management.Automation.MethodInvocationException]
    {
        # Surface the command's own terminating error, not the Invoke() wrapper.
        throw $_.Exception.InnerException
    }
    finally
    {
        $pipeline.Dispose()
    }
    if ($connections.Count -eq 0)
    {
        return
    }

    # Win32_Process exposes ParentProcessId and CommandLine in both Windows
    # PowerShell 5.1 and PowerShell 7+, unlike the Parent and CommandLine
    # properties of Get-Process, which exist only in PowerShell 7+.
    $cimProperties = @('ProcessId', 'Name', 'ExecutablePath')
    if ($Parent)
    {
        $cimProperties += 'ParentProcessId', 'CreationDate'
    }
    if ($CommandLine)
    {
        $cimProperties += 'CommandLine'
    }

    # Index processes by PID so each connection is an O(1) lookup.
    $processById = @{}
    foreach ($process in Get-CimInstance -ClassName Win32_Process -Property $cimProperties)
    {
        $processById[[int]$process.ProcessId] = $process
    }

    foreach ($connection in $connections)
    {
        $owningProcessId = [int]$connection.OwningProcess
        $process = $processById[$owningProcessId]

        $output = [ordered]@{
            PSTypeName  = 'NetTcpProcess'
            Address     = [ipaddress]$connection.LocalAddress
            Port        = [int]$connection.LocalPort
            ProcessName = $null
            ProcessId   = $owningProcessId
            Path        = $null
        }
        if ($process)
        {
            # Match the Get-Process naming used by earlier versions (no .exe).
            $output.ProcessName = $process.Name -replace '\.exe$'
            $output.Path = $process.ExecutablePath
        }

        if ($CommandLine)
        {
            $output.ProcessCommandLine = if ($process) { $process.CommandLine } else { $null }
        }

        if ($Parent)
        {
            $output.ParentProcessId = $null
            $output.ParentProcess = $null
            if ($process)
            {
                $parentProcessId = [int]$process.ParentProcessId
                $output.ParentProcessId = $parentProcessId
                # PID 0 is not a real parent: Windows reports it for System
                # Idle Process (whose "parent" is itself) and for System (4).
                $parentProcess = $null
                if ($parentProcessId -ne 0 -and $parentProcessId -ne $owningProcessId)
                {
                    $parentProcess = $processById[$parentProcessId]
                }
                # PIDs are reused: a "parent" created after its child is an
                # unrelated process that inherited the exited parent's PID.
                $isRealParent = $parentProcess -and (
                    $null -eq $parentProcess.CreationDate -or
                    $null -eq $process.CreationDate -or
                    $parentProcess.CreationDate -le $process.CreationDate)
                if ($isRealParent)
                {
                    $output.ParentProcess = $parentProcess.Name -replace '\.exe$'
                }
            }
        }

        # Some states (e.g. 0, seen on Docker Desktop's connections) have no
        # enum name, so State is $null. Show the raw CIM value instead.
        $output.State = [string]$connection.State
        if (-not $output.State -and $connection.CimInstanceProperties)
        {
            $output.State = [string]$connection.CimInstanceProperties['State'].Value
        }
        $output.RemoteAddress = [ipaddress]$connection.RemoteAddress
        $output.RemotePort = [int]$connection.RemotePort

        [pscustomobject]$output
    }
}

Export-ModuleMember -Function Get-NetTcpProcess
