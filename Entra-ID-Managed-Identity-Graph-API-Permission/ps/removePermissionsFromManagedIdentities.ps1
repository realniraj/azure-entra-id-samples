<#
.SYNOPSIS
    Removes specific Microsoft Graph API permissions from a User-Assigned Managed Identity.

.DESCRIPTION
    This script finds the service principal for a given User-Assigned Managed Identity
    and removes the 'User.Read.All' and 'Group.Read.All' delegated permissions from it.

.PARAMETER ManagedIdentityName
    The name of the User-Assigned Managed Identity.

.EXAMPLE
    .\removePermissionsFromManagedIdentity.ps1 -ManagedIdentityName "my-app-identity"
#>
<# Run this once in an elevated PowerShell terminal
Install-Module Microsoft.Graph -Scope AllUsers
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManagedIdentityName
)

# --- Step 1: Connect to Microsoft Graph ---
Write-Host "Connecting to Microsoft Graph..."
# Scopes required to read service principals and manage app role assignments
$requiredScopes = @("AppRoleAssignment.ReadWrite.All", "Application.Read.All")
Connect-MgGraph -Scopes $requiredScopes

# --- Step 2: Find the Service Principals ---
try {
    Write-Host "Finding the service principal for managed identity '$ManagedIdentityName'..."
    $managedIdentitySp = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityName'" -ErrorAction Stop
    if (-not $managedIdentitySp) {
        throw "Managed Identity '$ManagedIdentityName' not found."
    }

    Write-Host "Finding the service principal for Microsoft Graph API..."
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop

}
catch {
    Write-Error "Failed to find necessary service principals. Error: $_"
    return
}

# --- Step 3: Find the Specific App Role Assignments to Remove ---
$permissionsToRemove = @("User.Read.All", "Group.Read.All")
Write-Host "Checking for assigned permissions on '$ManagedIdentityName'..."

# Get all current app role assignments for the managed identity
$assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentitySp.Id

if (-not $assignments) {
    Write-Warning "No API permissions are assigned to '$ManagedIdentityName'."
    return
}

foreach ($permission in $permissionsToRemove) {
    # Find the App Role ID for the permission (e.g., the ID for 'User.Read.All')
    $appRoleId = ($graphSp.AppRoles | Where-Object { $_.Value -eq $permission }).Id

    if ($appRoleId) {
        # Find the assignment that links our identity to this specific role
        $assignmentToRemove = $assignments | Where-Object { $_.AppRoleId -eq $appRoleId }

        if ($assignmentToRemove) {
            Write-Host "Found assignment for '$permission'. Removing it..." -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess("'$($ManagedIdentityName)'", "Remove '$permission' permission")) {
                # --- Step 4: Remove the Assignment ---
                Remove-MgServicePrincipalAppRoleAssignment `
                    -ServicePrincipalId $managedIdentitySp.Id `
                    -AppRoleAssignmentId $assignmentToRemove.Id
                
                Write-Host "'$permission' permission has been successfully removed." -ForegroundColor Green
            }
        }
        else {
            Write-Host "Permission '$permission' is not assigned to '$ManagedIdentityName'."
        }
    }
}

Write-Host "Script finished."
Disconnect-MgGraph