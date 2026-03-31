Write-Host ''
Write-Host '  SPFx Parallel Deployment' -ForegroundColor White
Write-Host ("  " + [string]([char]0x2500) * 50) -ForegroundColor DarkGray
Write-Host '  Select target environment:' -ForegroundColor Cyan
Write-Host ''
Write-Host '    [D] / [1]  Development  (DEV)'  -ForegroundColor Yellow
Write-Host '    [U] / [2]  Acceptance   (UAT)'  -ForegroundColor Cyan
Write-Host '    [P] / [3]  Production   (PROD)' -ForegroundColor Green
Write-Host ''

$choice      = (Read-Host '  Enter choice  D/U/P  or  1/2/3').Trim().ToUpper()
$projectRoot = Split-Path $PSScriptRoot -Parent   # modules\\ -> project root
$envFile = switch ($choice) {
    { $_ -in @('D','1') } { Join-Path $projectRoot 'environments\DEV.ps1'  }
    { $_ -in @('U','2') } { Join-Path $projectRoot 'environments\UAT.ps1'  }
    { $_ -in @('P','3') } { Join-Path $projectRoot 'environments\PROD.ps1' }
    default               { $null }
}

if (-not $envFile -or -not (Test-Path $envFile)) {
    Write-Host "  $iWarn  Invalid selection '$choice'. Exiting." -ForegroundColor Yellow
    exit 1
}

# Provides: $environmentName, $packagePath, $siteCollections
. $envFile


#region -- Site Selection ---------------------------------------------------

$allSites = $siteCollections

Write-Host ''
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host '  Sites available for deployment:' -ForegroundColor Cyan
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ''
for ($i = 0; $i -lt $allSites.Count; $i++) {
    Write-Host ("  [{0,2}]  {1}" -f ($i + 1), $allSites[$i]) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host '  [A]          Deploy ALL sites listed above' -ForegroundColor White
Write-Host '  [1,3,5 ...]  Site numbers, comma or space separated' -ForegroundColor White
Write-Host '  [URL]        Enter a custom SharePoint site URL' -ForegroundColor White
Write-Host ''

$siteInput = (Read-Host '  Selection (default = A)').Trim()

if ($siteInput -eq '' -or $siteInput.ToUpper() -eq 'A') {
    Write-Host "  All $($allSites.Count) sites selected." -ForegroundColor Green

} elseif ($siteInput -match '^https?://') {
    $customUrl = $siteInput.TrimEnd('/')
    $siteCollections = @($customUrl)
    Write-Host "  Custom URL selected: $customUrl" -ForegroundColor Cyan

} else {
    $nums     = $siteInput -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $selected = @()
    foreach ($n in $nums) {
        if ($n -ge 1 -and $n -le $allSites.Count) {
            $selected += $allSites[$n - 1]
        } else {
            Write-Host "  !! Site number $n is out of range (1-$($allSites.Count)) -- skipped." -ForegroundColor Yellow
        }
    }
    if ($selected.Count -eq 0) {
        Write-Host '  !! No valid sites selected. Exiting.' -ForegroundColor Red
        exit 1
    }
    $siteCollections = $selected
    Write-Host "  $($siteCollections.Count) site(s) selected." -ForegroundColor Green
}
Write-Host ''

#endregion

