<#
.SYNOPSIS
    Creates an Azure Resource Group and a User-Assigned Managed Identity within it.
#>

# --- 1. Set your variables ---
$RESOURCE_GROUP_NAME = "my-managed-identity-rg"
$IDENTITY_NAME = "mySampleWebAppIdentity"
$LOCATION = "eastus"

# --- 2. Create the Resource Group ---
Write-Host "Creating resource group '${RESOURCE_GROUP_NAME}' in location '${LOCATION}'..."
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

# --- 3. Create the User-Assigned Managed Identity ---
Write-Host "Creating user-assigned managed identity '${IDENTITY_NAME}' in resource group '${RESOURCE_GROUP_NAME}'..."
az identity create --resource-group $RESOURCE_GROUP_NAME --name $IDENTITY_NAME

Write-Host "Process complete."