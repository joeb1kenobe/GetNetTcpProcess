<#
.Synopsis
   Get-NetTcpProcess
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
        }
        $FinalOutput = @()
    }
    Process
    {
        foreach($conn in $Connections)
        {
            $TempOutput = New-Object -TypeName NetTcpProcessOutput
            $id = $conn.OwningProcess
            $proc = (get-process | Select-Object -Property path,name,id | Where-Object -Property id -eq $id)
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