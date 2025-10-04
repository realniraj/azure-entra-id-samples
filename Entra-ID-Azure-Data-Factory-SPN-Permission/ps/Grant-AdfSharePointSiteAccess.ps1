<#
.SYNOPSIS
    Grants an Azure Data Factory's managed identity specific permissions (e.g., read, write)
    to a target SharePoint Online site.

.DESCRIPTION
    This script is the second step in a two-part process. It should be run AFTER the ADF's
    managed identity has been granted the 'Sites.Selected' Microsoft Graph API permission.

    The script automates granting site-level access by:
    1. Finding the ADF's managed identity (service principal).
    2. Finding the target SharePoint Online site by its URL.
    3. Creating a permission grant on the site for the ADF identity.

    You must run this script with an account that has sufficient privileges to manage
    SharePoint site permissions via Graph API, such as 'Sites.FullControl.All'.

.PARAMETER DataFactoryName
    The display name of the Azure Data Factory whose managed identity will be granted access.

.PARAMETER SiteUrl
    The full URL of the SharePoint Online site to grant access to (e.g., "https://yourtenant.sharepoint.com/sites/YourSite").

.PARAMETER Permissions
    The permission level to grant. Valid values are 'read' or 'write'. Defaults to 'read'.

.EXAMPLE
    .\Grant-AdfSharePointSiteAccess.ps1 -DataFactoryName "my-prod-adf" -SiteUrl "https://contoso.sharepoint.com/sites/Finance"

    This command grants 'read' access to the 'Finance' SharePoint site for the managed identity
    of the Azure Data Factory named 'my-prod-adf'.

.EXAMPLE
    .\Grant-AdfSharePointSiteAccess.ps1 -DataFactoryName "my-etl-adf" -SiteUrl "https://contoso.sharepoint.com/sites/ProjectX" -Permissions "write" -Verbose

    This command grants 'write' access to the 'ProjectX' site for the 'my-etl-adf' identity
    and provides detailed verbose output.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The display name of the Azure Data Factory.")]
    [string]$DataFactoryName,

    [Parameter(Mandatory = $true, HelpMessage = "The full URL of the SharePoint Online site.")]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false, HelpMessage = "The permission level to grant.")]
    [ValidateSet("read", "write")]
    [string]$Permissions = "read"
)

begin {
    # --- Step 1: Connect to Microsoft Graph ---
    Write-Verbose "Connecting to Microsoft Graph..."
    try {
        # Scopes required to find service principals and manage site permissions.
        # Sites.FullControl.All is a high-privilege scope required to grant permissions to other applications.
        $requiredScopes = @("Sites.FullControl.All", "Application.Read.All")
        Connect-MgGraph -Scopes $requiredScopes -ErrorAction Stop
        Write-Verbose "Successfully connected to Microsoft Graph."
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph. Please ensure you have the module installed and can authenticate with the required scopes. Error: $_"
        return # Stop script execution
    }
}

process {
    try {
        # --- Step 2: Find the ADF Service Principal ---
        Write-Verbose "Finding the service principal for Azure Data Factory: '$DataFactoryName'"
        $adfSp = Get-MgServicePrincipal -Filter "displayName eq '$DataFactoryName'" -ErrorAction Stop
        if (-not $adfSp) {
            throw "Azure Data Factory '$DataFactoryName' could not be found as a service principal in Microsoft Entra ID."
        }
        Write-Host "Found ADF Service Principal. ID: $($adfSp.Id), AppId: $($adfSp.AppId)" -ForegroundColor Green

        # --- Step 3: Find the SharePoint Site ---
        # The Get-MgSite command requires a 'hostname,relative-path' format for the -SiteId parameter.
        $uri = [System.Uri]$SiteUrl
        $siteIdForGraph = "$($uri.Host):$($uri.AbsolutePath)"
        Write-Verbose "Querying for SharePoint site with ID: '$siteIdForGraph'"
        $site = Get-MgSite -SiteId $siteIdForGraph -ErrorAction Stop
        if (-not $site) {
            throw "SharePoint site at URL '$SiteUrl' could not be found."
        }
        Write-Host "Found SharePoint Site '$($site.DisplayName)'. ID: $($site.Id)" -ForegroundColor Green

        # --- Step 4: Check for Existing Permissions ---
        Write-Verbose "Checking for existing permissions on the site for '$DataFactoryName'..."
        $existingPermissions = Get-MgSitePermission -SiteId $site.Id
        $appHasPermission = $existingPermissions.GrantedToIdentities | ForEach-Object { $_.Application.Id -eq $adfSp.AppId }

        if ($appHasPermission) {
            Write-Host "The application '$DataFactoryName' already has permissions on this site. No action needed." -ForegroundColor Yellow
            return
        }

        # --- Step 5: Grant the Permission ---
        $permissionParams = @{
            roles = @($Permissions)
            grantedToIdentities = @(
                @{
                    application = @{
                        id = $adfSp.AppId
                        displayName = $adfSp.DisplayName
                    }
                }
            )
        }

        if ($PSCmdlet.ShouldProcess("Site '$($site.DisplayName)'", "Grant '$Permissions' access to ADF '$DataFactoryName'")) {
            Write-Verbose "Granting '$Permissions' permission to '$DataFactoryName' on site '$($site.DisplayName)'..."
            New-MgSitePermission -SiteId $site.Id -BodyParameter $permissionParams -ErrorAction Stop
            Write-Host "Successfully granted '$Permissions' access to '$DataFactoryName' for site '$($site.DisplayName)'." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "An error occurred during the process. Error: $_"
        return
    }
}

end {
    Write-Verbose "Script finished. Disconnecting from Microsoft Graph."
    Disconnect-MgGraph
}