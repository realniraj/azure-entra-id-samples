# --- Step 1: Set your target environment variables (optional but recommended) ---
# This ensures you are targeting the correct tenant and subscription.
$tenantId = "89623cf5-82bf-46d4-9145-1f14a9b4ad0f"
$subscriptionId = "1c558941-67be-4a58-848f-2fcef3c5acf3"

# --- Step 2: Perform the Primary Login to Azure ---
# This is the only interactive login you will need to do.
Write-Host "Connecting to Azure..."
Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId

# --- Step 3: Get an Access Token specifically for Microsoft Graph ---
# This command leverages your existing Az login session to request a Graph token.
Write-Host "Requesting a Microsoft Graph token from the current Az session..."
# The -ResourceUrl specifies the audience for the token.
$graphToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/"

# --- Step 4: Connect to Microsoft Graph using the retrieved token ---
# The -AccessToken parameter tells Connect-MgGraph to use the token you provide
# instead of prompting for a new login.
Write-Host "Connecting to Microsoft Graph using the acquired token..."
Connect-MgGraph -AccessToken $graphToken.Token

# --- Step 5: Verify the connection ---
# This command will now succeed without any further login prompts.
$mgContext = Get-MgContext
if ($mgContext) {
    Write-Host "Successfully connected to Microsoft Graph as '$($mgContext.Account)' in tenant '$($mgContext.TenantId)'."
}
else {
    Write-Error "Failed to connect to Microsoft Graph."
}

# Now you can run any other MgGraph commands, like:
Get-MgUser -UserId "nirajkum@kloudezy.com"