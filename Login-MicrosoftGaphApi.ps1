<#
.SYNOPSIS
    Connects to both Azure (Az PowerShell) and Microsoft Graph (Microsoft.Graph PowerShell)
    using a single interactive login.

.DESCRIPTION
    This script simplifies the authentication process when you need to work with both Azure Resource Manager
    and the Microsoft Graph API in the same PowerShell session. It performs a primary login to Azure
    and then uses that authenticated session to silently acquire an access token for Microsoft Graph,
    avoiding a second login prompt.

    The script is idempotent: if you are already connected, it will confirm the connection
    without prompting for a new login.

.PARAMETER TenantId
    The ID of the Azure AD tenant to connect to. If not provided, the login will be interactive.

.PARAMETER SubscriptionId
    The ID of the Azure subscription to set as the active context. If not provided, the default
    subscription for the account will be used.

.EXAMPLE
    .\Login-MicrosoftGaphApi.ps1

    Runs the script interactively, prompting you to log in and select a tenant/subscription if needed.

.EXAMPLE
    .\Login-MicrosoftGaphApi.ps1 -TenantId "xxxx-xxxx-xxxx-xxxx" -SubscriptionId "yyyy-yyyy-yyyy-yyyy"

    Connects to the specified tenant and sets the active subscription.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

# --- Step 1: Connect to Azure (Az PowerShell) ---
if (Get-AzContext) {
    Write-Host "Already connected to Azure as '$((Get-AzContext).Account)'."
}
else {
    Write-Host "Connecting to Azure..."
    $connectParams = @{}
    if ($TenantId) { $connectParams.Tenant = $TenantId }
    if ($SubscriptionId) { $connectParams.Subscription = $SubscriptionId }
    Connect-AzAccount @connectParams
}

# --- Step 2: Connect to Microsoft Graph ---
if (Get-MgContext) {
    Write-Host "Already connected to Microsoft Graph as '$((Get-MgContext).Account)'."
}
else {
    # Get an Access Token specifically for Microsoft Graph using the Az session
    Write-Host "Requesting a Microsoft Graph token from the current Az session..."
    try {
        $graphToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/" -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to get a Microsoft Graph token. Ensure your account has permissions. Error: $_"
        return
    }

    # Connect to Microsoft Graph using the retrieved token
    Write-Host "Connecting to Microsoft Graph using the acquired token..."
    Connect-MgGraph -AccessToken $graphToken.Token
}

# --- Step 3: Verify the connection ---
$mgContext = Get-MgContext
if ($mgContext) {
    Write-Host "✅ Successfully connected to Microsoft Graph as '$($mgContext.Account)' in tenant '$($mgContext.TenantId)'." -ForegroundColor Green
    # You can now run any other MgGraph commands, like getting the current user's profile:
    # Get-MgMe
}
else {
    Write-Error "Failed to connect to Microsoft Graph."
}