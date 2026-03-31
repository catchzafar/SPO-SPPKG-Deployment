# ======== DEV Environment ========
# Dot-sourced by Deploy-SPFx-Solution.ps1.
# Provides: $environmentName, $siteCollections.
#
# Replace YOUR-TENANT-dev and site names with your actual SharePoint tenant and site collection paths.

$environmentName = 'DEV'

$siteCollections = @(
    'https://YOUR-TENANT-dev.sharepoint.com/sites/YourApp-Dev',
    'https://YOUR-TENANT-dev.sharepoint.com/sites/DEV_Department1',
    'https://YOUR-TENANT-dev.sharepoint.com/sites/DEV_Department2',
    'https://YOUR-TENANT-dev.sharepoint.com/sites/DEV_Department3'
    # Add more DEV site collections as needed...
)
