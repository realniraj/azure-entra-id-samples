<#
.SYNOPSIS
    Grants 'Sites.Selected' application permission to a specified Azure Data Factory
    by creating an app role assignment against the
    Microsoft Graph service principal.

.DESCRIPTION
    This script automates the process of granting Microsoft Graph API permissions to a
    Azure Data Factory's managed identity (service principal). It is idempotent, meaning it
    will check if the permission is already assigned and will not create a duplicate.

    You must run this script with an account that has sufficient privileges, such as
    'Cloud Application Administrator' or 'Application Administrator'.

.PARAMETER DataFactoryName
    The display name of the Azure Data Factory whose managed identity will be granted the permission.

.EXAMPLE
    .\Grant-GraphPermissionsToAzureDataFactory.ps1 -DataFactoryName "my-production-adf"

    This command will connect to Microsoft Graph, find the service principal for the managed
    identity of the Azure Data Factory named 'my-production-adf', and assign the
    'Sites.Selected' permission to it.

.EXAMPLE
    .\Grant-GraphPermissionsToAzureDataFactory.ps1 -DataFactoryName "my-production-adf" -Verbose

    This command runs the script with detailed verbose output, showing each step of the process.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The display name of the Azure Data Factory.")]
    [string]$DataFactoryName,

    [Parameter(Mandatory = $false, HelpMessage = "The Graph API application permissions to grant.")]
    [string[]]$Permission = @("Sites.Selected")
)

begin {
    try {
        # --- Step 1: Connect to Microsoft Graph if not already connected ---
        Write-Verbose "Checking for existing Microsoft Graph connection..."
        if (-not (Get-MgContext)) {
            Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
            # Scopes required for the script to read service principals and create app role assignments
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
        # Scopes required for the script to read service principals and create app role assignments
        # The App ID for Microsoft Graph is a well-known, constant value
        $script:graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
        Write-Verbose "Found Microsoft Graph Service Principal with ID: $($script:graphSp.Id)"
    }
    catch {
        Write-Error "An error occurred while finding the service principals. Error: $_"
        return
    }
}

process {
    # --- Step 3: Define and Assign App Roles ---
    foreach ($perm in $Permission) {
        Write-Host "`nProcessing permission: '$permission'..." -ForegroundColor Cyan

        # Find the specific App Role on the Microsoft Graph service principal
        $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $permission -and $_.AllowedMemberTypes -contains "Application" }

        if (-not $appRole) {
            Write-Warning "The permission '$permission' was not found on the Microsoft Graph service principal. Skipping."
            continue
        }

        # Check if the assignment already exists
        $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $dataFactorySp.Id | Where-Object { $_.AppRoleId -eq $appRole.Id }

        if ($existingAssignment) {
            Write-Host "Permission '$permission' is already assigned to '$DataFactoryName'. No action needed." -ForegroundColor Green
        }
        else {
            # Create the App Role Assignment
            $assignmentParams = @{
                ServicePrincipalId = $dataFactorySp.Id
                PrincipalId = $dataFactorySp.Id
                ResourceId = $graphSp.Id
                AppRoleId = $appRole.Id
            }

            if ($PSCmdlet.ShouldProcess("'$($DataFactoryName)'", "Grant permission '$($permission)'")) {
                Write-Verbose "Creating new app role assignment for permission '$permission'..."
                try {
                    New-MgServicePrincipalAppRoleAssignment @assignmentParams -ErrorAction Stop
                    Write-Host "Successfully assigned permission '$permission' to '$DataFactoryName'." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to assign permission '$permission'. Error: $_"
                }
            }
        }
    }
}

end {
    if ($script:DisconnectedInEndBlock) {
        Write-Verbose "Script finished. Disconnecting from Microsoft Graph."
        Disconnect-MgGraph
    }
}

<#
How to Run the Script

1.  Save the script to a file (e.g., `Grant-GraphPermissionsToAzureDataFactory.ps1`).
2.  Open PowerShell and navigate to the directory where you saved the file.
3.  Run the script, providing the name of your Azure Data Factory as a parameter. The script will prompt you to sign in.

Example usage
.\Grant-GraphPermissionsToAzureDataFactory.ps1 -DataFactoryName "my-demo-adf"

#>
    
