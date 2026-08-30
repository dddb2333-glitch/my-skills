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
$runRoot = Join-Path $WorkRoot 'share-publish'
Reset-Directory -Path $runRoot
$source = Join-Path $runRoot 'private-src'
$snapshot = Join-Path $runRoot 'public-snapshot'
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
$publishSucceeded = $false

try {
    Write-Host '[1/10] Verify PRIVATE visibility when available and clone canonical main...'
    Test-PrivateRepoVisibilityIfGhAvailable
    Clone-PrivateCanonical -Destination $source
    $head = Get-GitHead -RepoRoot $source

    Write-Host '[2/10] Verify canonical identity/compatibility...'
    $meta = Assert-CanonicalLayout -CanonicalRoot $source
    Write-Host "  PRIVATE HEAD: $head"
    Write-Host "  Layout: $($meta.layout)"
    Write-Host "  Identity: $($meta.identity_source) / $($meta.identity_confidence)"

    Write-Host '[3/10] Build Framework allowlist snapshot with safe copy...'
    $copied = @(Copy-FrameworkAllowlist -SourceRoot $source -DestinationRoot $snapshot -AllowList $AllowListPath -DenyList $DenyListPath)

    Write-Host '[4/10] Add public README + complete share-tools + provenance...'
    Write-PublicReadme -DestinationRoot $snapshot -SourceHead $head -SourceLayout ([string]$meta.layout) -SourceMode 'private-remote-commit' -SourceDirty $false
    Copy-PublicShareTools -DestinationRoot $snapshot -FileList $PublicToolFiles
    Write-PublicExportManifest -DestinationRoot $snapshot -SourceHead $head -CanonicalMeta $meta -CopiedRules $copied -SourceMode 'private-remote-commit' -SourceDirty $false
    Write-PublicGitAttributes -DestinationRoot $snapshot

    Write-Host '[5/10] Run deny-path, shape/size, secret checks and hashes...'
    Test-FinalDeniedPaths -Root $snapshot -DenyList $DenyListPath
    Test-PublicSnapshotShape -Root $snapshot
    Test-PublicSnapshotSecrets -Root $snapshot
    Write-Sha256Manifest -Root $snapshot
    Test-PublicSnapshotShape -Root $snapshot
    Test-PublicSnapshotSecrets -Root $snapshot

    Write-Host '[6/10] Capture current PUBLIC main HEAD...'
    $expectedHead = Get-RemoteHead -RepoUrl $PublicRepoUrl -Branch $PublicBranch
    if ($expectedHead) { Write-Host "  PUBLIC expected HEAD: $expectedHead" }
    else { Write-Host '  PUBLIC main does not currently exist.' }

    Write-Host '[7/10] Build fresh one-commit PUBLIC snapshot...'
    Initialize-FreshGitSnapshot -SnapshotRoot $snapshot -CommitMessage "Publish Skill Supply Chain public Framework from $head"
    $publicCommit = Get-GitHead -RepoRoot $snapshot
    Write-Host "  PUBLIC candidate commit: $publicCommit"
    Write-Host "  Files: $(Get-TreeFileCount -Root $snapshot)"
    Write-Host "  Framework paths: $($copied -join ', ')"

    Write-Host '[8/10] Confirm and push with remote-head lease...'
    Confirm-Publish -ActionText "replace PUBLIC/$PublicBranch with Framework export from PRIVATE $head" -Yes:$Yes
    Push-FreshSnapshotWithLease -SnapshotRoot $snapshot -ExpectedRemoteHead $expectedHead

    Write-Host '[9/10] Verify remote commit after push...'
    Assert-RemoteHeadEquals -RepoUrl $PublicRepoUrl -Branch $PublicBranch -ExpectedHead $publicCommit
    $publishSucceeded = $true

    Write-Host '[10/10] DONE'
    Write-Host "PUBLIC: $PublicRepoUrl"
    Write-Host "PUBLIC HEAD verified: $publicCommit"
    Write-Warning 'Fresh-snapshot publishing rewrites current PUBLIC branch history. It cannot erase prior clones, forks, caches, downloads, or service retention.'
}
finally {
    if ($publishSucceeded -and -not $KeepWork) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    elseif (-not $publishSucceeded) {
        Write-Warning "Publish did not complete. Diagnostic work tree kept: $runRoot"
    }
}
