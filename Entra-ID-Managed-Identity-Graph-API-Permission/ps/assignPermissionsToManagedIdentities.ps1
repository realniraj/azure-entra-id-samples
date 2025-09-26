<#
.SYNOPSIS
    Assigns Microsoft Graph API permissions to a user-assigned managed identity.
.DESCRIPTION
    This script grants 'User.Read.All' and 'Group.Read.All' application permissions
    to a specified managed identity by creating app role assignments against the
    Microsoft Graph service principal.
#>

# --- Step 1: Set your variables ---
$ManagedIdentityName = "mySampleWebAppIdentity"
$ResourceGroupName = "my-managed-identity-rg"
$GraphPermissions = @(
    "User.Read.All",
    "Group.Read.All"
)

# --- Step 2: Get the necessary IDs ---
Write-Host "Fetching required IDs..."

# The Principal ID of your Managed Identity (the assignee)
$PrincipalId = az identity show --name $ManagedIdentityName --resource-group $ResourceGroupName --query "principalId" --output tsv

# Get the Microsoft Graph Service Principal object. We'll reuse this.
$GraphSp = az ad sp show --id "00000003-0000-0000-c000-000000000000" | ConvertFrom-Json
$ResourceId = $GraphSp.id

Write-Host "Principal (Managed Identity) ID: $PrincipalId"
Write-Host "Resource (MS Graph) ID: $ResourceId"

# --- Step 3: Loop through and assign permissions ---
$tempFile = [System.IO.Path]::GetTempFileName()

foreach ($permission in $GraphPermissions) {
    Write-Host "Assigning permission: '$permission'..."

    # Find the App Role ID from the Graph Service Principal's appRoles property
    $AppRoleId = $GraphSp.appRoles | Where-Object { $_.value -eq $permission -and $_.allowedMemberTypes -contains 'Application' } | Select-Object -ExpandProperty id

    if (-not $AppRoleId) {
        Write-Warning "Could not find App Role ID for permission '$permission'. Skipping."
        continue
    }

    $body = @{
        principalId = $PrincipalId
        resourceId  = $ResourceId
        appRoleId   = $AppRoleId
    } | ConvertTo-Json

    $body | Out-File -FilePath $tempFile -Encoding utf8
    az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ResourceId/appRoleAssignedTo" --headers "Content-Type=application/json" --body "@$tempFile"
}

# --- Step 4: Clean up ---
Remove-Item -Path $tempFile -Force
Write-Host "✅ Permission assignment process complete for '$ManagedIdentityName'."