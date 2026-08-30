# Compatibility wrapper. Supported path: PRIVATE canonical -> explicit Framework allowlist -> PUBLIC.
param(
    [switch]$Yes,
    [switch]$KeepWork
)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\publish-private-to-public.ps1" @PSBoundParameters
