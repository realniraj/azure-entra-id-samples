#!/bin/bash

# --- 1. Set your variables ---
RESOURCE_GROUP_NAME="my-managed-identity-rg"
IDENTITY_NAME="mySampleWebAppIdentity"
LOCATION="eastus"


# --- 2. Create the Resource Group ---
echo "Creating resource group '${RESOURCE_GROUP_NAME}' in location '${LOCATION}'..."
az group create --name "${RESOURCE_GROUP_NAME}" --location "${LOCATION}"


# --- 3. Create the User-Assigned Managed Identity ---
echo "Creating user-assigned managed identity '${IDENTITY_NAME}' in resource group '${RESOURCE_GROUP_NAME}'..."
az identity create --resource-group "${RESOURCE_GROUP_NAME}" --name "${IDENTITY_NAME}"

echo "Process complete."