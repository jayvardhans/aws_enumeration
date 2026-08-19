#!/usr/bin/env bash
set -uo pipefail

# AWS IAM enumeration for authorized CTF/lab environments.
# Usage: ./iam-enum.sh <aws-profile>

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <aws-profile>"
    exit 1
fi

PROFILE="$1"

command -v aws >/dev/null 2>&1 || {
    echo "[!] AWS CLI is required."
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "[!] jq is required. Install with: sudo apt install jq"
    exit 1
}

run_aws() {
    echo
    echo "------------------------------------------------------------"
    echo "[+] $*"
    echo "------------------------------------------------------------"
    "$@"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[!] Command failed with exit code: $rc"
    fi
    return 0
}

echo "============================================================"
echo "[+] AWS IAM Enumeration"
echo "[+] Profile: $PROFILE"
echo "============================================================"

CALLER=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo "[!] Unable to authenticate with AWS profile: $PROFILE"
    exit 1
fi

echo
echo "[+] aws sts get-caller-identity"
echo "$CALLER"

ACCOUNT_ID=$(jq -r '.Account // empty' <<<"$CALLER")
CALLER_ARN=$(jq -r '.Arn // empty' <<<"$CALLER")

USER_OUTPUT=$(aws iam get-user --profile "$PROFILE" 2>/dev/null || true)

echo
echo "[+] aws iam get-user"
echo "$USER_OUTPUT"

USERNAME=$(jq -r '.User.UserName // empty' <<<"$USER_OUTPUT" 2>/dev/null)

# If get-user is unavailable, derive the IAM username from an IAM-user ARN.
if [[ -z "$USERNAME" && "$CALLER_ARN" == arn:aws:iam::*:user/* ]]; then
    USERNAME="${CALLER_ARN##*/}"
fi

echo
echo "[+] Username: ${USERNAME:-Unknown}"

# ------------------------------------------------------------
# Basic enumeration
# ------------------------------------------------------------

run_aws aws iam list-users --profile "$PROFILE"

GROUP_OUTPUT=$(aws iam list-groups --profile "$PROFILE" 2>/dev/null || true)
echo
echo "[+] aws iam list-groups"
echo "$GROUP_OUTPUT"

ROLE_OUTPUT=$(aws iam list-roles --profile "$PROFILE" 2>/dev/null || true)
echo
echo "[+] aws iam list-roles"
echo "$ROLE_OUTPUT"

POLICY_OUTPUT=$(aws iam list-policies --scope Local --profile "$PROFILE" 2>/dev/null || true)
echo
echo "[+] aws iam list-policies --scope Local"
echo "$POLICY_OUTPUT"

# ------------------------------------------------------------
# Current user
# ------------------------------------------------------------

if [[ -n "$USERNAME" ]]; then
    run_aws aws iam list-groups-for-user \
        --user-name "$USERNAME" \
        --profile "$PROFILE"

    run_aws aws iam list-attached-user-policies \
        --user-name "$USERNAME" \
        --profile "$PROFILE"

    run_aws aws iam list-user-policies \
        --user-name "$USERNAME" \
        --profile "$PROFILE"

    run_aws aws iam list-access-keys \
        --user-name "$USERNAME" \
        --profile "$PROFILE"
else
    echo "[!] Username could not be determined; skipping user-specific commands."
fi

# ------------------------------------------------------------
# Groups
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[+] GROUP ENUMERATION"
echo "============================================================"

while IFS= read -r GROUPNAME; do
    [[ -z "$GROUPNAME" ]] && continue

    echo
    echo "############################################################"
    echo "[+] GROUP: $GROUPNAME"
    echo "############################################################"

    run_aws aws iam list-attached-group-policies \
        --group-name "$GROUPNAME" \
        --profile "$PROFILE"

    # IMPORTANT:
    # list-group-policies returns PolicyNames[]. Each name is then
    # paired with the current GROUPNAME for get-group-policy.
    GROUP_POLICY_OUTPUT=$(aws iam list-group-policies \
        --group-name "$GROUPNAME" \
        --profile "$PROFILE" 2>/dev/null || true)

    echo
    echo "[+] aws iam list-group-policies --group-name $GROUPNAME"
    echo "$GROUP_POLICY_OUTPUT"

    while IFS= read -r POLICYNAME; do
        [[ -z "$POLICYNAME" ]] && continue

        echo
        echo "****************************************************"
        echo "[+] Inline Group Policy"
        echo "[+] Group : $GROUPNAME"
        echo "[+] Policy: $POLICYNAME"
        echo "****************************************************"

        run_aws aws iam get-group-policy \
            --group-name "$GROUPNAME" \
            --policy-name "$POLICYNAME" \
            --profile "$PROFILE"
    done < <(jq -r '.PolicyNames[]?' <<<"$GROUP_POLICY_OUTPUT" 2>/dev/null)

done < <(jq -r '.Groups[]?.GroupName' <<<"$GROUP_OUTPUT" 2>/dev/null)

# ------------------------------------------------------------
# Roles
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[+] ROLE ENUMERATION"
echo "============================================================"

while IFS= read -r ROLE_NAME; do
    [[ -z "$ROLE_NAME" ]] && continue

    echo
    echo "############################################################"
    echo "[+] ROLE: $ROLE_NAME"
    echo "############################################################"

    run_aws aws iam get-role \
        --role-name "$ROLE_NAME" \
        --profile "$PROFILE"

    run_aws aws iam list-attached-role-policies \
        --role-name "$ROLE_NAME" \
        --profile "$PROFILE"

    run_aws aws iam list-role-policies \
        --role-name "$ROLE_NAME" \
        --profile "$PROFILE"

done < <(jq -r '.Roles[]?.RoleName' <<<"$ROLE_OUTPUT" 2>/dev/null)

# ------------------------------------------------------------
# Local policies
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[+] POLICY ENUMERATION"
echo "============================================================"

while IFS= read -r POLICY_ARN; do
    [[ -z "$POLICY_ARN" ]] && continue

    echo
    echo "############################################################"
    echo "[+] POLICY: $POLICY_ARN"
    echo "############################################################"

    POLICY_DETAILS=$(aws iam get-policy \
        --policy-arn "$POLICY_ARN" \
        --profile "$PROFILE" 2>/dev/null || true)

    echo
    echo "[+] aws iam get-policy"
    echo "$POLICY_DETAILS"

    # Automatically obtain DefaultVersionId from get-policy.
    VERSION=$(jq -r '.Policy.DefaultVersionId // empty' \
        <<<"$POLICY_DETAILS" 2>/dev/null)

    if [[ -n "$VERSION" ]]; then
        echo
        echo "[+] Default policy version: $VERSION"

        run_aws aws iam get-policy-version \
            --policy-arn "$POLICY_ARN" \
            --version-id "$VERSION" \
            --profile "$PROFILE"
    else
        echo "[!] Default policy version could not be determined."
    fi

done < <(jq -r '.Policies[]?.Arn' <<<"$POLICY_OUTPUT" 2>/dev/null)

echo
echo "============================================================"
echo "[+] IAM ENUMERATION COMPLETE"
echo "============================================================"
echo "[+] Profile : $PROFILE"
echo "[+] Account : ${ACCOUNT_ID:-Unknown}"
echo "[+] User    : ${USERNAME:-Unknown}"
echo "============================================================"
