#!/bin/bash

# Interactively configures the .env file for performance tests
# by discovering service URLs from the current OpenShift cluster.

set -e # Exit immediately on error.

echo "Verifying OpenShift connection..."
if ! command -v oc &> /dev/null; then
    echo "Error: 'oc' command not found. Please install the OpenShift CLI and add it to your PATH"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "Error: Not logged into an OpenShift cluster"
    echo "Please log in with 'oc login' and try again"
    exit 1
fi
echo "OpenShift connection verified"
echo ""

ENV_FILE=".env"
touch "$ENV_FILE"
echo "Configuring environment variables in '$ENV_FILE'..."
echo "---"

# Checks if a URL variable is set in .env; if not, discovers and sets it.
# $1: Variable name (e.g., OIDC_ISSUER_URL)
# $2: Discovery command (e.g., oc get route ...)
# $3: URL Prefix (optional)
# $4: URL Suffix (optional)
check_and_set_url() {
    local VAR_NAME=$1
    local DISCOVERY_CMD=$2
    local PREFIX=$3
    local SUFFIX=$4

    if grep -q "^export ${VAR_NAME}=" "$ENV_FILE"; then
        echo "${VAR_NAME} is already set, skipping discovery"
    else
        echo "Discovering ${VAR_NAME}..."
        # Subshell removes trailing newlines from the command output.
        local DISCOVERED_PART=$(eval "$DISCOVERY_CMD" 2>/dev/null | tr -d '\r\n')
        
        if [ -n "$DISCOVERED_PART" ]; then
            local FINAL_URL="${PREFIX}${DISCOVERED_PART}${SUFFIX}"
            echo "export ${VAR_NAME}=${FINAL_URL}" >> "$ENV_FILE"
            echo "${VAR_NAME} set"
        else
            echo "Error: Could not discover value for ${VAR_NAME}. Ensure you are logged into the correct OpenShift cluster"
            exit 1
        fi
    fi
}

# Checks if a credential is set in .env; if not, prompts the user for it.
# $1: Variable name
# $2: Prompt text for the user
# $3: 'true' if the input is secret (optional)
check_and_set_credential() {
    local VAR_NAME=$1
    local PROMPT_TEXT=$2
    local IS_SECRET=${3:-false}

    if grep -q "^export ${VAR_NAME}=" "$ENV_FILE"; then
        echo "${VAR_NAME} is already set"
    else
        if [ "$IS_SECRET" = true ]; then
            read -sp "Enter ${PROMPT_TEXT}: " USER_INPUT
            echo ""
        else
            read -p "Enter ${PROMPT_TEXT}: " USER_INPUT
        fi
        echo "export ${VAR_NAME}=${USER_INPUT}" >> "$ENV_FILE"
    fi
}

# Discover service URLs from the OpenShift cluster.
check_and_set_url "FULCIO_URL" "oc get fulcio -o jsonpath='{.items[0].status.url}'"
check_and_set_url "REKOR_URL" "oc get rekor -o jsonpath='{.items[0].status.url}'"
check_and_set_url "OIDC_ISSUER_URL" "oc get route keycloak -n keycloak-system --no-headers | awk '{print \$2}'" "https://" "/auth/realms/trusted-artifact-signer"
check_and_set_url "TSA_URL" "oc get timestampauthorities -o jsonpath='{.items[0].status.url}'" "" "/api/v1/timestamp"


# Set the static OIDC client ID if not already present.
if ! grep -q "^export OIDC_CLIENT_ID=" "$ENV_FILE"; then
    echo "export OIDC_CLIENT_ID=trusted-artifact-signer" >> "$ENV_FILE"
fi
echo "OIDC_CLIENT_ID set"

# Prompt for user-specific credentials.
check_and_set_credential "OIDC_USER" "OIDC Username"
check_and_set_credential "OIDC_PASSWORD" "OIDC Password" true

echo "---"
echo "Configuration complete. Review '$ENV_FILE' to verify the settings"
