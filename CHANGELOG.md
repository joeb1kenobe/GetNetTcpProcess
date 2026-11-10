# Changelog

All notable changes to GetNetTcpProcess are listed here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module uses [semantic versioning](https://semver.org/).

## [1.0.1] - Unreleased

Documentation only. `Get-NetTcpProcess` behaves exactly as in 1.0.0.

### Added
- A full README covering installation, requirements, parameters, output properties, eight examples and known behavior.
- A command reference, [docs/Get-NetTcpProcess.md](docs/Get-NetTcpProcess.md), generated from the help with platyPS.
- This changelog.

### Changed
- The comment-based help is complete:
  - descriptions of every parameter and output property;
  - eight examples, matching the README;
  - `.INPUTS`, plus notes on elevation, states with no name, Docker Desktop and `Format-Table`;
  - links. `Get-Help Get-NetTcpProcess -Online` now opens the command reference.
- The module manifest has a clearer description and release notes.

## [1.0.0] - 2026-11-10

First release as a module on the PowerShell Gallery.

### Added
- Packaged as a module (`GetNetTcpProcess.psm1` and `GetNetTcpProcess.psd1`) for Windows PowerShell 5.1 and PowerShell 7+, exporting only `Get-NetTcpProcess`. Dot-sourcing `GetNetTcpProcess.ps1` still works and now imports the module.
- New output properties: `ProcessId`, `RemoteAddress` and `RemotePort`, plus `ParentProcessId` with `-Parent`.
- `-State` accepts all 13 TCP states, and several at once.
- Pester tests, with `Get-NetTCPConnection` and `Get-CimInstance` mocked.

### Fixed
- `-State` returned empty `ProcessName` and `Path` values.
- `-Parent` and `-CommandLine` returned nothing in Windows PowerShell 5.1. Process information now comes from `Win32_Process`.
- `ParentProcess` showed `System.Diagnostics.Process (name)`. It now shows the parent's name.
- Wrong parents were reported:
  - for PID 0 and PID 4, which showed "System Idle Process";
  - for processes whose parent's PID had been reused by a newer process.
- `-State` with no matching connections wrote an error, which also leaked into the caller's `-ErrorVariable`. It now returns nothing, and other errors still reach the caller.
- `-State` missed listeners on machines with many sockets (for example with Docker Desktop). The state is now passed to `Get-NetTCPConnection` rather than filtered afterward.
- States with no name (raw value `0`) showed as blank. They now show the number.
- Much faster on busy machines: about 96 s down to 11 s with ~4,900 connections.
- The README's install instruction (`Import-Module -Path`) didn't work.

### Changed
- `ParentProcess` is now a string with the parent's name.
- The process with PID 0 is named `System Idle Process` (as `Win32_Process` reports it) instead of `Idle`.

[1.0.1]: https://github.com/joeb1kenobe/GetNetTcpProcess/compare/490ff9f...main
[1.0.0]: https://www.powershellgallery.com/packages/GetNetTcpProcess/1.0.0
