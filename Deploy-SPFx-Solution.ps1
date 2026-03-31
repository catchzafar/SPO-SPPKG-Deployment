param()


Clear-Host

. (Join-Path $PSScriptRoot 'modules\\Icons.ps1')

#region -- PS Version Guard --------------------------------------------------

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "$iWarn  This script requires Windows PowerShell 5.x." -ForegroundColor Yellow
    Write-Host "    Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "    Run this script from Windows PowerShell 5.1 (not PowerShell 7+)." -ForegroundColor Cyan
    exit 1
}

#endregion

#region -- PnP Module Guard --------------------------------------------------

if (-not (Get-Module -ListAvailable -Name SharePointPnPPowerShellOnline)) {
    Write-Host "$iWarn  The module 'SharePointPnPPowerShellOnline' is not installed." -ForegroundColor Yellow
    Write-Host "$iInfo  Install it by running in Windows PowerShell 5.1:" -ForegroundColor Cyan
    Write-Host "      Install-Module SharePointPnPPowerShellOnline -Scope CurrentUser -Force" -ForegroundColor White
    Write-Host "    Then re-run this script." -ForegroundColor White
    exit 1
}

#endregion


#region -- Package Path Selection -------------------------------------------

# Set the default path to your .sppkg file here.
# The script will prompt you to confirm or change it at runtime.
$packagePath = 'C:\Path\To\Your\Solution\your-solution.sppkg'

. (Join-Path $PSScriptRoot 'modules\\SolutionPath.ps1')

#endregion


#region -- Environment Selection --------------------------------------------

. (Join-Path $PSScriptRoot 'modules\\SetEnvironment.ps1')

#endregion


#region -- Parallel Jobs -------------------------------------------------

Write-Host ''
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host '  Parallel Deployments' -ForegroundColor Cyan
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Number of sites to deploy simultaneously (1 = sequential, 5 = fastest).' -ForegroundColor DarkGray
Write-Host ''

do {
    $parallelInput = (Read-Host '  Parallel deployment [1-5]  (default = 3)').Trim()
    if ($parallelInput -eq '') { $parallelInput = '3' }
    $MaxParallel = 0
    [int]::TryParse($parallelInput, [ref]$MaxParallel) | Out-Null
    if ($MaxParallel -lt 1 -or $MaxParallel -gt 5) {
        Write-Host "  $iWarn  Enter a number between 1 and 5." -ForegroundColor Yellow
    }
} while ($MaxParallel -lt 1 -or $MaxParallel -gt 5)

Write-Host ''
Write-Host ("  Parallel jobs : $MaxParallel") -ForegroundColor Green
Write-Host ''

#endregion

#region -- Logging Setup -----------------------------------------------------

$runId   = [System.Guid]::NewGuid().ToString()
$logDir  = Join-Path $PSScriptRoot 'deploy-logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("Deploy_{0}_[{1}]_{2}.log" -f $packageName, $environmentName, (Get-Date -Format 'yyyyMMdd_HHmmss'))

# Stable per-site GUID for cross-run log correlation
$siteGuids = @{}
foreach ($s in $siteCollections) { $siteGuids[$s] = [System.Guid]::NewGuid().ToString() }

#endregion

#region -- Site Index --------------------------------------------------------

# Maps URL -> 0-based index.  Used by Update-SiteLine to find the correct row.
$siteIndex = @{}
for ($i = 0; $i -lt $siteCollections.Count; $i++) { $siteIndex[$siteCollections[$i]] = $i }

#endregion

#region -- Load Libraries ----------------------------------------------------

# Display.ps1  : console detection, icon maps, Write-Log, Update-SiteLine, Invoke-DrainJob
# ScriptBlock.ps1 : $scriptBlock (the per-site job worker)
. (Join-Path $PSScriptRoot 'modules\\Display.ps1')
. (Join-Path $PSScriptRoot 'modules\\ScriptBlock.ps1')

#endregion
Clear-Host


#region -- Print Header ------------------------------------------------------

$envColor = switch ($environmentName) {
    'DEV'  { 'Yellow' }
    'UAT'  { 'Cyan'   }
    'PROD' { 'Green'  }
    default { 'White' }
}

Write-Host ''
Write-Host ("  SPFx Parallel Deployment  [$environmentName]") -ForegroundColor $envColor
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ("  Total sites : {0,-4}  Parallel deployment : {1}" -f $siteCollections.Count, $MaxParallel) -ForegroundColor Cyan
Write-Host '  Ctrl+C  ->  cancel gracefully  (active deployments finish, queued deployments are skipped)' -ForegroundColor DarkGray
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ''

$siteStartRow = if ($dashboardMode) { [Console]::CursorTop } else { 0 }

#endregion

#region -- Pre-render Sites as Queued ----------------------------------------

foreach ($site in $siteCollections) {
    $n = ($siteIndex[$site] + 1).ToString().PadLeft(2)
    Write-Host "  [$n]  $($phaseIcon['Queued']) ---  Queued          $site" -ForegroundColor DarkGray
}
Write-Host ''
$bottomRow = if ($dashboardMode) { [Console]::CursorTop } else { 0 }

#endregion

#region -- Initial Log Entries -----------------------------------------------

Write-Log -level 'START' -message (
    "Deployment started  Env={0}  Sites={1}  Parallel={2}  Package={3}" -f
    $environmentName, $siteCollections.Count, $MaxParallel, $packagePath
)

Write-Log -level 'INPUT' -message "Environment selected  Input='$choice'  Resolved=$environmentName"
$pkgSource = if ($pkgInput) { 'user-provided' } else { 'default' }
Write-Log -level 'INPUT' -message "Package path ($pkgSource)  Path=$packagePath"
$siteSelDisplay = if ($siteInput -eq '' -or $siteInput.ToUpper() -eq 'A') { 'ALL' } else { "'$siteInput'" }
Write-Log -level 'INPUT' -message "Site selection  Input=$siteSelDisplay  Resolved=$($siteCollections.Count) site(s)"
foreach ($s in $siteCollections) { Write-Log -level 'INPUT' -message "  Selected site: $s" }
Write-Log -level 'INPUT' -message "Parallel deployments  Input='$parallelInput'  Resolved=$MaxParallel"

foreach ($s in $siteCollections) { Write-Log -siteUrl $s -level 'QUEUED' -message $s }

#endregion

#region -- Parallel Runner ---------------------------------------------------

$queue         = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($s in $siteCollections) { $queue.Enqueue($s) }
$activeJobs    = @{}
$deployResults = @{}
$cancelled     = $false

$interactiveConsole = $false
try { [Console]::TreatControlCAsInput = $true; $interactiveConsole = $true } catch { }

function Start-NextJob {
    if ($script:queue.Count -eq 0) { return }
    Start-Sleep -Seconds 3
    $siteUrl = $script:queue.Dequeue()
    $job = Start-Job -ScriptBlock $script:scriptBlock -ArgumentList $siteUrl, $script:packagePath
    $script:activeJobs[$job.Id] = @{ Job = $job; Site = $siteUrl }
    Update-SiteLine -siteUrl $siteUrl -phase 'Connecting' -step 1 -total 5 -color Yellow
}

try {
    while ($queue.Count -gt 0 -and $activeJobs.Count -lt $MaxParallel) { Start-NextJob }

    while ($activeJobs.Count -gt 0) {

        if ($interactiveConsole -and [Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                $cancelled = $true
                foreach ($s in $queue) { Update-SiteLine -siteUrl $s -phase 'Cancelled' -color DarkYellow }
                $queue.Clear()
                Write-Log -level 'CANCEL' -message "Cancellation requested by user (Ctrl+C)  Active=$($script:activeJobs.Count)"
                if ($dashboardMode) { [Console]::SetCursorPosition(0, $bottomRow) }
                Write-Host ''
                Write-Host "  $iWarn Cancellation requested -- waiting for $($activeJobs.Count) active job(s) to finish..." -ForegroundColor Yellow
                if ($dashboardMode) { $bottomRow = [Console]::CursorTop }
            }
        }

        $completedIds = @()
        foreach ($id in @($activeJobs.Keys)) {
            $info = $activeJobs[$id]
            Invoke-DrainJob -site $info.Site -job $info.Job
            if ($info.Job.State -notin @('Running', 'NotStarted')) { $completedIds += $id }
        }

        foreach ($id in $completedIds) {
            $info = $activeJobs[$id]
            Invoke-DrainJob -site $info.Site -job $info.Job
            Remove-Job -Job $info.Job -Force
            $activeJobs.Remove($id)
            if (-not $cancelled -and $queue.Count -gt 0) { Start-NextJob }
        }

        if ($activeJobs.Count -gt 0) { Start-Sleep -Milliseconds 300 }
    }
}
finally {
    if ($interactiveConsole) { try { [Console]::TreatControlCAsInput = $false } catch { } }

    if ($activeJobs.Count -gt 0) {
        if ($dashboardMode) { [Console]::SetCursorPosition(0, $bottomRow) }
        Write-Host "  $iWarn Cleaning up $($activeJobs.Count) remaining deployment(s)..." -ForegroundColor DarkYellow
        foreach ($id in @($activeJobs.Keys)) {
            $info = $activeJobs[$id]
            Invoke-DrainJob -site $info.Site -job $info.Job
            Stop-Job   -Job $info.Job -ErrorAction SilentlyContinue
            Remove-Job -Job $info.Job -Force -ErrorAction SilentlyContinue
        }
        if ($dashboardMode) { $bottomRow = [Console]::CursorTop }
    }
}

#endregion

#region -- Mark Sites Cancelled ----------------------------------------------

if ($cancelled) {
    foreach ($s in $siteCollections) {
        if (-not $deployResults.ContainsKey($s) -and
            -not ($activeJobs.Values | Where-Object { $_.Site -eq $s })) {
            Update-SiteLine -siteUrl $s -phase 'Cancelled' -color DarkYellow
            Write-Log -siteUrl $s -level 'CANCEL' -message "Cancelled (never started)  $s"
        }
    }
}

#endregion

#region -- Summary -----------------------------------------------------------

if ($dashboardMode) { [Console]::SetCursorPosition(0, $bottomRow) }

$successful = @($siteCollections | Where-Object { $deployResults.ContainsKey($_) -and $deployResults[$_].Status -eq 'Success' })
$failed     = @($siteCollections | Where-Object { $deployResults.ContainsKey($_) -and $deployResults[$_].Status -eq 'Failed'  })
$skipped    = @($siteCollections | Where-Object { -not $deployResults.ContainsKey($_) })

Write-Host ''
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ("  Deployment Summary  [$environmentName]") -ForegroundColor $envColor
if ($cancelled) { Write-Host "  $iWarn Run was cancelled -- results below are partial." -ForegroundColor Yellow }
Write-Host ("  " + [string]([char]0x2500) * 68) -ForegroundColor DarkGray
Write-Host ("  {0,-2}  Success  : {1}" -f $iOK,   $successful.Count) -ForegroundColor Green
Write-Host ("  {0,-2}  Failed   : {1}" -f $iFail,  $failed.Count)     -ForegroundColor $(if ($failed.Count -gt 0) { 'Red' } else { 'DarkGray' })
if ($cancelled -or $skipped) {
    Write-Host ("  {0,-2}  Skipped  : {1}" -f $iSkip, $skipped.Count) -ForegroundColor DarkYellow
}

if ($failed) {
    Write-Host ''
    Write-Host '  Failed site details:' -ForegroundColor Red
    $failed | ForEach-Object {
        $r        = $deployResults[$_]
        $tot      = if ($r -and $r.Total)    { $r.Total }    else { 5 }
        $stepInfo = if ($r -and $r.FailStep -gt 0) { "  [step $($r.FailStep)/$tot]" } else { '' }
        $errMsg   = if ($r -and $r.Error)    { "  --  $($r.Error)" }               else { '' }
        Write-Host "    $iFail $_$stepInfo$errMsg" -ForegroundColor Red
    }
}

#endregion

#region -- Write Summary to Log ----------------------------------------------

Write-RunSummary -Successful $successful -Failed $failed -Skipped $skipped `
    -Cancelled $cancelled -EnvironmentName $environmentName

Write-Host "  Log file : $logFile" -ForegroundColor DarkGray
Write-Host ''
