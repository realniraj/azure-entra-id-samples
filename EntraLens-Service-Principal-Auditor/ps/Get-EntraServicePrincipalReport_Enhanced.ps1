<#
.SYNOPSIS
    Generates a comprehensive and enhanced report of all Service Principals in a Microsoft Entra ID tenant.

.DESCRIPTION
    This script connects to Microsoft Graph to fetch all Service Principals. It gathers key details including type,
    permissions, credentials, and now includes ownership, creation date, last sign-in activity, and other
    contextual application properties. The final report is exported to a CSV file.

.NOTES
    Author: Niraj Kumar
    Date: September 26, 2025
    Prerequisites: Microsoft.Graph PowerShell module must be installed.
    Required Permissions: Application.Read.All, AppRoleAssignment.ReadWrite.All, Directory.Read.All, AuditLog.Read.All

.EXAMPLE
    .\Get-EntraServicePrincipalReport_Enhanced.ps1
#>

# This script requires -module Microsoft.Graph

try {
    # Define the required permissions (scopes), now including AuditLog for sign-in data
    $requiredScopes = @("Application.Read.All", "AppRoleAssignment.ReadWrite.All", "Directory.Read.All", "AuditLog.Read.All")

    # Connect to Microsoft Graph
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Green
    Connect-MgGraph -Scopes $requiredScopes
    
    Write-Host "Successfully connected. Fetching all Service Principals..." -ForegroundColor Green
    # Fetch all service principals (page through results)
    $servicePrincipals = Get-MgServicePrincipal -All -ErrorAction Stop

    # Prefetch Applications (map by AppId) to reduce per-SP calls and improve performance
    Write-Host "Prefetching application objects for performance..." -ForegroundColor Green
    $appsByAppId = @{}
    try {
        $allApps = Get-MgApplication -All -ErrorAction Stop
        foreach ($a in $allApps) { if ($a.AppId) { $appsByAppId[$a.AppId] = $a } }
    } catch {
        Write-Verbose "Warning: failed to prefetch applications: $($_.Exception.Message)"
        $allApps = @()
    }

    # Prefetch app role assignments and oauth grants (skipped).
    # NOTE: Some versions of the Microsoft.Graph module prompt for ServicePrincipalId when calling
    # Get-MgServicePrincipalAppRoleAssignment or Get-MgServicePrincipalOauth2PermissionGrant without a
    # ServicePrincipalId. To avoid interactive prompts, we skip the global prefetch and fetch per-SP as needed.
    $appRoleAssignmentsByPrincipal = @{}
    $oauthGrantsByPrincipal = @{}
    Write-Verbose "Skipping global prefetch of app role assignments and oauth grants to avoid interactive prompts; will fetch per-SP when needed."

    if (-not $servicePrincipals) {
        Write-Warning "No Service Principals found or failed to retrieve them."
        return
    }

    # Initialize the list to store report data
    $reportData = [System.Collections.ArrayList]@()
 
    $totalCount = $servicePrincipals.Count
    $processedCount = 0

    foreach ($sp in $servicePrincipals) {
        $processedCount++
        Write-Progress -Activity "Processing Service Principals" -Status "Processing $($sp.DisplayName) ($processedCount of $totalCount)" -PercentComplete (($processedCount / $totalCount) * 100)

        # --- Get Corresponding Application Object for more details ---
        $appObject = $null
        $ownersFormatted = "Not an Application"
        $signInAudience = "N/A"
        $homepage = $sp.Homepage
        if ($sp.ServicePrincipalType -eq "Application") {
            # Use prefetched app object when available
            if ($appsByAppId.ContainsKey($sp.AppId)) { $appObject = $appsByAppId[$sp.AppId] }
            else {
                try { $appObject = Get-MgApplication -ApplicationId $sp.AppId -ErrorAction Stop } catch { $appObject = $null }
            }

            if ($appObject) {
                if ($appObject.SignInAudience) { $signInAudience = $appObject.SignInAudience }
                if (-not $homepage) {
                    if ($appObject.Homepage) { $homepage = $appObject.Homepage }
                    elseif ($appObject.Web -and $appObject.Web.HomepageUrl) { $homepage = $appObject.Web.HomepageUrl }
                }

                # --- Get Owners ---
                try {
                    $owners = Get-MgApplicationOwner -ApplicationId $appObject.Id -All -ErrorAction SilentlyContinue
                    if ($owners) {
                        $ownerLabels = $owners | ForEach-Object {
                            if ($_.UserPrincipalName) { $_.UserPrincipalName }
                            elseif ($_.Mail) { $_.Mail }
                            elseif ($_.DisplayName) { $_.DisplayName }
                            else { $_.Id }
                        }
                        $ownersFormatted = ($ownerLabels | Where-Object { $_ }) -join "; "
                        if ([string]::IsNullOrEmpty($ownersFormatted)) { $ownersFormatted = "No owners assigned" }
                    } else {
                        $ownersFormatted = "No owners assigned"
                    }
                } catch {
                    $ownersFormatted = "Error retrieving owners"
                }
            } else {
                $ownersFormatted = "App object not found"
            }
        }

        # --- Get Last Sign-In Date ---
        $lastSignIn = "No sign-in found"
        try {
            # Query recent sign-in logs (server-side sort not always supported) and pick latest client-side
            $signIns = Get-MgAuditLogSignIn -Filter "servicePrincipalId eq '$($sp.Id)'" -Top 50 -ErrorAction SilentlyContinue
            if ($signIns) {
                $latestSignIn = $signIns | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                if ($latestSignIn -and $latestSignIn.CreatedDateTime) { $lastSignIn = $latestSignIn.CreatedDateTime.ToString("yyyy-MM-dd HH:mm:ss") }
            }
        } catch {
            $lastSignIn = "Error retrieving sign-ins (check permissions)"
        }

        # --- Gather Credentials ---
        if ($sp.PasswordCredentials) { $secretExpiries = ($sp.PasswordCredentials | ForEach-Object { if ($_.EndDateTime) { $_.EndDateTime.ToString("yyyy-MM-dd") } else { "Unknown" } }) -join "; " } else { $secretExpiries = "None" }
        if ([string]::IsNullOrEmpty($secretExpiries)) { $secretExpiries = "None" }

        if ($sp.KeyCredentials) { $certExpiries = ($sp.KeyCredentials | ForEach-Object { if ($_.EndDateTime) { $_.EndDateTime.ToString("yyyy-MM-dd") } else { "Unknown" } }) -join "; " } else { $certExpiries = "None" }
        if ([string]::IsNullOrEmpty($certExpiries)) { $certExpiries = "None" }

        # --- Gather Permissions ---
        # Use prefetched oauth grants and app role assignments when possible to avoid pagination issues and many calls
        $apiPermissions = @()
        if ($sp.Id) {
            if ($oauthGrantsByPrincipal.ContainsKey($sp.Id)) { $apiPermissions = $oauthGrantsByPrincipal[$sp.Id] }
            else {
                try { $apiPermissions = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue } catch { $apiPermissions = @() }
            }
        } else { $apiPermissions = @() }
        $apiPermissionsFormatted = ($apiPermissions | ForEach-Object { "Resource: $($_.ResourceId) | Scope: $($_.Scope)" }) -join "; "
        if ([string]::IsNullOrEmpty($apiPermissionsFormatted)) { $apiPermissionsFormatted = "None" }

        $appRoleAssignments = @()
        if ($sp.Id) {
            if ($appRoleAssignmentsByPrincipal.ContainsKey($sp.Id)) { $appRoleAssignments = $appRoleAssignmentsByPrincipal[$sp.Id] }
            else {
                try { $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue } catch { $appRoleAssignments = @() }
            }
        } else { $appRoleAssignments = @() }

        # Format app role assignments; attempt to show resource display name when available
        $appRoleAssignmentsFormatted = ($appRoleAssignments | ForEach-Object {
            $assignment = $_
            $resourceName = $assignment.ResourceDisplayName
            if (-not $resourceName -and $assignment.ResourceId) {
                # Try to resolve to a service principal display name from earlier fetched list
                $resSP = $servicePrincipals | Where-Object { $_.Id -eq $assignment.ResourceId } | Select-Object -First 1
                if ($resSP) { $resourceName = $resSP.DisplayName }
            }
            if (-not $resourceName) { $resourceName = $assignment.ResourceId }
            "RoleId: $($assignment.AppRoleId) on Resource: $resourceName"
        }) -join "; "
        if ([string]::IsNullOrEmpty($appRoleAssignmentsFormatted)) { $appRoleAssignmentsFormatted = "None" }

        # --- Construct the Enhanced Report Object ---
        $reportObject = [PSCustomObject]@{
            DisplayName            = $sp.DisplayName
            AppId                  = $sp.AppId
            ObjectId               = $sp.Id
            ServicePrincipalType   = $sp.ServicePrincipalType
            AccountEnabled         = $sp.AccountEnabled
            CreatedDateTime        = $(if ($sp.CreatedDateTime) { $sp.CreatedDateTime.ToString("yyyy-MM-dd") } else { "Unknown" })
            LastSignInDateTime     = $lastSignIn
            Owners                 = $ownersFormatted
            SignInAudience         = $signInAudience
            HomepageURL            = $homepage
            Tags                   = $(if ($sp.Tags) { $sp.Tags -join "; " } else { "" })
            SecretExpiryDates      = $secretExpiries
            CertificateExpiryDates = $certExpiries
            ApiPermissions         = $apiPermissionsFormatted
            AppRoleAssignments     = $appRoleAssignmentsFormatted
        }

        $reportData.Add($reportObject)
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "EntraServicePrincipalReport_Enhanced_$($timestamp).csv"
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $filePath = Join-Path -Path $scriptRoot -ChildPath $fileName

    Write-Host "`nExporting enhanced report to $filePath..." -ForegroundColor Green
    $reportData | Export-Csv -Path $filePath -NoTypeInformation

    Write-Host "Report generation complete!" -ForegroundColor Green
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    # Convert the detailed error object to a single string to avoid passing an object array to Write-Error
    $detailed = ($_ | Format-List * -Force | Out-String)
    Write-Error -Message $detailed
}
finally {
    if (Get-MgContext) {
        Write-Host "Disconnecting from Microsoft Graph." -ForegroundColor Green
        Disconnect-MgGraph
    }
}
