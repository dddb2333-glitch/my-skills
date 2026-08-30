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
$checkRoot = Join-Path $WorkRoot 'share-check-private'
$cleanupRemote = $false

try {
    if ($UseLocalCanonical) {
        $source = $LocalCanonicalRoot
        Write-Host "[1/4] Use LOCAL canonical: $source"
        if (Test-GitWorkingTree -Path $source) {
            $head = Get-GitHead -RepoRoot $source
            $dirty = @(Get-GitStatusPorcelain -RepoRoot $source)
            if ($dirty.Count -gt 0) { Write-Warning 'Local canonical has uncommitted/untracked changes. Remote publish will NOT include them.' }
        }
        else {
            $head = $null
            Write-Warning 'Local canonical is not a Git working tree. Structural validation will continue, but no Git HEAD/dirty-state provenance can be proven. Remote publish still uses PRIVATE/main only.'
        }
    }
    else {
        Test-PrivateRepoVisibilityIfGhAvailable
        Reset-Directory -Path $checkRoot
        $cleanupRemote = $true
        $source = Join-Path $checkRoot 'private-src'
        Write-Host '[1/4] Clone PRIVATE canonical main...'
        Clone-PrivateCanonical -Destination $source
        $head = Get-GitHead -RepoRoot $source
    }

    Write-Host '[2/4] Verify canonical identity/compatibility...'
    $meta = Assert-CanonicalLayout -CanonicalRoot $source
    Write-Host "  layout: $($meta.layout)"
    Write-Host "  schema_version: $($meta.schema_version)"
    Write-Host "  canonical_role: $($meta.canonical_role)"
    Write-Host "  identity_source: $($meta.identity_source)"
    Write-Host "  identity_confidence: $($meta.identity_confidence)"
    if ($head) { Write-Host "  HEAD: $head" } else { Write-Host "  HEAD: (none; local non-git tree)" }

    Write-Host '[3/4] Verify Framework allowlist...'
    $rules = @(Read-ExportRules -Path $AllowListPath)
    $deny = @(Read-DenyRules -Path $DenyListPath)
    foreach ($rule in $rules) {
        if (Test-IsDeniedRelativePath -RelativePath $rule.Path -DenyRules $deny) { throw "Allowlist conflicts with deny-list: $($rule.Path)" }
        $p = Join-Path $source $rule.Path
        if (Test-Path -LiteralPath $p) { Write-Host "  [OK] $($rule.Kind):$($rule.Path)" }
        elseif ($rule.Kind -eq 'required') { throw "[BLOCK] Missing REQUIRED Framework path: $($rule.Path)" }
        else { Write-Warning "Optional Framework path missing: $($rule.Path)" }
    }

    Write-Host '[4/4] Top-level canonical items:'
    Get-ChildItem -LiteralPath $source -Force | Select-Object Name,Mode | Format-Table -AutoSize
    Write-Host '[PASS] Canonical source is compatible with share-tools v2.3.'
}
finally {
    if ($cleanupRemote) { Remove-Item -LiteralPath $checkRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
