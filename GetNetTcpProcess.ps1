<#
.Synopsis
   Get-NetTcpProcess
   Code by Joe Brown (joeb1kenobe) fell free to use this code, but do not republish as your own. If you discover a bug or see a way to imporve the code, please submit a pull request at https://github.com/joeb1kenobe/GetNetTcpProcess
.DESCRIPTION
   Get-NetTcpProcess will combine output from Get-Processes and Get-NetTCPConnections to provide a list of TCP connections and the associated processes.
.EXAMPLE
   Get-NetTcpProcess
.EXAMPLE
   Get-NetTcpProcess -state Listen
#>
class NetTcpProcessOutput
{
    [ipaddress]$Address
    [int]$Port
    [string]$State
    [string]$Path
    [string]$ProcessName
    [string]$ParentProcess
    [string]$ProcessCommandLine
}
function Get-NetTcpProcess
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        [ValidateSet("Listen","Established","Bound")]
        [string]
        $State,
        [switch]
        $CommandLine,
        [switch]
        $Parent
    )

    Begin
    {
        if ($state)
        {
            $Connections = Get-NetTCPConnection -State $state
        }
        else 
        {
            $Connections = Get-NetTCPConnection
            $process = Get-Process |Select-Object -Property Path,Name,Id,CommandLine,Parent
        }
        $FinalOutput = @()
    }
    Process
    {
        foreach($conn in $Connections)
        {
            $TempOutput = New-Object -TypeName NetTcpProcessOutput
            $id = $conn.OwningProcess
            $proc = ($process | Where-Object -Property id -eq $id)
            $TempOutput.Address = [ipaddress]$conn.LocalAddress
            $TempOutput.Path = $proc.Path
            $TempOutput.Port = $conn.LocalPort
            $TempOutput.ProcessName = $proc.name
            $TempOutput.State = $conn.State
            $TempOutput.ParentProcess = $proc.Parent
            $TempOutput.ProcessCommandLine = $proc.CommandLine
            $FinalOutput += $TempOutput
        }
    }
    End
    {
        if ($Parent -eq $false -and $CommandLine -eq $false)
        {
            $FinalOutput | Select-Object -Property Address,Port,ProcessName,Path,State
        }
        elseif ($Parent -eq $true -and $CommandLine -eq $false)
        {
            $FinalOutput | Select-Object -Property Address,Port,ProcessName,Path,ParentProcess,State
        }
        elseif ($Parent -eq $false -and $CommandLine -eq $true)
        {
            $FinalOutput | Select-Object -Property Address,Port,ProcessName,Path,ProcessCommandLine,State
        }
        else 
        {
            $FinalOutput | Select-Object -Property Address,Port,ProcessName,Path,ProcessCommandLine,ParentProcess,State
        }
    }
}
