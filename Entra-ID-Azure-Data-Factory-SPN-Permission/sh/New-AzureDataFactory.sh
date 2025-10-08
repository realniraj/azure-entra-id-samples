#!/bin/bash
set -euo pipefail

#
# .SYNOPSIS
#   Creates a new Azure Data Factory (V2) instance in a specified resource group.
#
# .DESCRIPTION
#   This script automates the creation of an Azure Data Factory using the Azure CLI.
#   It will first check if the specified resource group exists in the given location,
#   and if not, it will prompt to create it. It then creates the Data Factory with a
#   system-assigned managed identity enabled.
#
#   This script requires the Azure CLI and an authenticated Azure session.
#
# .PARAMETER --data-factory-name
#   The name for the new Azure Data Factory. This name must be globally unique.
#
# .PARAMETER --resource-group-name
#   The name of the resource group where the Data Factory will be created.
#
# .PARAMETER --location
#   The Azure region where the resource group and Data Factory will be located (e.g., 'EastUS', 'WestEurope').
#
# .EXAMPLE
#   ./New-AzureDataFactory.sh --data-factory-name "my-unique-adf" --resource-group-name "my-adf-rg" --location "EastUS"
#

usage() {
    echo "Usage: $0 --data-factory-name <ADF_NAME> --resource-group-name <RG_NAME> --location <LOCATION>"
    echo ""
    echo "Creates a new Azure Data Factory (V2) instance."
    echo ""
    echo "Arguments:"
    echo "  --data-factory-name    The globally unique name of the new Azure Data Factory."
    echo "  --resource-group-name  The name of the resource group for the Data Factory."
    echo "  --location             The Azure region for the resources (e.g., 'EastUS')."
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --data-factory-name) DATA_FACTORY_NAME="$2"; shift ;;
        --resource-group-name) RESOURCE_GROUP_NAME="$2"; shift ;;
        --location) LOCATION="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

# Validate parameters
if [ -z "${DATA_FACTORY_NAME-}" ] || [ -z "${RESOURCE_GROUP_NAME-}" ] || [ -z "${LOCATION-}" ]; then
    usage
fi

# --- 1. Check for az CLI and Connect to Azure ---
echo "Checking for Azure CLI and Azure connection..."
if ! command -v az &> /dev/null; then
    echo "❌ Error: The Azure CLI (az) is not installed. Please install it and try again."
    exit 1
fi

if ! az account show > /dev/null 2>&1; then
  echo "Not logged in to Azure. Initiating login..."
  az login --only-show-errors
fi
echo "✅ Successfully connected to Azure account."

# --- 2. Create Resource Group if it doesn't exist ---
echo "Checking for resource group '${RESOURCE_GROUP_NAME}'..."
if ! az group show --name "${RESOURCE_GROUP_NAME}" &> /dev/null; then
    echo "Resource group '${RESOURCE_GROUP_NAME}' not found. Creating it now in '${LOCATION}'..."
    az group create --name "${RESOURCE_GROUP_NAME}" --location "${LOCATION}" --output none
    echo "✅ Successfully created resource group '${RESOURCE_GROUP_NAME}'."
else
    echo "✅ Resource group '${RESOURCE_GROUP_NAME}' already exists."
fi

# --- 3. Create the Azure Data Factory ---
echo "Creating Azure Data Factory '${DATA_FACTORY_NAME}'..."
az datafactory create --name "${DATA_FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --location "${LOCATION}" --output none

# Retrieve the resource id for the newly-created Data Factory
ADF_ID=$(az datafactory show --name "${DATA_FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query id -o tsv)
if [ -z "${ADF_ID}" ]; then
    echo "❌ Failed to determine Data Factory resource id. Exiting."
    exit 1
fi

# Check current identity type (if any) and enable SystemAssigned if not already set
IDENTITY_TYPE=$(az resource show --ids "${ADF_ID}" --query "identity.type" -o tsv 2>/dev/null || true)
if [ "${IDENTITY_TYPE}" = "SystemAssigned" ]; then
    echo "✅ SystemAssigned managed identity is already enabled for '${DATA_FACTORY_NAME}'."
else
    echo "Enabling System-Assigned Managed Identity for '${DATA_FACTORY_NAME}'..."
    az resource update --ids "${ADF_ID}" --set identity.type=SystemAssigned --output none
    echo "✅ Enabled SystemAssigned managed identity."
fi

# Read the portal URL
ADF_URL=$(az datafactory show --name "${DATA_FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query "properties.portalUrl" -o tsv)
echo "✅ Successfully created Azure Data Factory '${DATA_FACTORY_NAME}'."
echo "ADF Portal URL: ${ADF_URL}"