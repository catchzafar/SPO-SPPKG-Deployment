# =============================================================================
# modules/Logging.ps1
# Dot-sourced by Display.ps1 (and transitively by deploy.ps1).
#
# Responsibilities:
#   - function Write-Log          -- append one structured UTF-8 log entry
#   - function Write-RunSummary   -- write full end-of-run summary block to log
#
# All functions reference deploy.ps1 script-scope vars via $script:*
# ($runId, $logFile, $siteGuids, $deployResults) — no parameters needed for
# those as they are fixed for the lifetime of one run.
# =============================================================================

#region -- Write-Log ----------------------------------------------------------

# Appends a single structured log entry.  Always called from the host (main)
# thread — background jobs cannot call this directly.
#
# Format:
#   [yyyy-MM-dd HH:mm:ss] [RUN:<guid>] [SITE:<guid>] [LEVEL   ] message
#
# Arguments:
#   -siteUrl   optional — resolves to [SITE:<guid>] via $script:siteGuids
#   -level     log level string, padded to 8 chars in the output
#   -message   free-form message text

function Write-Log {
    param(
        [string]$siteUrl = '',
        [string]$level   = 'INFO',
        [string]$message
    )
    $ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $sitePart = if ($siteUrl -and $script:siteGuids[$siteUrl]) {
        " [Thread_ID:$($script:siteGuids[$siteUrl])]"
    } else { '' }
    $entry = "[$ts] [RUN:$($script:runId)]$sitePart [$($level.PadRight(8))] $message"
    Add-Content -LiteralPath $script:logFile -Value $entry -Encoding UTF8
}

#endregion

#region -- Write-RunSummary ---------------------------------------------------

# Writes the complete end-of-run block to the log file:
#   SUMMARY  — aggregated counts + cancellation flag
#   SUCCESS  — one entry per successfully deployed site (with duration)
#   FAILED   — one entry per failed site (step + error message)
#   SKIPPED  — one entry per skipped / cancelled site
#   END      — total wall-clock duration for the run
#
# Called once at the end of deploy.ps1, after $successful / $failed / $skipped
# have been computed from $deployResults.

function Write-RunSummary {
    param(
        $Successful,          # pipeline-compatible collection of URLs
        $Failed,
        $Skipped,
        [bool]$Cancelled,
        [string]$EnvironmentName
    )

    # @($null).Count = 1 in PowerShell — filter nulls to get a true empty array.
    $arrOK      = @($Successful | Where-Object { $_ })
    $arrFail    = @($Failed     | Where-Object { $_ })
    $arrSkipped = @($Skipped    | Where-Object { $_ })

    $cntOK      = $arrOK.Count
    $cntFail    = $arrFail.Count
    $cntSkipped = $arrSkipped.Count
    $cntCancel  = if ($Cancelled) { $cntSkipped } else { 0 }

    # -- SUMMARY ---------------------------------------------------------------
    Write-Log -level 'SUMMARY' -message (
        "Success={0}  Failed={1}  Skipped={2}  Cancelled={3}  Env={4}{5}" -f
        $cntOK, $cntFail, $cntSkipped, $cntCancel,
        $EnvironmentName,
        $(if ($Cancelled) { '  [RUN CANCELLED]' } else { '' })
    )

    # -- Per-site results ------------------------------------------------------
    foreach ($s in $arrOK) {
        $r   = $script:deployResults[$s]
        $dur = if ($r -and $r.Elapsed) { "  Duration=$($r.Elapsed)s" } else { '' }
        Write-Log -siteUrl $s -level 'SUCCESS' -message "Deployment succeeded$dur  $s"
    }

    foreach ($s in $arrFail) {
        $r        = $script:deployResults[$s]
        $tot      = if ($r -and $r.Total)    { $r.Total }    else { 5 }
        $failStep = if ($r -and $r.FailStep) { $r.FailStep } else { 0 }
        $errMsg   = if ($r -and $r.Error)    { $r.Error }    else { 'unknown error' }
        Write-Log -siteUrl $s -level 'FAILED' -message (
            "Deployment failed at step $failStep/$tot  --  $errMsg  $s"
        )
    }

    foreach ($s in $arrSkipped) {
        Write-Log -siteUrl $s -level 'SKIPPED' -message (
            "Solution is not deployed (skipped/cancelled)  in $s"
        )
    }

    # -- END -------------------------------------------------------------------
    $runEndTime   = Get-Date
    $runStartLine = Get-Content -LiteralPath $script:logFile | Select-Object -First 1
    $runStartTime = [datetime]$runStartLine.Substring(1, 19)
    $runDuration  = [math]::Round(
        (New-TimeSpan -Start $runStartTime -End $runEndTime).TotalSeconds, 1
    )
    Write-Log -level 'END' -message (
        "Deployment run ended  Env={0}  Success={1}  Failed={2}  Skipped={3}  Duration={4}s" -f
        $EnvironmentName, $cntOK, $cntFail, $cntSkipped, $runDuration
    )
}

#endregion
