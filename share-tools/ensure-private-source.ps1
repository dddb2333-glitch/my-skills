param(
    [switch]$Apply,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\common.ps1"

Assert-Configuration
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'GitHub CLI (gh) is not installed or not in PATH.'
    Write-Host 'Check repository visibility manually in GitHub Settings -> General -> Danger Zone -> Repository visibility.'
    Write-Host "Expected repository: $PrivateRepoSlug"
    exit 2
}

$probe = Invoke-NativeCapture -FilePath 'gh' -ArgumentList @('repo','view',$PrivateRepoSlug,'--json','visibility','--jq','.visibility')
if ($probe.ExitCode -ne 0 -or $probe.Output.Count -eq 0) { throw 'Could not query repository visibility. Check gh authentication.' }
$visibility = (($probe.Output -join "`n").Trim())
Write-Host "Current visibility: $visibility"

if ($visibility -eq 'PRIVATE') {
    Write-Host '[PASS] Canonical source repository is PRIVATE.'
    exit 0
}

if (-not $Apply) {
    Write-Warning 'Repository is not PRIVATE. No change was made.'
    Write-Host 'To apply explicitly:'
    Write-Host '  .\ensure-private-source.ps1 -Apply'
    exit 1
}

Confirm-ExplicitAction -ActionText "change $PrivateRepoSlug visibility from $visibility to PRIVATE" -Token 'MAKE_PRIVATE' -Yes:$Yes
$oldPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & gh repo edit $PrivateRepoSlug --visibility private --accept-visibility-change-consequences
    $editExit = $LASTEXITCODE
}
finally { $ErrorActionPreference = $oldPreference }
if ($editExit -ne 0) { throw 'Failed to set private visibility.' }

$afterProbe = Invoke-NativeCapture -FilePath 'gh' -ArgumentList @('repo','view',$PrivateRepoSlug,'--json','visibility','--jq','.visibility')
$after = if ($afterProbe.Output.Count -gt 0) { (($afterProbe.Output -join "`n").Trim()) } else { $null }
if ($afterProbe.ExitCode -ne 0 -or $after -ne 'PRIVATE') { throw "Visibility post-check failed; current value: $after" }
Write-Host '[DONE] Repository visibility changed to PRIVATE and verified.'
