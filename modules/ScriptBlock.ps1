# ======== modules/ScriptBlock.ps1 ========
# Dot-sourced by deploy.ps1.
# Defines $scriptBlock — the worker passed to Start-Job for each site deployment.
#
# The scriptblock is self-contained: it only uses its own params and built-in cmdlets.
# Progress events are emitted via Write-Output as PSCustomObject so the host can
# update the dashboard in real time.  The final return value is a plain hashtable.

$scriptBlock = {
    param(
        [string]$siteUrl,
        [string]$packagePath
    )

    # Convert all non-terminating errors to terminating so every failure
    # is caught by the single catch block and reported cleanly.
    $ErrorActionPreference = 'Stop'

    $TOTAL    = 5
    $result   = @{ Site = $siteUrl; Status = 'Failed'; Error = $null; FailStep = 0 }
    $lastStep = 0

    try {
        $startTime = Get-Date

        # Step 1 — Connect
        $lastStep = 1
        Write-Output ([PSCustomObject]@{
            Site  = $siteUrl; Phase = 'Connecting'; Step = 1; Total = $TOTAL
            Ts    = (Get-Date -Format 'HH:mm:ss')
        })
        Connect-PnPOnline -Url $siteUrl -UseWebLogin -WarningAction SilentlyContinue -ErrorAction Stop

        # Step 2 — Check if app already exists in the site app catalog list
        $lastStep  = 2
        $sppkgFile = [System.IO.Path]::GetFileName($packagePath)
        Write-Output ([PSCustomObject]@{
            Site  = $siteUrl; Phase = 'Checking'; Step = 2; Total = $TOTAL
            Ts    = (Get-Date -Format 'HH:mm:ss')
        })
        $camlQuery   = "<View><Query><Where><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>$sppkgFile</Value></Eq></Where></Query></View>"
        $existingItem = Get-PnPListItem -List 'Apps for SharePoint' -Query $camlQuery -ErrorAction SilentlyContinue

        # Step 3 — Upload: Overwrite if exists, Add+Publish if new
        $lastStep = 3
        if ($existingItem) {
            Write-Output ([PSCustomObject]@{
                Site  = $siteUrl; Phase = 'Updating'; Step = 3; Total = $TOTAL
                Ts    = (Get-Date -Format 'HH:mm:ss')
            })
            $uploadedApp = Add-PnPApp -Path $packagePath -Scope Site -Overwrite -ErrorAction Stop
        }
        else {
            Write-Output ([PSCustomObject]@{
                Site  = $siteUrl; Phase = 'Installing'; Step = 3; Total = $TOTAL
                Ts    = (Get-Date -Format 'HH:mm:ss')
            })
            $uploadedApp = Add-PnPApp -Path $packagePath -Scope Site -Publish -SkipFeatureDeployment -ErrorAction Stop
        }

        # Step 4 — Publish (commented out — testing whether -Publish on Add-PnPApp is sufficient)
        $lastStep = 4
        Write-Output ([PSCustomObject]@{
            Site  = $siteUrl; Phase = 'Publishing'; Step = 4; Total = $TOTAL
            Ts    = (Get-Date -Format 'HH:mm:ss')
        })
        # Publish-PnPApp -Identity $uploadedApp.Id -Scope Site -SkipFeatureDeployment -ErrorAction Stop

        # Step 5 — Done
        $elapsed = [math]::Round((New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds, 1)
        Write-Output ([PSCustomObject]@{
            Site    = $siteUrl; Phase = 'Done'; Step = 5; Total = $TOTAL
            Ts      = (Get-Date -Format 'HH:mm:ss'); Elapsed = $elapsed
        })
        $result.Status = 'Success'
    }
    catch {
        # Keep only the first line of the exception message — full noise suppressed.
        $msg = ($_.Exception.Message -split "`n")[0].Trim()
        Write-Output ([PSCustomObject]@{
            Site  = $siteUrl; Phase = 'Failed'; Step = $lastStep; Total = $TOTAL
            Ts    = (Get-Date -Format 'HH:mm:ss'); Error = $msg
        })
        $result.Error    = $msg
        $result.FailStep = $lastStep
    }

    return $result
}
