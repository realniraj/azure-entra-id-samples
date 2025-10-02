#!/bin/bash

# This script removes the User.Read.All and Group.Read.All Microsoft Graph
# permissions from a User-Assigned Managed Identity.

# --- Configuration ---
MANAGED_IDENTITY_NAME="your-identity-name"

# --- DO NOT EDIT BELOW THIS LINE ---
set -e # Exit immediately if a command exits with a non-zero status.

echo "Finding service principal for managed identity '$MANAGED_IDENTITY_NAME'..."
IDENTITY_SP_ID=$(az ad sp list --display-name "$MANAGED_IDENTITY_NAME" --query "[0].id" -o tsv)

if [ -z "$IDENTITY_SP_ID" ]; then
    echo "Error: Could not find service principal for managed identity '$MANAGED_IDENTITY_NAME'"
    exit 1
fi

echo "Finding service principal for Microsoft Graph..."
GRAPH_SP_ID=$(az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv)

PERMISSIONS_TO_REMOVE=("User.Read.All" "Group.Read.All")

echo "Fetching current permission assignments for '$MANAGED_IDENTITY_NAME'..."
# Use az rest to get all assignments for the identity's service principal
ASSIGNMENTS_JSON=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${IDENTITY_SP_ID}/appRoleAssignments" -o json)

for permission in "${PERMISSIONS_TO_REMOVE[@]}"; do
    echo "-----------------------------------------------------"
    echo "Checking for permission: $permission"

    # Find the ID of the permission (the AppRoleId) on the MS Graph service principal
    APP_ROLE_ID=$(az ad sp show --id "$GRAPH_SP_ID" --query "appRoles[?value=='$permission'].id" -o tsv)

    if [ -z "$APP_ROLE_ID" ]; then
        echo "Warning: Could not find App Role ID for '$permission'. Skipping."
        continue
    fi
    
    # Find the ID of the assignment object that links the identity to the role
    ASSIGNMENT_ID=$(echo "$ASSIGNMENTS_JSON" | jq -r ".value[] | select(.appRoleId==\"$APP_ROLE_ID\") | .id")

    if [ -n "$ASSIGNMENT_ID" ]; then
        echo "Found assignment for '$permission'. Removing it..."
        
        # Use az rest to delete the specific assignment
        az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${IDENTITY_SP_ID}/appRoleAssignments/${ASSIGNMENT_ID}"
        
        echo "Successfully removed permission: '$permission'"
    else
        echo "Permission '$permission' is not assigned. Nothing to do."
    fi
done

echo "-----------------------------------------------------"
echo "Script finished."