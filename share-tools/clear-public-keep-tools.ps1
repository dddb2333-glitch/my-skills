param(
    [switch]$Yes,
    [switch]$KeepWork
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\common.ps1"

Assert-GitAvailable
Assert-GitIdentity
Assert-Configuration
$runRoot = Join-Path $WorkRoot 'share-clear-public'
Reset-Directory -Path $runRoot
$snapshot = Join-Path $runRoot 'public-clear-snapshot'
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
$publishSucceeded = $false

try {
    Write-Host '[1/7] Capture current PUBLIC main HEAD...'
    $expectedHead = Get-RemoteHead -RepoUrl $PublicRepoUrl -Branch $PublicBranch
    if ($expectedHead) { Write-Host "  PUBLIC expected HEAD: $expectedHead" }
    else { Write-Host '  PUBLIC main does not currently exist.' }

    Write-Host '[2/7] Build cleared snapshot: README + complete share-tools + integrity metadata...'
    $readme = @'
# my-skills

The public Framework snapshot is currently cleared.

`share-tools/` is retained so a reviewed Framework subset can be published again from the private canonical repository.

`PUBLIC_EXPORT_SHA256.txt` is an integrity manifest for this cleared snapshot.
'@
    Write-Utf8NoBomText -Path (Join-Path $snapshot 'README.md') -Text $readme
    Copy-PublicShareTools -DestinationRoot $snapshot -FileList $PublicToolFiles
    Write-PublicGitAttributes -DestinationRoot $snapshot

    Write-Host '[3/7] Deny-path, shape/size, secret checks and hashes...'
    Test-FinalDeniedPaths -Root $snapshot -DenyList $DenyListPath
    Test-PublicSnapshotShape -Root $snapshot
    Test-PublicSnapshotSecrets -Root $snapshot
    Write-Sha256Manifest -Root $snapshot
    Test-PublicSnapshotShape -Root $snapshot
    Test-PublicSnapshotSecrets -Root $snapshot

    Write-Host '[4/7] Build fresh Git snapshot...'
    Initialize-FreshGitSnapshot -SnapshotRoot $snapshot -CommitMessage 'Clear public Framework snapshot; retain reviewed share-tools'
    $publicCommit = Get-GitHead -RepoRoot $snapshot

    Write-Host '[5/7] Confirm and push with lease...'
    Confirm-Publish -ActionText "clear PUBLIC/$PublicBranch Framework payload while retaining README + share-tools + integrity manifest" -Yes:$Yes
    Push-FreshSnapshotWithLease -SnapshotRoot $snapshot -ExpectedRemoteHead $expectedHead

    Write-Host '[6/7] Verify remote commit after push...'
    Assert-RemoteHeadEquals -RepoUrl $PublicRepoUrl -Branch $PublicBranch -ExpectedHead $publicCommit
    $publishSucceeded = $true

    Write-Host '[7/7] DONE'
    Write-Host "PUBLIC HEAD verified: $publicCommit"
    Write-Warning 'This changes only the current branch. It cannot erase copies already cloned, forked, cached, downloaded, or retained elsewhere.'
}
finally {
    if ($publishSucceeded -and -not $KeepWork) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    elseif (-not $publishSucceeded) {
        Write-Warning "Clear did not complete. Diagnostic work tree kept: $runRoot"
    }
}
