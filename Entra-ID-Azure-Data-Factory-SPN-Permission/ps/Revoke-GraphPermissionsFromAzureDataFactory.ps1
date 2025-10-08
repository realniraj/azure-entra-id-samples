<#
.SYNOPSIS
    Revokes 'Sites.Selected' application permission from a specified Azure Data Factory
    by deleting an app role assignment from the Microsoft Graph service principal.

.DESCRIPTION
    This script automates the process of revoking Microsoft Graph API permissions from an
    Azure Data Factory's managed identity (service principal). It is idempotent, meaning it
    will check if the permission is already revoked and will not error if the assignment
    doesn't exist.

    You must run this script with an account that has sufficient privileges, such as
    'Cloud Application Administrator' or 'Application Administrator'.

.PARAMETER DataFactoryName
    The display name of the Azure Data Factory whose managed identity will have its permission revoked.

.EXAMPLE
    .\Revoke-GraphPermissionsFromAzureDataFactory.ps1 -DataFactoryName "my-production-adf"

    This command will connect to Microsoft Graph, find the service principal for the managed
    identity of the Azure Data Factory named 'my-production-adf', and remove the
    'Sites.Selected' permission assignment from it.

.EXAMPLE
    .\Revoke-GraphPermissionsFromAzureDataFactory.ps1 -DataFactoryName "my-production-adf" -Verbose

    This command runs the script with detailed verbose output, showing each step of the process.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The display name of the Azure Data Factory.")]
    [string]$DataFactoryName,

    [Parameter(Mandatory = $false, HelpMessage = "The Graph API application permissions to revoke.")]
    [string[]]$Permission = @("Sites.Selected")
)

begin {
    try {
        # --- Step 1: Connect to Microsoft Graph if not already connected ---
        Write-Verbose "Checking for existing Microsoft Graph connection..."
        if (-not (Get-MgContext)) {
            Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
            # Scopes required for the script to read service principals and manage app role assignments
            $requiredScopes = @("AppRoleAssignment.ReadWrite.All", "Application.Read.All")
            Connect-MgGraph -Scopes $requiredScopes -ErrorAction Stop
            $script:DisconnectedInEndBlock = $true
        }
        Write-Verbose "Successfully connected to Microsoft Graph."

        # --- Step 2: Find the necessary Service Principals ---
        Write-Verbose "Finding the service principal for the Azure Data Factory: '$DataFactoryName'"
        $dataFactorySps = Get-MgServicePrincipal -Filter "displayName eq '$DataFactoryName'" -ErrorAction Stop
        if (-not $dataFactorySps) {
            throw "Azure Data Factory '$DataFactoryName' could not be found as a service principal in Microsoft Entra ID."
        }
        if ($dataFactorySps.Count -gt 1) {
            throw "Found multiple service principals with display name '$DataFactoryName'. Please provide a more specific identifier."
        }
        $script:dataFactorySp = $dataFactorySps
        Write-Verbose "Found Azure Data Factory Service Principal with ID: $($script:dataFactorySp.Id)"

        Write-Verbose "Finding the service principal for Microsoft Graph API..."
        # The App ID for Microsoft Graph is a well-known, constant value
        $script:graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
        Write-Verbose "Found Microsoft Graph Service Principal with ID: $($script:graphSp.Id)"
    }
    catch {
        Write-Error "An error occurred during the initial setup. Error: $_"
        return
    }
}

process {
    # --- Step 3: Find and Revoke App Role Assignments ---
    foreach ($perm in $Permission) {
        Write-Host "`nProcessing permission: '$perm'..." -ForegroundColor Cyan

        # Find the specific App Role on the Microsoft Graph service principal
        $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm -and $_.AllowedMemberTypes -contains "Application" }

        if (-not $appRole) {
            Write-Warning "The permission '$perm' was not found on the Microsoft Graph service principal. Skipping."
            continue
        }

        # Check if the assignment already exists
        $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $dataFactorySp.Id | Where-Object { $_.AppRoleId -eq $appRole.Id }

        if ($existingAssignment) {
            if ($PSCmdlet.ShouldProcess("'$($DataFactoryName)'", "Revoke permission '$($perm)' (Assignment ID: $($existingAssignment.Id))")) {
                Write-Verbose "Removing app role assignment for permission '$perm'..."
                try {
                    Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $dataFactorySp.Id -AppRoleAssignmentId $existingAssignment.Id -ErrorAction Stop
                    Write-Host "Successfully revoked permission '$perm' from '$DataFactoryName'." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to revoke permission '$perm'. Error: $_"
                }
            }
        }
        else {
            Write-Host "Permission '$perm' is not assigned to '$DataFactoryName'. No action needed." -ForegroundColor Yellow
        }
    }
}

end {
    if ($script:DisconnectedInEndBlock) {
        Write-Verbose "Script finished. Disconnecting from Microsoft Graph."
        Disconnect-MgGraph
    }
}