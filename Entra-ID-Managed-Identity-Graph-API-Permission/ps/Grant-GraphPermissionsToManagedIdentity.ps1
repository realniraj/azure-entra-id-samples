<#
.SYNOPSIS
    Grants 'User.Read.All' and 'Group.Read.All' application permissions
    to a specified managed identity by creating app role assignments against the
    Microsoft Graph service principal.

.DESCRIPTION
    This script automates the process of granting Microsoft Graph API permissions to a
    User-Assigned Managed Identity. It is idempotent, meaning it will check if permissions
    are already assigned and will not create duplicates.

    You must run this script with an account that has sufficient privileges, such as
    'Cloud Application Administrator' or 'Application Administrator'.

.PARAMETER ManagedIdentityName
    The display name of the User-Assigned Managed Identity that will be granted the permissions.

.EXAMPLE
    .\Grant-GraphPermissionsToManagedIdentity.ps1 -ManagedIdentityName "my-app-identity"

    This command will connect to Microsoft Graph, find the service principal for the managed
    identity named 'my-app-identity', and assign the User.Read.All and Group.Read.All
    permissions to it.

.EXAMPLE
    .\Grant-GraphPermissionsToManagedIdentity.ps1 -ManagedIdentityName "my-app-identity" -Verbose

    This command runs the script with detailed verbose output, showing each step of the process.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The display name of the User-Assigned Managed Identity.")]
    [string]$ManagedIdentityName
)

begin {
    # --- Step 1: Connect to Microsoft Graph ---
    Write-Verbose "Connecting to Microsoft Graph..."
    try {
        # Scopes required for the script to read service principals and create app role assignments
        $requiredScopes = @("AppRoleAssignment.ReadWrite.All", "Application.Read.All")
        Connect-MgGraph -Scopes $requiredScopes -ErrorAction Stop
        Write-Verbose "Successfully connected to Microsoft Graph."
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph. Please ensure you have the module installed and can authenticate. Error: $_"
        # Stop the script if connection fails
        return
    }

    # --- Step 2: Find the necessary Service Principals ---
    $managedIdentitySp = $null
    $graphSp = $null
    try {
        Write-Verbose "Finding the service principal for the managed identity: '$ManagedIdentityName'"
        $managedIdentitySp = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityName'" -ErrorAction Stop
        if (-not $managedIdentitySp) {
            throw "Managed Identity '$ManagedIdentityName' could not be found as a service principal in Microsoft Entra ID."
        }
        Write-Verbose "Found Managed Identity Service Principal with ID: $($managedIdentitySp.Id)"

        Write-Verbose "Finding the service principal for Microsoft Graph API..."
        # The App ID for Microsoft Graph is a well-known, constant value
        $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
        Write-Verbose "Found Microsoft Graph Service Principal with ID: $($graphSp.Id)"
    }
    catch {
        Write-Error "An error occurred while finding the service principals. Error: $_"
        return
    }
}

process {
    # --- Step 3: Define and Assign App Roles ---
    $permissionsToGrant = @(
        "User.Read.All",
        "Group.Read.All"
    )

    foreach ($permission in $permissionsToGrant) {
        Write-Host "`nProcessing permission: '$permission'..." -ForegroundColor Cyan

        # Find the specific App Role on the Microsoft Graph service principal
        $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $permission -and $_.AllowedMemberTypes -contains "Application" }

        if (-not $appRole) {
            Write-Warning "The permission '$permission' was not found on the Microsoft Graph service principal. Skipping."
            continue
        }

        # Check if the assignment already exists
        $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentitySp.Id | Where-Object { $_.AppRoleId -eq $appRole.Id }

        if ($existingAssignment) {
            Write-Host "Permission '$permission' is already assigned to '$ManagedIdentityName'. No action needed." -ForegroundColor Green
        }
        else {
            # Create the App Role Assignment
            $assignmentParams = @{
                ServicePrincipalId = $managedIdentitySp.Id
                PrincipalId = $managedIdentitySp.Id
                ResourceId = $graphSp.Id
                AppRoleId = $appRole.Id
            }

            if ($PSCmdlet.ShouldProcess("'$($ManagedIdentityName)'", "Grant permission '$($permission)'")) {
                Write-Verbose "Creating new app role assignment for permission '$permission'..."
                try {
                    New-MgServicePrincipalAppRoleAssignment @assignmentParams -ErrorAction Stop
                    Write-Host "Successfully assigned permission '$permission' to '$ManagedIdentityName'." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to assign permission '$permission'. Error: $_"
                }
            }
        }
    }
}

end {
    Write-Verbose "Script finished. Disconnecting from Microsoft Graph."
    Disconnect-MgGraph
}

<#
How to Run the Script

1.  Save the script to a file (e.g., `Grant-GraphPermissionsToManagedIdentity.ps1`).
2.  Open PowerShell and navigate to the directory where you saved the file.
3.  Run the script, providing the name of your managed identity as a parameter. The script will prompt you to sign in.

Example usage
.\Grant-GraphPermissionsToManagedIdentity.ps1 -ManagedIdentityName "my-demo-identity"

#>
    
