<#
.SYNOPSIS
Lists TCP connections together with the process that owns each one.

.DESCRIPTION
Get-NetTcpProcess combines the output of Get-NetTCPConnection with process
information from the Win32_Process CIM class, so you can see which process
owns which TCP port. It works in Windows PowerShell 5.1 and PowerShell 7+
on Windows.

Code by Joe Brown (joeb1kenobe). Feel free to use this code, but do not
republish it as your own. If you discover a bug or see a way to improve the
code, please submit a pull request at
https://github.com/joeb1kenobe/GetNetTcpProcess

.PARAMETER State
Limits the output to connections in one or more TCP states: Closed, Listen,
SynSent, SynReceived, Established, FinWait1, FinWait2, CloseWait, Closing,
LastAck, TimeWait, DeleteTCB, Bound.

.PARAMETER CommandLine
Adds the ProcessCommandLine property: the command line used to start the
owning process, if available.

.PARAMETER Parent
Adds the ParentProcessId and ParentProcess (parent process name) properties,
if available.

.EXAMPLE
Get-NetTcpProcess -State Bound -CommandLine

Lists all ports in the Bound state, with the command line used to start the
owning process.

.EXAMPLE
Get-NetTcpProcess -State Listen, Established -Parent

Lists all listening and established connections, with the parent of the
owning process.

.EXAMPLE
Get-NetTcpProcess | Where-Object -Property Port -EQ 445

Shows the process that has local port 445 open.

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
Without elevation, Path, ProcessCommandLine and the parent of processes that
run as another user (including SYSTEM services) may be empty.
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
