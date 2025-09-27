#!/bin/bash
#
# SYNOPSIS:
#   Generates a comprehensive report of all Service Principals in a Microsoft Entra ID tenant.
#
# DESCRIPTION:
#   This script uses the Azure CLI to fetch all Service Principals. It gathers key details
#   including type, permissions, credentials, ownership, creation date, and last sign-in
#   activity. The final report is exported to a CSV file.
#
# PREREQUISITES:
#   - Azure CLI (az)
#   - jq (for JSON parsing)
#
# REQUIRED PERMISSIONS:
#   The user running this script needs Microsoft Graph permissions, typically granted
#   through a role like 'Cloud Application Administrator'. The required permissions are:
#   - Application.Read.All
#   - AppRoleAssignment.ReadWrite.All (or .Read.All)
#   - Directory.Read.All
#   - AuditLog.Read.All
#

set -e

echo "Checking prerequisites..."

if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI (az) is not installed. Please install it and try again."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it and try again."
    exit 1
fi

echo "Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "You are not logged in to Azure. Please run 'az login' and consent to the required permissions."
    az login --scope https://graph.microsoft.com/.default > /dev/null
fi

echo "Successfully connected. Starting report generation..."

# --- 1. Prefetch data for performance ---
echo "Fetching all Service Principals... (This may take a few minutes)"
ALL_SPS=$(az ad sp list --all --query '[].{id:id, appId:appId, displayName:displayName, servicePrincipalType:servicePrincipalType, accountEnabled:accountEnabled, createdDateTime:createdDateTime, homepage:homepage, tags:tags, passwordCredentials:passwordCredentials, keyCredentials:keyCredentials}' -o json)

echo "Fetching all Applications..."
ALL_APPS=$(az ad app list --all --query '[].{appId:appId, id:id, signInAudience:signInAudience, web:{homepageUrl:web.homePageUrl}, owners:owners, displayName:displayName}' -o json)

# --- 2. Prepare for CSV output ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="EntraServicePrincipalReport_Enhanced_${TIMESTAMP}.csv"

echo "DisplayName,AppId,ObjectId,ServicePrincipalType,AccountEnabled,CreatedDateTime,LastSignInDateTime,Owners,SignInAudience,HomepageURL,Tags,SecretExpiryDates,CertificateExpiryDates,ApiPermissions,AppRoleAssignments" > "$FILENAME"

# --- 3. Process each Service Principal ---
TOTAL_COUNT=$(echo "$ALL_SPS" | jq 'length')
PROCESSED_COUNT=0

echo "$ALL_SPS" | jq -c '.[]' | while IFS= read -r sp; do
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    DISPLAY_NAME=$(echo "$sp" | jq -r '.displayName')
    
    # Progress bar
    PERCENT=$((PROCESSED_COUNT * 100 / TOTAL_COUNT))
    printf "\rProcessing Service Principals: [%-50s] %d%% (%d/%d) - %s" $(printf '#%.0s' $(seq 1 $((PERCENT/2)))) "$PERCENT" "$PROCESSED_COUNT" "$TOTAL_COUNT" "$DISPLAY_NAME"

    # --- Extract basic info ---
    APP_ID=$(echo "$sp" | jq -r '.appId // ""')
    OBJECT_ID=$(echo "$sp" | jq -r '.id // ""')
    SP_TYPE=$(echo "$sp" | jq -r '.servicePrincipalType // "N/A"')
    ACCOUNT_ENABLED=$(echo "$sp" | jq -r '.accountEnabled // "false"')
    CREATED_DT=$(echo "$sp" | jq -r '.createdDateTime // "Unknown"' | cut -d'T' -f1)
    HOMEPAGE=$(echo "$sp" | jq -r '.homepage // ""')
    TAGS=$(echo "$sp" | jq -r 'if .tags then .tags | join("; ") else "" end')

    # --- Initialize variables ---
    OWNERS_FORMATTED="Not an Application"
    SIGN_IN_AUDIENCE="N/A"
    
    # --- Get Application details if applicable ---
    if [[ "$SP_TYPE" == "Application" && "$APP_ID" != "null" && ! -z "$APP_ID" ]]; then
        APP_OBJECT=$(echo "$ALL_APPS" | jq --arg APP_ID "$APP_ID" '.[] | select(.appId == $APP_ID)')

        if [[ ! -z "$APP_OBJECT" ]]; then
            APP_OBJECT_ID=$(echo "$APP_OBJECT" | jq -r '.id')
            SIGN_IN_AUDIENCE=$(echo "$APP_OBJECT" | jq -r '.signInAudience // "N/A"')
            
            if [[ -z "$HOMEPAGE" || "$HOMEPAGE" == "null" ]]; then
                HOMEPAGE=$(echo "$APP_OBJECT" | jq -r '.web.homepageUrl // ""')
            fi

            # Get Owners
            OWNER_IDS=$(echo "$APP_OBJECT" | jq -r '.owners[].objectId | select(. != null)')
            if [[ ! -z "$OWNER_IDS" ]]; then
                OWNER_UPNS=()
                for owner_id in $OWNER_IDS; do
                    # Use 'az ad user show' or 'az ad sp show' to get UPN/DisplayName
                    # This is an expensive operation, so we'll use a placeholder for this example script.
                    # For a full implementation, you would query each owner ID.
                    # For simplicity, we'll just list the IDs. A more advanced script would resolve them.
                    OWNER_UPNS+=("id:$owner_id")
                done
                OWNERS_FORMATTED=$(IFS='; '; echo "${OWNER_UPNS[*]}")
            else
                OWNERS_FORMATTED="No owners assigned"
            fi
        else
            OWNERS_FORMATTED="App object not found"
        fi
    fi

    # --- Get Last Sign-In Date ---
    # Note: This requires AuditLog.Read.All permissions.
    LAST_SIGN_IN="No sign-in found"
    SIGN_IN_JSON=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/auditLogs/signIns?\$filter=servicePrincipalId eq '$OBJECT_ID'&\$top=1" --header "Content-Type=application/json" 2>/dev/null || echo '{"value":[]}')
    LATEST_SIGN_IN_DT=$(echo "$SIGN_IN_JSON" | jq -r '.value[0].createdDateTime // ""')
    if [[ ! -z "$LATEST_SIGN_IN_DT" ]]; then
        LAST_SIGN_IN=$(echo "$LATEST_SIGN_IN_DT" | sed 's/T/ /;s/Z//')
    fi

    # --- Gather Credentials ---
    SECRET_EXPIRIES=$(echo "$sp" | jq -r 'if .passwordCredentials and (.passwordCredentials | length > 0) then [.passwordCredentials[].endDateTime | .[0:10]] | join("; ") else "None" end')
    CERT_EXPIRIES=$(echo "$sp" | jq -r 'if .keyCredentials and (.keyCredentials | length > 0) then [.keyCredentials[].endDateTime | .[0:10]] | join("; ") else "None" end')

    # --- Gather API Permissions (OAuth2 Grants) ---
    API_PERMS_JSON=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/${OBJECT_ID}/oauth2PermissionGrants" --header "Content-Type=application/json" 2>/dev/null || echo '{"value":[]}')
    API_PERMS_FORMATTED=$(echo "$API_PERMS_JSON" | jq -r 'if .value and (.value | length > 0) then [.value[] | "Resource: \(.resourceId) | Scope: \(.scope)"] | join("; ") else "None" end')

    # --- Gather App Role Assignments ---
    APP_ROLES_JSON=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/${OBJECT_ID}/appRoleAssignments" --header "Content-Type=application/json" 2>/dev/null || echo '{"value":[]}')
    APP_ROLES_FORMATTED=$(echo "$APP_ROLES_JSON" | jq -r 'if .value and (.value | length > 0) then [.value[] | "RoleId: \(.appRoleId) on Resource: \(.resourceDisplayName // .resourceId)"] | join("; ") else "None" end')

    # --- Sanitize for CSV ---
    # Function to remove commas and newlines to prevent CSV corruption
    sanitize() {
        echo "$1" | tr -d '\n\r' | tr ',' ';'
    }

    # --- Construct the CSV Row ---
    ROW="\"$(sanitize "$DISPLAY_NAME")\","
    ROW+="\"$(sanitize "$APP_ID")\","
    ROW+="\"$(sanitize "$OBJECT_ID")\","
    ROW+="\"$(sanitize "$SP_TYPE")\","
    ROW+="\"$(sanitize "$ACCOUNT_ENABLED")\","
    ROW+="\"$(sanitize "$CREATED_DT")\","
    ROW+="\"$(sanitize "$LAST_SIGN_IN")\","
    ROW+="\"$(sanitize "$OWNERS_FORMATTED")\","
    ROW+="\"$(sanitize "$SIGN_IN_AUDIENCE")\","
    ROW+="\"$(sanitize "$HOMEPAGE")\","
    ROW+="\"$(sanitize "$TAGS")\","
    ROW+="\"$(sanitize "$SECRET_EXPIRIES")\","
    ROW+="\"$(sanitize "$CERT_EXPIRIES")\","
    ROW+="\"$(sanitize "$API_PERMS_FORMATTED")\","
    ROW+="\"$(sanitize "$APP_ROLES_FORMATTED")\""

    echo "$ROW" >> "$FILENAME"

done

echo -e "\n\nExporting report to $FILENAME..."
echo "Report generation complete!"
