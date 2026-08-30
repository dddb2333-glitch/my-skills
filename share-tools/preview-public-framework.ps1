param([switch]$UseLocalCanonical)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\common.ps1"

if ($UseLocalCanonical) {
    if (Get-Command git -ErrorAction SilentlyContinue) { Assert-GitAvailable }
    else { Write-Warning 'Git is unavailable; continuing local structural validation/preview without Git provenance.' }
}
else { Assert-GitAvailable }
Assert-Configuration
$runRoot = Join-Path $PreviewRoot 'framework-preview'
Reset-Directory -Path $runRoot
$snapshot = Join-Path $runRoot 'public-preview'
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null

if ($UseLocalCanonical) {
    $source = $LocalCanonicalRoot
    Write-Host "[1/8] Use LOCAL canonical preview: $source"
    if (Test-GitWorkingTree -Path $source) {
        $sourceMode = 'local-git-working-tree-preview'
        $head = Get-GitHead -RepoRoot $source
        $dirtyLines = @(Get-GitStatusPorcelain -RepoRoot $source)
        $sourceDirty = ($dirtyLines.Count -gt 0)
        if ($sourceDirty) { Write-Warning 'LOCAL preview includes working-tree changes that may not exist in PRIVATE remote.' }
    }
    else {
        $sourceMode = 'local-non-git-preview'
        $head = $null
        $sourceDirty = $null
        Write-Warning 'LOCAL preview source is not a Git working tree. Preview is allowed for structural/export inspection only; source commit and dirty state are unknown, and formal publish still uses PRIVATE/main.'
    }
}
else {
    Test-PrivateRepoVisibilityIfGhAvailable
    $source = Join-Path $runRoot 'private-src'
    $sourceMode = 'private-remote-commit'
    $sourceDirty = $false
    Write-Host '[1/8] Clone PRIVATE latest canonical...'
    Clone-PrivateCanonical -Destination $source
    $head = Get-GitHead -RepoRoot $source
}

Write-Host '[2/8] Verify canonical identity/compatibility...'
$meta = Assert-CanonicalLayout -CanonicalRoot $source

Write-Host '[3/8] Build Framework allowlist snapshot with reparse-point-safe copy...'
$copied = @(Copy-FrameworkAllowlist -SourceRoot $source -DestinationRoot $snapshot -AllowList $AllowListPath -DenyList $DenyListPath)

Write-Host '[4/8] Add public README + complete share-tools + provenance...'
Write-PublicReadme -DestinationRoot $snapshot -SourceHead $head -SourceLayout ([string]$meta.layout) -SourceMode $sourceMode -SourceDirty $sourceDirty
Copy-PublicShareTools -DestinationRoot $snapshot -FileList $PublicToolFiles
Write-PublicExportManifest -DestinationRoot $snapshot -SourceHead $head -CanonicalMeta $meta -CopiedRules $copied -SourceMode $sourceMode -SourceDirty $sourceDirty
Write-PublicGitAttributes -DestinationRoot $snapshot

Write-Host '[5/8] Run deny-path, shape/size, and secret checks...'
Test-FinalDeniedPaths -Root $snapshot -DenyList $DenyListPath
Test-PublicSnapshotShape -Root $snapshot
Test-PublicSnapshotSecrets -Root $snapshot

Write-Host '[6/8] Generate SHA256 manifest...'
Write-Sha256Manifest -Root $snapshot
Test-PublicSnapshotShape -Root $snapshot
Test-PublicSnapshotSecrets -Root $snapshot

Write-Host '[7/8] Summarize preview...'
if ($head) { Write-Host "  Source HEAD: $head" } else { Write-Host "  Source HEAD: (none; local non-git tree)" }
Write-Host "  Source mode: $sourceMode"
if ($null -eq $sourceDirty) { Write-Host "  Source dirty: unknown (non-git local preview)" } else { Write-Host "  Source dirty: $sourceDirty" }
Write-Host "  Layout: $($meta.layout)"
Write-Host "  Identity: $($meta.identity_source) / $($meta.identity_confidence)"
Write-Host "  Files: $(Get-TreeFileCount -Root $snapshot)"
Write-Host "  Preview: $snapshot"
Write-Host "  Framework paths: $($copied -join ', ')"

Write-Host '[8/8] PREVIEW READY -- no GitHub push was performed.'
Write-Host ''
Get-ChildItem -LiteralPath $snapshot -Recurse -Force -File | ForEach-Object {
    $_.FullName.Substring($snapshot.Length).TrimStart([char[]]'\/')
}
