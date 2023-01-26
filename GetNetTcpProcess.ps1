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
        $state
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
            $process = Get-Process |Select-Object -Property Path,Name,Id
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
            $FinalOutput += $TempOutput
        }
    }
    End
    {
        $FinalOutput
    }
}
