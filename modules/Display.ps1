# ======== modules/Display.ps1 ========
# Dot-sourced by deploy.ps1.
# Responsibilities:
#   - Dot-sources Icons.ps1    -- unicode detection, phase icons, status indicators
#   - Dot-sources Logging.ps1  -- Write-Log, Write-RunSummary
#   - $dashboardMode           -- cursor-repositioning capability detection
#   - $lineWidth               -- line width for dashboard layout
#   - function Update-SiteLine -- in-place cursor-overwrite per site row
#   - function Invoke-DrainJob -- drain job output stream -> Update-SiteLine + Write-Log
#
# All functions reference caller-scope variables via $script:* because they are
# defined by dot-sourcing into deploy.ps1's script scope.

# Icons, unicode detection, and status indicators live in Icons.ps1.
# Dot-sourcing here makes Display.ps1 self-contained when used standalone.
. (Join-Path $PSScriptRoot 'Icons.ps1')
. (Join-Path $PSScriptRoot 'Logging.ps1')

#region -- Dashboard Detection -----------------------------------------------

# Separate from unicode detection: tests whether the host supports cursor
# repositioning (needed for in-place dashboard row overwriting).
$dashboardMode = $false
try {
    $null = [Console]::CursorTop
    [Console]::SetCursorPosition(0, [Console]::CursorTop)
    $dashboardMode = $true
} catch { }

$lineWidth = if ($dashboardMode) { [Math]::Max(60, [Console]::WindowWidth - 1) } else { 160 }

#endregion

#region ── Update-SiteLine ───────────────────────────────────────────────────

# Overwrites the pre-rendered row for a site with the current phase + colour.
# In dashboardMode uses SetCursorPosition for true in-place update.
# Falls back to printing a new line in non-interactive / redirected environments.
#
# Status column layout (fixed 24 chars):
#   ICON(2)  SPACE(1)  STEP/TOT(3)  SPACES(2)  LABEL(15)  SPACE(1)
#   Example: "►  1/5  Connecting...  "
#
# References deploy.ps1 script-scope vars: $siteIndex, $siteStartRow, $bottomRow,
#   $phaseIcon, $lineWidth, $dashboardMode.
function Update-SiteLine {
    param(
        [string]$siteUrl,
        [string]$phase,
        [int]$step    = 0,
        [int]$total   = 5,
        [string]$detail = '',
        [ConsoleColor]$color = 'Yellow'
    )

    $idx  = $script:siteIndex[$siteUrl]
    $n    = ($idx + 1).ToString().PadLeft(2)
    $row  = $script:siteStartRow + $idx

    $stepStr = if ($step -gt 0) { "$step/$total" } else { '---' }

    $icon = $script:phaseIcon[$phase]
    if (-not $icon) { $icon = $script:phaseIcon['Queued'] }

    $label = switch ($phase) {
        'Connecting' { 'Connecting...  ' }
        'Checking'   { 'Checking...    ' }
        'Uploading'  { 'Uploading...   ' }
        'Uploaded'   { 'Upload done    ' }
        'Publishing' { 'Publishing...  ' }
        'Updating'   { 'Updating...    ' }
        'Upgrading'  { 'Upgrading...   ' }
        'Installing' { 'Installing...  ' }
        'Done'       { ("Done $detail         ").PadRight(15).Substring(0, 15) }
        'Failed'     { 'Failed         ' }
        'Cancelled'  { 'Cancelled      ' }
        default      { 'Queued         ' }
    }

    $statusCol = "$icon $stepStr  $label"   # 24 chars
    $prefix    = "  [$n]  $statusCol "
    $sitePart  = $siteUrl
    if ($phase -eq 'Failed' -and $detail) { $sitePart += "  -- $detail" }

    $maxSite = $script:lineWidth - $prefix.Length
    if ($maxSite -lt 0) { $maxSite = 0 }
    if ($sitePart.Length -gt $maxSite) { $sitePart = $sitePart.Substring(0, $maxSite) }

    $line = ($prefix + $sitePart).PadRight($script:lineWidth)

    if ($script:dashboardMode) {
        try {
            [Console]::SetCursorPosition(0, $row)
            Write-Host $line -ForegroundColor $color -NoNewline
            [Console]::SetCursorPosition(0, $script:bottomRow)
        } catch { }
    } else {
        Write-Host "  [$n]  $statusCol $sitePart" -ForegroundColor $color
    }
}

#endregion

#region ── Invoke-DrainJob ────────────────────────────────────────────────────

# Receives all available output from a background job.
# PSCustomObject items  -> Update-SiteLine + Write-Log
# Hashtable items       -> stored in $deployResults (final job result)
#
# 2>$null suppresses job error-stream records from bleeding to the console;
# errors are already captured as PSCustomObject via Write-Output inside the job.
#
# References deploy.ps1 script-scope var: $deployResults.
function Invoke-DrainJob {
    param([string]$site, $job)

    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue 2>$null
    foreach ($item in $output) {

        # Final result hashtable emitted by the job's return statement
        if ($item -is [System.Collections.Hashtable]) {
            if ($item.ContainsKey('Status')) { $script:deployResults[$site] = $item }
            continue
        }

        # Progress event (PSCustomObject or its deserialized form from a job)
        $phase = $null
        try { $phase = [string]$item.Phase } catch { }
        if (-not $phase) { continue }

        $step   = try { [int]$item.Step  } catch { 0 }
        $total  = try { [int]$item.Total } catch { 5 }
        $detail = ''
        $color  = [ConsoleColor]::Yellow

        switch ($phase) {
            'Done' {
                $e = try { $item.Elapsed } catch { $null }
                if ($e) { $detail = "($e`s)" }
                $color = [ConsoleColor]::Green
            }
            'Failed' {
                $e = try { $item.Error } catch { $null }
                if ($e) { $detail = [string]$e }
                $color = [ConsoleColor]::Red
            }
        }

        Update-SiteLine -siteUrl $site -phase $phase -step $step -total $total -detail $detail -color $color

        # Structured log
        $logLevel = switch ($phase) {
            'Done'      { 'SUCCESS' }
            'Failed'    { 'FAILED'  }
            'Cancelled' { 'CANCEL'  }
            default     { 'INFO'    }
        }
        $logMsg = "[$step/$total] $phase"
        if ($detail) { $logMsg += "  $detail" }
        Write-Log -siteUrl $site -level $logLevel -message "$logMsg  $site"
    }
}

#endregion
