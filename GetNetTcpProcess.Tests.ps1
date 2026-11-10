#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'GetNetTcpProcess\GetNetTcpProcess.psd1'
    Import-Module -Name $manifestPath -Force

    function Get-FakeConnection
    {
        param ($LocalAddress, $LocalPort, $State, $OwningProcess,
            $RemoteAddress = '0.0.0.0', $RemotePort = 0)

        [pscustomobject]@{
            LocalAddress  = $LocalAddress
            LocalPort     = $LocalPort
            RemoteAddress = $RemoteAddress
            RemotePort    = $RemotePort
            State         = $State
            OwningProcess = $OwningProcess
        }
    }

    function Get-FakeProcess
    {
        param ($ProcessId, $Name, $ExecutablePath, $ParentProcessId, $CommandLine, $CreationDate)

        [pscustomobject]@{
            ProcessId       = $ProcessId
            Name            = $Name
            ExecutablePath  = $ExecutablePath
            ParentProcessId = $ParentProcessId
            CommandLine     = $CommandLine
            CreationDate    = $CreationDate
        }
    }

    $script:listenConnection = Get-FakeConnection -LocalAddress '0.0.0.0' -LocalPort 445 -State 'Listen' -OwningProcess 4
    $script:webConnection = Get-FakeConnection -LocalAddress '127.0.0.1' -LocalPort 8080 -State 'Listen' -OwningProcess 1000
    $script:establishedConnection = Get-FakeConnection -LocalAddress '192.168.1.10' -LocalPort 50000 -State 'Established' `
        -OwningProcess 2000 -RemoteAddress '203.0.113.5' -RemotePort 443
    $script:orphanConnection = Get-FakeConnection -LocalAddress '::' -LocalPort 9999 -State 'Listen' -OwningProcess 4242

    # A real connection whose raw CIM State (0) has no enum name: State is $null.
    $script:unnamedStateConnection = Get-FakeConnection -LocalAddress '::' -LocalPort 60000 -State $null -OwningProcess 1000
    $script:unnamedStateConnection | Add-Member -NotePropertyName CimInstanceProperties -NotePropertyValue @{
        State = [pscustomobject]@{ Value = [uint32]0 }
    }
}

Describe 'Get-NetTcpProcess' {
    BeforeEach {
        Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess {
            $script:listenConnection
            $script:webConnection
            $script:establishedConnection
        }
        # Like the real cmdlet, -State filters, and a state with no connections
        # writes a non-terminating ObjectNotFound error.
        Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess -ParameterFilter { $null -ne $State } {
            $all = $script:listenConnection, $script:webConnection, $script:establishedConnection
            foreach ($requested in $State)
            {
                $found = @($all | Where-Object -FilterScript { $_.State -eq [string]$requested })
                if ($found.Count -eq 0)
                {
                    Write-Error -Message "No MSFT_NetTCPConnection objects found with property 'State' equal to '$requested'." `
                        -Category ObjectNotFound
                }
                $found
            }
        }

        Mock Get-CimInstance -ModuleName GetNetTcpProcess -ParameterFilter { $ClassName -eq 'Win32_Process' } {
            Get-FakeProcess -ProcessId 4 -Name 'System' -ParentProcessId 0
            Get-FakeProcess -ProcessId 900 -Name 'explorer.exe' -ExecutablePath 'C:\Windows\explorer.exe' `
                -ParentProcessId 800 -CreationDate ([datetime]'2026-01-01 08:00')
            Get-FakeProcess -ProcessId 1000 -Name 'node.exe' -ExecutablePath 'C:\Program Files\nodejs\node.exe' `
                -ParentProcessId 900 -CommandLine '"node.exe" server.js' -CreationDate ([datetime]'2026-01-01 09:00')
            Get-FakeProcess -ProcessId 2000 -Name 'chrome.exe' -ExecutablePath 'C:\Program Files\Google\Chrome\chrome.exe' `
                -ParentProcessId 900 -CommandLine '"chrome.exe" --flag' -CreationDate ([datetime]'2026-01-01 10:00')
        }
    }

    Context 'No filter' {
        It 'Returns one object per connection, joined to its process' {
            $result = @(Get-NetTcpProcess)

            $result.Count | Should -Be 3
            $web = $result | Where-Object Port -EQ 8080
            $web.ProcessName | Should -Be 'node'
            $web.ProcessId | Should -Be 1000
            $web.Path | Should -Be 'C:\Program Files\nodejs\node.exe'
            $web.Address | Should -Be ([ipaddress]'127.0.0.1')
            $web.State | Should -Be 'Listen'
            Should -Invoke Get-CimInstance -ModuleName GetNetTcpProcess -Times 1 -Exactly
        }

        It 'Includes the remote endpoint' {
            $established = Get-NetTcpProcess | Where-Object Port -EQ 50000

            $established.RemoteAddress | Should -Be ([ipaddress]'203.0.113.5')
            $established.RemotePort | Should -Be 443
        }

        It 'Omits optional properties unless their switch is used' {
            $propertyNames = (Get-NetTcpProcess | Select-Object -First 1).PSObject.Properties.Name

            $propertyNames | Should -Not -Contain 'ProcessCommandLine'
            $propertyNames | Should -Not -Contain 'ParentProcess'
            $propertyNames | Should -Not -Contain 'ParentProcessId'
        }
    }

    Context '-State filter' {
        It 'Passes -State to Get-NetTCPConnection and still resolves the process' {
            $result = @(Get-NetTcpProcess -State Listen)

            $result.Count | Should -Be 2
            $result.State | Should -Not -Contain 'Established'
            ($result | Where-Object Port -EQ 8080).ProcessName | Should -Be 'node'
            ($result | Where-Object Port -EQ 445).ProcessName | Should -Be 'System'
            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter { $State -contains 'Listen' }
        }

        It 'Passes several states in one call' {
            $result = @(Get-NetTcpProcess -State Listen, Established)

            $result.Count | Should -Be 3
            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter {
                $State -contains 'Listen' -and $State -contains 'Established'
            }
        }

        It 'Does not call Get-NetTCPConnection with -State when no state is given' {
            $null = Get-NetTcpProcess

            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter { $null -eq $State }
        }

        It 'Keeps every connection Get-NetTCPConnection returns, without filtering again' {
            # Regression: with thousands of sockets, the state the cmdlet reports
            # on an object can disagree with the state it was queried by.
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess -ParameterFilter { $State -contains 'Listen' } {
                Get-FakeConnection -LocalAddress '127.0.0.1' -LocalPort 5432 -State 'Closed' -OwningProcess 1000
            }

            $result = @(Get-NetTcpProcess -State Listen)

            $result.Count | Should -Be 1
            $result[0].Port | Should -Be 5432
        }

        It 'Rejects an unknown state' {
            { Get-NetTcpProcess -State 'Bogus' } | Should -Throw
        }
    }

    Context 'No matches and errors' {
        It 'Returns nothing and leaks no error into the caller''s -ErrorVariable' {
            $result = Get-NetTcpProcess -State Bound -ErrorVariable getErrors -ErrorAction Stop

            $result | Should -BeNullOrEmpty
            $getErrors | Should -BeNullOrEmpty
            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter { $State -contains 'Bound' }
            Should -Invoke Get-CimInstance -ModuleName GetNetTcpProcess -Times 0 -Exactly
        }

        It 'Calls Get-NetTCPConnection with -ErrorAction Continue, so a caller''s Stop preference cannot turn "no results" into a throw' {
            # Asserted on the call: a module-scoped mock body ignores the
            # -ErrorAction it is given and uses the test's own preference.
            $null = Get-NetTcpProcess -State Bound

            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter {
                $ErrorAction -eq 'Continue'
            }
        }

        It 'Returns the matching states when only some states have connections' {
            $result = @(Get-NetTcpProcess -State Bound, Established -ErrorVariable getErrors)

            $result.Count | Should -Be 1
            $result[0].Port | Should -Be 50000
            $getErrors | Should -BeNullOrEmpty
        }

        It 'Returns nothing when there are no connections at all' {
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess { }

            Get-NetTcpProcess | Should -BeNullOrEmpty
            Should -Invoke Get-CimInstance -ModuleName GetNetTcpProcess -Times 0 -Exactly
        }

        It 'Passes other errors from Get-NetTCPConnection on to the caller' {
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess -ParameterFilter { $State -contains 'Listen' } {
                Write-Error -Message 'Access denied' -Category PermissionDenied
            }

            { Get-NetTcpProcess -State Listen -ErrorAction Stop } | Should -Throw '*Access denied*'
        }

        It 'Reports other errors as non-terminating by default' {
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess { Write-Error -Message 'Access denied' -Category PermissionDenied }

            $null = Get-NetTcpProcess -ErrorVariable getErrors -ErrorAction SilentlyContinue

            @($getErrors).Count | Should -Be 1
            $getErrors[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        }
    }

    Context '-Parent' {
        It 'Adds the parent process id and name' {
            $web = Get-NetTcpProcess -Parent | Where-Object Port -EQ 8080

            $web.ParentProcessId | Should -Be 900
            $web.ParentProcess | Should -Be 'explorer'
        }

        It 'Leaves ParentProcess empty when the parent has exited' {
            $system = Get-NetTcpProcess -Parent | Where-Object Port -EQ 445

            $system.ParentProcessId | Should -Be 0
            $system.ParentProcess | Should -BeNullOrEmpty
        }

        It 'Leaves ParentProcess empty when the parent PID is 0 or the process itself' {
            # As on a real system: Idle (0) reports itself as parent, System (4) reports 0.
            Mock Get-CimInstance -ModuleName GetNetTcpProcess -ParameterFilter { $ClassName -eq 'Win32_Process' } {
                Get-FakeProcess -ProcessId 0 -Name 'System Idle Process' -ParentProcessId 0
                Get-FakeProcess -ProcessId 4 -Name 'System' -ParentProcessId 0
                Get-FakeProcess -ProcessId 1000 -Name 'node.exe' -ParentProcessId 1000
            }
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess {
                Get-FakeConnection -LocalAddress '10.0.0.4' -LocalPort 43420 -State 'TimeWait' -OwningProcess 0
                $script:listenConnection
                $script:webConnection
            }

            $result = @(Get-NetTcpProcess -Parent)

            $result.Count | Should -Be 3
            foreach ($row in $result)
            {
                $row.ParentProcess | Should -BeNullOrEmpty -Because "PID $($row.ProcessId) has no real parent"
            }
            ($result | Where-Object ProcessId -EQ 0).ParentProcessId | Should -Be 0
            ($result | Where-Object ProcessId -EQ 4).ParentProcessId | Should -Be 0
            ($result | Where-Object ProcessId -EQ 1000).ParentProcessId | Should -Be 1000
        }

        It 'Ignores a parent PID that was reused by a newer process' {
            Mock Get-CimInstance -ModuleName GetNetTcpProcess -ParameterFilter { $ClassName -eq 'Win32_Process' } {
                Get-FakeProcess -ProcessId 900 -Name 'impostor.exe' -ParentProcessId 1 -CreationDate ([datetime]'2026-06-01')
                Get-FakeProcess -ProcessId 1000 -Name 'node.exe' -ParentProcessId 900 -CreationDate ([datetime]'2026-01-01')
            }

            $web = Get-NetTcpProcess -Parent | Where-Object Port -EQ 8080

            $web.ParentProcessId | Should -Be 900
            $web.ParentProcess | Should -BeNullOrEmpty
        }
    }

    Context '-CommandLine' {
        It 'Adds the process command line' {
            $web = Get-NetTcpProcess -CommandLine | Where-Object Port -EQ 8080

            $web.ProcessCommandLine | Should -Be '"node.exe" server.js'
        }

        It 'Works together with -Parent' {
            $chrome = Get-NetTcpProcess -CommandLine -Parent | Where-Object Port -EQ 50000

            $chrome.ProcessCommandLine | Should -Be '"chrome.exe" --flag'
            $chrome.ParentProcess | Should -Be 'explorer'
        }
    }

    Context 'State with no enum name' {
        BeforeEach {
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess {
                $script:unnamedStateConnection
                $script:webConnection
            }
        }

        It 'Shows the raw numeric state instead of a blank' {
            $unnamed = Get-NetTcpProcess | Where-Object Port -EQ 60000

            $unnamed.State | Should -BeExactly '0'
            $unnamed.ProcessName | Should -Be 'node'
        }

        It 'Leaves named states and -State results unchanged' {
            (Get-NetTcpProcess | Where-Object Port -EQ 8080).State | Should -BeExactly 'Listen'

            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess -ParameterFilter { $State -contains 'Listen' } { $script:webConnection }
            $result = @(Get-NetTcpProcess -State Listen)

            $result.Count | Should -Be 1
            $result[0].State | Should -BeExactly 'Listen'
            Should -Invoke Get-NetTCPConnection -ModuleName GetNetTcpProcess -Times 1 -Exactly -ParameterFilter { $State -contains 'Listen' }
        }
    }

    Context 'PID with no matching process' {
        BeforeEach {
            Mock Get-NetTCPConnection -ModuleName GetNetTcpProcess { $script:orphanConnection }
        }

        It 'Still returns the connection, with empty process details' {
            $orphan = Get-NetTcpProcess -CommandLine -Parent

            $orphan.Port | Should -Be 9999
            $orphan.ProcessId | Should -Be 4242
            $orphan.ProcessName | Should -BeNullOrEmpty
            $orphan.Path | Should -BeNullOrEmpty
            $orphan.ProcessCommandLine | Should -BeNullOrEmpty
            $orphan.ParentProcess | Should -BeNullOrEmpty
        }
    }
}

Describe 'Help and release metadata' {
    BeforeAll {
        $script:help = Get-Help -Name Get-NetTcpProcess -Full
        $script:manifest = Test-ModuleManifest -Path $manifestPath
    }

    It 'Has a synopsis and description' {
        $script:help.Synopsis | Should -Not -BeNullOrEmpty
        ($script:help.Description.Text -join ' ') | Should -Not -BeNullOrEmpty
    }

    It 'Describes parameter <_>' -ForEach @('State', 'Parent', 'CommandLine') {
        $parameterHelp = $script:help.Parameters.Parameter | Where-Object -Property Name -EQ $_
        ($parameterHelp.Description.Text -join ' ') | Should -Not -BeNullOrEmpty
    }

    It 'Has at least six examples, each with code and an explanation' {
        @($script:help.Examples.Example).Count | Should -BeGreaterOrEqual 6
        foreach ($example in $script:help.Examples.Example)
        {
            $example.Code | Should -Match 'Get-NetTcpProcess'
            ($example.Remarks.Text -join ' ').Trim() | Should -Not -BeNullOrEmpty
        }
    }

    It 'Links to the online command reference' {
        $script:help.RelatedLinks.NavigationLink[0].Uri | Should -Be 'https://github.com/joeb1kenobe/GetNetTcpProcess/blob/main/docs/Get-NetTcpProcess.md'
    }

    It 'Has gallery metadata in the manifest' {
        $script:manifest.Description | Should -Not -BeNullOrEmpty
        $script:manifest.ReleaseNotes | Should -Not -BeNullOrEmpty
        $script:manifest.ProjectUri | Should -Be 'https://github.com/joeb1kenobe/GetNetTcpProcess'
        # Pinned to the version's tag, so each gallery version links to its own license.
        $script:manifest.LicenseUri | Should -Be "https://github.com/joeb1kenobe/GetNetTcpProcess/blob/v$($script:manifest.Version)/LICENSE"
    }

    It 'Has a CHANGELOG entry for the manifest version as its newest release' {
        $changelog = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'CHANGELOG.md')
        $newest = $changelog | Where-Object -FilterScript { $_ -match '^## \[(\d+\.\d+\.\d+)\]' } | Select-Object -First 1
        $newest | Should -Match ('^## \[' + [regex]::Escape($script:manifest.Version.ToString()) + '\]')
        $script:manifest.ReleaseNotes | Should -Match ([regex]::Escape($script:manifest.Version.ToString()))
    }
}

AfterAll {
    Remove-Module -Name GetNetTcpProcess -ErrorAction SilentlyContinue
}
