# Azure Data Factory & Microsoft Graph Permissions Sample

This sample provides PowerShell scripts to automate the creation of an Azure Data Factory (ADF) and the process of granting its managed identity permissions to the Microsoft Graph API. Specifically, it focuses on assigning the `Sites.Selected` permission, which is a common requirement for data pipelines that need to access specific SharePoint Online sites securely.

## Overview

This solution enables an Azure Data Factory to securely authenticate to Microsoft Graph using its own managed identity, eliminating the need for storing secrets or credentials. This is the recommended best practice for Azure services that need to interact with APIs like Microsoft Graph.

The sample includes three primary scripts:

1.  **`New-AzureDataFactory.ps1`**: Creates a new Azure Data Factory and its corresponding resource group if it doesn't already exist.
2.  **`Grant-GraphPermissionsToAzureDataFactory.ps1`**: Grants the `Sites.Selected` application permission to the ADF's system-assigned managed identity.
3.  **`Grant-AdfSharePointSiteAccess.ps1`**: Grants the ADF's managed identity access to specific SharePoint Online sites.

## Prerequisites

Before you begin, ensure you have the following:

*   An active **Azure Subscription**.
*   **PowerShell 7.x** or later.
*   The following PowerShell modules:
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

## How to Use the Sample

Choose one of the three methods below to provision the resources.

### Method 1: Using PowerShell Scripts (`/ps`)

This method provides a step-by-step approach using individual PowerShell scripts.

1.  **Connect to Azure and Microsoft Graph**:
    Open a PowerShell terminal and run the generalized login script. This will handle both connections with a single sign-in.
    ```powershell
    # From the root of the repository
    .\Login-MicrosoftGaphApi.ps1 -TenantId "your-tenant-id" -SubscriptionId "your-subscription-id"
    ```

2.  **Create the Azure Data Factory**:
    Run the `New-AzureDataFactory.ps1` script to provision the ADF with a system-assigned managed identity.
    ```powershell
    # Navigate to the ps directory
    cd ".\Entra-ID-Azure-Data-Factory-SPN-Permission\ps"

    .\New-AzureDataFactory.ps1 -DataFactoryName "my-company-adf-001" -ResourceGroupName "adf-sp-rg" -Location "EastUS"
    ```

3.  **Grant `Sites.Selected` Permission**:
    Run the `Grant-GraphPermissionsToAzureDataFactory.ps1` script, providing the name of the ADF you just created.
    ```powershell
    .\Grant-GraphPermissionsToAzureDataFactory.ps1 -DataFactoryName "my-company-adf-001"
    ```

### Method 2: Using Shell Scripts (`/sh`)

This method uses Bash and the Azure CLI.

1.  **Log in to Azure**:
    Open a terminal and log in to your Azure account.
    ```sh
    az login --tenant "your-tenant-id"
    ```

2.  **Create the Azure Data Factory**:
    Run the `New-AzureDataFactory.sh` script.
    ```sh
    # Navigate to the sh directory
    cd "Entra-ID-Azure-Data-Factory-SPN-Permission/sh"

    ./New-AzureDataFactory.sh --data-factory-name "my-company-adf-001" --resource-group-name "adf-sp-rg" --location "EastUS"
    ```

3.  **Grant `Sites.Selected` Permission**:
    Edit the `Grant-GraphPermissionsToAzureDataFactory.sh` script to set your `TENANT_ID`, `SUBSCRIPTION_ID`, and `DATA_FACTORY_NAME`, then run it.
    ```sh
    ./Grant-GraphPermissionsToAzureDataFactory.sh
    ```

### Method 3: Using Terraform (`/tf`)

This declarative method creates and configures all resources in one operation.

1.  **Log in to Azure**:
    Open a terminal and log in to your Azure account.
    ```sh
    az login --tenant "your-tenant-id"
    ```

2.  **Initialize Terraform**:
    Navigate to the `/tf` directory and run `terraform init`.
    ```sh
    cd "Entra-ID-Azure-Data-Factory-SPN-Permission/tf"
    terraform init
    ```

3.  **Deploy the Resources**:
    Run `terraform apply`. You can override the default variable values if needed.
    ```sh
    terraform apply -var="data_factory_name=my-company-adf-001"
    ```
    Terraform will create the resource group, the Data Factory, and assign the `Sites.Selected` permission.

## Crucial Next Step: Grant Access to Specific SharePoint Sites

The `Sites.Selected` permission gives your ADF the *ability* to be granted access, but it doesn't have access to any sites yet. You must now explicitly grant access to each SharePoint site you want the ADF to read from.

The `Grant-AdfSharePointSiteAccess.ps1` script automates this process.

```powershell
# Ensure you are connected to Graph with the correct permissions
# Connect-MgGraph -Scopes "Sites.FullControl.All", "Application.Read.All"

# Grant 'read' access to the ADF for a specific site
.\ps\Grant-AdfSharePointSiteAccess.ps1 -DataFactoryName "my-company-adf-001" -SiteUrl "https://yourtenant.sharepoint.com/sites/Marketing"

# You can also grant 'write' access
.\ps\Grant-AdfSharePointSiteAccess.ps1 -DataFactoryName "my-company-adf-001" -SiteUrl "https://yourtenant.sharepoint.com/sites/DataStaging" -Permissions "write"
```

After completing this final step, your Azure Data Factory can now authenticate to Microsoft Graph and read data from the specified SharePoint site.

## Clean Up

To remove all resources created in this sample, you can delete the resource group. This will also delete the Azure Data Factory.

```powershell
Remove-AzResourceGroup -Name "adf-sp-rg" -Force
```