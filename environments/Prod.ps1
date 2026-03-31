# ======== PROD Environment ========
# Dot-sourced by Deploy-SPFx-Solution.ps1.
# Provides: $environmentName, $siteCollections.
#
# Replace YOUR-TENANT and site names with your actual SharePoint production tenant and site collection paths.

$environmentName = 'PROD'

$siteCollections = @(
    'https://YOUR-TENANT.sharepoint.com',
    'https://YOUR-TENANT.sharepoint.com/sites/Department1',
    'https://YOUR-TENANT.sharepoint.com/sites/Department2',
    'https://YOUR-TENANT.sharepoint.com/sites/Department3'
    # Add more PROD site collections as needed...
)
