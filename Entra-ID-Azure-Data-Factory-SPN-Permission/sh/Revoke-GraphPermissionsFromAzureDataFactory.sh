#!/bin/bash
set -euo pipefail

# --- 1. Configuration: Set your target environment variables ---
TENANT_ID="89623cf5-82bf-46d4-9145-1f14a9b4ad0f"
SUBSCRIPTION_ID="1c558941-67be-4a58-848f-2fcef3c5acf3"
DATA_FACTORY_NAME="my-unique-adf"

# --- 2. Authentication and Setup ---
echo "Checking Azure login status..."
if ! az account show > /dev/null 2>&1; then
  echo "Not logged in. Initiating login..."
  az login --tenant "${TENANT_ID}" --use-device-code --allow-no-subscriptions --only-show-errors
else
  echo "Already logged in."
fi

echo "Setting active subscription to '${SUBSCRIPTION_ID}'..."
az account set --subscription "${SUBSCRIPTION_ID}"

# --- 3. Fetch Required IDs ---
echo "Fetching required IDs..."

# Get the Principal ID (Object ID) of the target Service Principal by its display name.
# This universal method works for both System-Assigned and User-Assigned Managed Identities,
# as well as regular Application SPNs.
ADF_PRINCIPAL_ID=$(az ad sp list \
  --display-name "${DATA_FACTORY_NAME}" \
  --query "[0].id" \
  --output tsv)

if [[ -z "${ADF_PRINCIPAL_ID}" ]]; then
  echo "❌ Error: Could not find a Service Principal with the display name '${DATA_FACTORY_NAME}'."
  exit 1
fi
echo "  - Found ADF Principal ID: ${ADF_PRINCIPAL_ID}"

# Get the Object ID of the Microsoft Graph Service Principal
GRAPH_SP_ID=$(az ad sp show \
  --id 00000003-0000-0000-c000-000000000000 \
  --query "id" \
  --output tsv)

if [[ -z "${GRAPH_SP_ID}" ]]; then
  echo "❌ Error: Could not retrieve Microsoft Graph Service Principal ID."
  exit 1
fi
echo "  - Found Graph SP ID: ${GRAPH_SP_ID}"

# Get the ID for the 'Sites.Selected' application permission on the Graph SP
SITES_SELECTED_ROLE_ID=$(az ad sp show \
  --id "${GRAPH_SP_ID}" \
  --query "appRoles[?value=='Sites.Selected' && contains(allowedMemberTypes, 'Application')].id" \
  --output tsv)

if [[ -z "${SITES_SELECTED_ROLE_ID}" ]]; then
  echo "❌ Error: Could not find the 'Sites.Selected' App Role ID on the Microsoft Graph service principal."
  exit 1
fi
echo "  - Found 'Sites.Selected' Role ID: ${SITES_SELECTED_ROLE_ID}"

# --- 4. Find the Specific Permission Assignment to Remove ---
echo "Checking for existing permission assignment..."

ASSIGNMENT_ID=$(az rest \
  --method GET \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${ADF_PRINCIPAL_ID}/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --query "value[?appRoleId=='${SITES_SELECTED_ROLE_ID}' && resourceId=='${GRAPH_SP_ID}'].id" \
  --output tsv)

if [[ -z "${ASSIGNMENT_ID}" ]]; then
  echo "✅ Permission 'Sites.Selected' is not assigned to '${DATA_FACTORY_NAME}'. No action needed."
  exit 0
fi

echo "Found assignment with ID: ${ASSIGNMENT_ID}. Proceeding with removal..."

# --- 5. Remove the Permission ---
echo "Removing 'Sites.Selected' permission from ADF '${DATA_FACTORY_NAME}'..."

az rest \
  --method DELETE \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${ADF_PRINCIPAL_ID}/appRoleAssignments/${ASSIGNMENT_ID}" \
  --headers "Content-Type=application/json" \
  --only-show-errors

if [ $? -eq 0 ]; then
    echo "✅ Successfully removed 'Sites.Selected' permission from '${DATA_FACTORY_NAME}'."
else
    echo "❌ Error: Failed to remove permission. Please check the output above for details."
    exit 1
fi