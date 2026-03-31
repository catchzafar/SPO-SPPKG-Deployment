# =============================================================================
# modules/Icons.ps1
# Centralised icon and symbol definitions for the deployment scripts.
#
# Dot-sourced early in deploy.ps1 (before the guards) and by Display.ps1.
# Uses [char] code points only — no literal Unicode, no encoding risk.
#
# Exports:
#   $unicodeConsole  — $true when the host can render Unicode
#   $phaseIcon       — hashtable: phase name -> 2-char status column symbol
#   $iOK             — success indicator (● / OK)
#   $iFail           — failure indicator (✗ / !!)
#   $iSkip           — skipped / cancelled indicator (◌ / --)
#   $iWarn           — warning indicator (▲ / /!)
#   $iInfo           — informational hint indicator (i / i:)
# =============================================================================

#region -- Unicode Detection -------------------------------------------------

# Force UTF-8 output so [char] symbols render on any capable host.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$unicodeConsole = $false
try { $unicodeConsole = ([Console]::OutputEncoding.CodePage -eq 65001) } catch { }

#endregion

#region -- Phase Icons -------------------------------------------------------
#
# Each value is exactly 2 chars wide: Unicode symbol + space, or 2-char ASCII.
# Used by Update-SiteLine in Display.ps1 to build the fixed-width status column.
#
# Unicode reference:
#   0x25BA ►  Black Right-Pointing Pointer
#   0x2191 ↑  Upwards Arrow
#   0x2713 ✓  Check Mark
#   0x00BB »  Right-Pointing Double Angle Quotation Mark
#   0x25CF ●  Black Circle
#   0x2717 ✗  Ballot X
#   0x25CC ◌  Dotted Circle
#   0x25CB ○  White Circle

$phaseIcon = if ($unicodeConsole) {
    @{
        Connecting = [string][char]0x25BA + ' '   # ►
        Checking   = [string][char]0x2026 + ' '   # …
        Uploading  = [string][char]0x2191 + ' '   # ↑
        Uploaded   = [string][char]0x2713 + ' '   # ✓
        Publishing = [string][char]0x00BB + ' '   # »
        Updating   = [string][char]0x21BA + ' '   # ↺
        Upgrading  = [string][char]0x21BA + ' '   # ↺
        Installing = [string][char]0x2193 + ' '   # ↓
        Done       = [string][char]0x25CF + ' '   # ●
        Failed     = [string][char]0x2717 + ' '   # ✗
        Cancelled  = [string][char]0x25CC + ' '   # ◌
        Queued     = [string][char]0x25CB + ' '   # ○
    }
} else {
    @{
        Connecting = '>>'
        Checking   = '??'
        Uploading  = '~~'
        Uploaded   = '+]'
        Publishing = '^^'
        Updating   = '<>'
        Upgrading  = '<>'
        Installing = 'vv'
        Done       = 'OK'
        Failed     = '!!'
        Cancelled  = '--'
        Queued     = '--'
    }
}

#endregion

#region -- Status Indicators -------------------------------------------------
#
# Short symbols used in freeform messages, summary lines, and banner text.
#
# Unicode reference:
#   0x25CF ●  Black Circle        (success)
#   0x2717 ✗  Ballot X            (failure)
#   0x25CC ◌  Dotted Circle       (skipped / cancelled)
#   0x25B2 ▲  Black Up-Pointing Triangle  (warning)
#   0x2139 i  Information Source  (informational hint)

$iOK   = if ($unicodeConsole) { [string][char]0x25CF } else { 'OK' }   # ● success
$iFail = if ($unicodeConsole) { [string][char]0x2717 } else { '!!' }   # ✗ failure
$iSkip = if ($unicodeConsole) { [string][char]0x25CC } else { '--' }   # ◌ skipped / cancelled
$iWarn = if ($unicodeConsole) { [string][char]0x25B2 } else { '/!' }   # ▲ warning
$iInfo = if ($unicodeConsole) { [string][char]0x2139 } else { 'i:' }   # i informational hint

#endregion
