# Azure Data Factory & Microsoft Graph Permissions Sample

This sample provides PowerShell scripts to automate the creation of an Azure Data Factory (ADF) and the process of granting its managed identity permissions to the Microsoft Graph API. Specifically, it focuses on assigning the `Sites.Selected` permission, which is a common requirement for data pipelines that need to access specific SharePoint Online sites securely.

## Overview

This solution enables an Azure Data Factory to securely authenticate to Microsoft Graph using its own managed identity, eliminating the need for storing secrets or credentials. This is the recommended best practice for Azure services that need to interact with APIs like Microsoft Graph.

The sample includes two primary scripts:

1.  **`New-AzureDataFactory.ps1`**: Creates a new Azure Data Factory and its corresponding resource group if it doesn't already exist.
2.  **`Grant-GraphPermissionsToAzureDataFactory.ps1`**: Grants the `Sites.Selected` application permission to the ADF's system-assigned managed identity.

## Prerequisites

Before you begin, ensure you have the following:

*   An active **Azure Subscription**.
*   **PowerShell 7.x** or later.
*   The following PowerShell modules installed:
    *   **Azure Az Module**: `Install-Module Az -Scope CurrentUser`
    *   **Microsoft Graph Module**: `Install-Module Microsoft.Graph -Scope CurrentUser`
*   Sufficient permissions in your Microsoft Entra ID tenant to grant application permissions (e.g., a user with the **Cloud Application Administrator** or **Application Administrator** role).

## 🔐 The Core Problem: Why Scripts are Necessary for API Permissions

A common point of confusion is why you can't just assign Microsoft Graph permissions to a managed identity in the Azure Portal. The reason lies in the two distinct permission models used by Azure:

1.  **Azure RBAC (Role-Based Access Control)**: This is the permission system for managing **Azure resources**. It governs actions like creating a VM, deleting a Storage Account, or reading a Key Vault secret. The "Access control (IAM)" blade in the Azure Portal is the graphical interface for Azure RBAC. You can use it to grant an ADF's managed identity roles like "Storage Blob Data Reader."

2.  **Microsoft Entra ID Application Permissions**: This system governs access to **data exposed by an API**, most notably Microsoft Graph. These permissions (called `app roles`) control whether an application can read user profiles, send an email, or, in this case, access SharePoint sites.

### The GUI Limitation

When you navigate to an Azure Data Factory's managed identity in the Azure Portal, the "Azure role assignments" page interacts *only* with the Azure RBAC system. The portal **does not have a built-in interface** to browse and assign API permissions (like `Sites.Selected`) from Microsoft Graph to a managed identity. There is no "Grant Graph API Permissions" button.

### The Solution: Direct API Interaction

To grant an ADF's managed identity permissions to call the Microsoft Graph API, you must perform a series of steps directly against the underlying Entra ID APIs. The scripts in this repository automate this exact process:

1.  **Find the Service Principal** for your Azure Data Factory's managed identity. This is its security identity within Entra ID.
2.  **Find the Service Principal** for the target API (Microsoft Graph).
3.  **Look up the App Role ID** on the Graph service principal that corresponds to the permission you want (e.g., the unique ID for `Sites.Selected`).
4.  **Create an `appRoleAssignment`** object that links the ADF's service principal to the Graph app role.

These scripts handle this complexity, providing a reliable and repeatable way to configure the necessary API permissions that cannot be done through the Azure Portal's user interface.

## How to Use

Follow these steps to create an ADF and grant it permissions to access SharePoint.

### Step 1: Connect to Azure and Microsoft Graph

Open a PowerShell terminal and connect to both Azure (for resource management) and Microsoft Graph (for permission management). You will be prompted to sign in for each.

```powershell
# Connect to your Azure subscription
Connect-AzAccount

# Connect to Microsoft Graph with the required permission scopes
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All"
```

### Step 2: Create the Azure Data Factory

Run the `New-AzureDataFactory.ps1` script to provision the ADF. Provide a globally unique name for the Data Factory, a resource group name, and a location.

```powershell
# Navigate to the ps directory
cd "c:\Code Repo\azure-entra-id-samples\Entra-ID-Azure-Data-Factory-SPN-Permission\ps"

.\New-AzureDataFactory.ps1 -DataFactoryName "my-company-adf-001" -ResourceGroupName "adf-sp-rg" -Location "EastUS"
```

This will create the resource group (if needed) and the ADF. A managed identity is automatically created for the ADF.

### Step 3: Grant `Sites.Selected` Permission

Now, run the `Grant-GraphPermissionsToAzureDataFactory.ps1` script, providing the name of the ADF you just created.

```powershell
.\Grant-GraphPermissionsToAzureDataFactory.ps1 -DataFactoryName "my-company-adf-001"
```

The script will find the ADF's managed identity and assign the `Sites.Selected` permission from Microsoft Graph to it.

### Step 4: Grant Access to Specific SharePoint Sites (Crucial Next Step)

The `Sites.Selected` permission gives your ADF the *ability* to be granted access, but it doesn't have access to any sites yet. You must now explicitly grant access to each SharePoint site you want the ADF to read from.

This is done via a Microsoft Graph API call. Here is a sample PowerShell command to grant "read" access to a specific site:

```powershell
# 1. Find your ADF's Service Principal
$adfSp = Get-MgServicePrincipal -Filter "displayName eq 'my-company-adf-001'"

# 2. Find your SharePoint Site (replace 'My-Site' and 'mytenant.sharepoint.com' with your details)
$site = Get-MgSite -SiteId "mytenant.sharepoint.com:/sites/My-Site"

# 3. Prepare the permission grant
$params = @{
    roles = @("read") # Or "write"
    grantedToIdentities = @(
        @{
            application = @{
                id = $adfSp.AppId
                displayName = $adfSp.DisplayName
            }
        }
    )
}

# 4. Grant the permission to the site
New-MgSitePermission -SiteId $site.Id -BodyParameter $params
```

After completing this final step, your Azure Data Factory can now authenticate to Microsoft Graph and read data from the specified SharePoint site.

## Clean Up

To remove all resources created in this sample, you can delete the resource group. This will also delete the Azure Data Factory.

```powershell
Remove-AzResourceGroup -Name "adf-sp-rg" -Force
```