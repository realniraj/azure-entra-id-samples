#!/bin/bash
set -euo pipefail

# --- Step 1: Set your variables ---
MANAGED_IDENTITY_NAME="mySampleWebAppIdentity"
RESOURCE_GROUP_NAME="my-managed-identity-rg"

# --- Step 2: Get the necessary IDs ---
echo "Fetching required IDs..."

# The Principal ID of your Managed Identity (the assignee)
PRINCIPAL_ID=$(az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query "principalId" \
  --output tsv)

# The Object ID of the Microsoft Graph Service Principal (the resource)
RESOURCE_ID=$(az ad sp show \
  --id 00000003-0000-0000-c000-000000000000 \
  --query "id" \
  --output tsv)

# The ID for the 'User.Read.All' application permission
USER_READ_ALL_ID=$(az ad sp show \
  --id $RESOURCE_ID \
  --query "appRoles[?value=='User.Read.All' && contains(allowedMemberTypes, 'Application')].id" \
  --output tsv)


# The ID for the 'Group.Read.All' application permission
GROUP_READ_ALL_ID=$(az ad sp show \
  --id $RESOURCE_ID \
  --query "appRoles[?value=='Group.Read.All' && contains(allowedMemberTypes, 'Application')].id" \
  --output tsv)

echo "Principal (Managed Identity) ID: $PRINCIPAL_ID"
echo "Resource (MS Graph) ID: $RESOURCE_ID"
echo "User.Read.All Permission ID: $USER_READ_ALL_ID"
echo "Group.Read.All Permission ID: $GROUP_READ_ALL_ID"

# --- Step 3: Assign the 'User.Read.All' permission ---
echo "Assigning User.Read.All permission..."

USER_BODY=$(jq -n \
  --arg principalId "$PRINCIPAL_ID" \
  --arg resourceId "$RESOURCE_ID" \
  --arg appRoleId "$USER_READ_ALL_ID" \
  '{principalId:$principalId, resourceId:$resourceId, appRoleId:$appRoleId}')

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$RESOURCE_ID/appRoleAssignedTo" \
  --headers "Content-Type=application/json" \
  --body "$USER_BODY"

# --- Step 4: Assign the 'Group.Read.All' permission ---
echo "Assigning Group.Read.All permission..."

GROUP_BODY=$(jq -n \
  --arg principalId "$PRINCIPAL_ID" \
  --arg resourceId "$RESOURCE_ID" \
  --arg appRoleId "$GROUP_READ_ALL_ID" \
  '{principalId:$principalId, resourceId:$resourceId, appRoleId:$appRoleId}')

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$RESOURCE_ID/appRoleAssignedTo" \
  --headers "Content-Type=application/json" \
  --body "$GROUP_BODY"

echo "✅ Successfully assigned User.Read.All and Group.Read.All permissions to '$MANAGED_IDENTITY_NAME'."

