#!/usr/bin/env bash

# ============================================================
# AWS IAM Enumeration Script
#
# Usage:
#   ./aws_enum.sh <AWS_PROFILE>
#
# Example:
#   ./aws_enum.sh ctf
# ============================================================

set -uo pipefail

# ------------------------------------------------------------
# Check arguments
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo
    echo "Usage: $0 <AWS_PROFILE>"
    echo
    echo "Example:"
    echo "  $0 ctf"
    echo
    exit 1
fi

PROFILE="$1"

# ------------------------------------------------------------
# AWS command wrapper
# ------------------------------------------------------------

aws_cmd() {
    aws --profile "$PROFILE" "$@"
}

# ------------------------------------------------------------
# Check AWS CLI
# ------------------------------------------------------------

if ! command -v aws >/dev/null 2>&1; then
    echo "[-] AWS CLI is not installed."
    exit 1
fi

# ------------------------------------------------------------
# Check profile
# ------------------------------------------------------------

if ! aws configure list-profiles 2>/dev/null | grep -Fxq "$PROFILE"; then
    echo "[-] AWS profile '$PROFILE' was not found."
    echo
    echo "Available profiles:"
    aws configure list-profiles 2>/dev/null
    exit 1
fi

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                 AWS IAM ENUMERATION"
echo "============================================================"
echo "[+] AWS Profile : $PROFILE"
echo "============================================================"


# ============================================================
# 1. STS - Caller Identity
# ============================================================

echo
echo "[1] aws sts get-caller-identity"
echo "------------------------------------------------------------"

CALLER_IDENTITY=$(aws_cmd sts get-caller-identity 2>&1)

echo "$CALLER_IDENTITY"


# ============================================================
# 2. IAM Get User
# ============================================================

echo
echo "[2] aws iam get-user"
echo "------------------------------------------------------------"

USER_OUTPUT=$(aws_cmd iam get-user 2>&1)

echo "$USER_OUTPUT"

USERNAME=$(printf '%s\n' "$USER_OUTPUT" |
    awk -F'"UserName": "' 'NF>1 {split($2,a,"\""); print a[1]; exit}')

USER_ARN=$(printf '%s\n' "$USER_OUTPUT" |
    awk -F'"Arn": "' 'NF>1 {split($2,a,"\""); print a[1]; exit}')

if [[ -n "${USERNAME:-}" ]]; then
    echo
    echo "[+] IAM Username : $USERNAME"
    echo "[+] IAM User ARN : $USER_ARN"
else
    echo
    echo "[!] IAM username could not be determined."
    echo "[!] Credentials may represent an assumed role."
fi


# ============================================================
# 3. List Users
# ============================================================

echo
echo "[3] aws iam list-users"
echo "------------------------------------------------------------"

USERS_OUTPUT=$(aws_cmd iam list-users 2>&1)

echo "$USERS_OUTPUT"


# ============================================================
# 4. List Groups
# ============================================================

echo
echo "[4] aws iam list-groups"
echo "------------------------------------------------------------"

GROUPS_OUTPUT=$(aws_cmd iam list-groups 2>&1)

echo "$GROUPS_OUTPUT"


# ============================================================
# Extract ALL GROUP NAMES
# ============================================================

mapfile -t GROUP_NAMES < <(
    printf '%s\n' "$GROUPS_OUTPUT" |
    grep -o '"GroupName": "[^"]*"' |
    sed 's/"GroupName": "//;s/"$//' |
    sort -u
)

echo
echo "[+] Groups discovered: ${#GROUP_NAMES[@]}"

if [[ ${#GROUP_NAMES[@]} -gt 0 ]]; then
    for GROUPNAME in "${GROUP_NAMES[@]}"; do
        echo "    -> $GROUPNAME"
    done
else
    echo "    -> No groups discovered."
fi


# ============================================================
# 5. List Roles
# ============================================================

echo
echo "[5] aws iam list-roles"
echo "------------------------------------------------------------"

ROLES_OUTPUT=$(aws_cmd iam list-roles 2>&1)

echo "$ROLES_OUTPUT"


# ============================================================
# Extract ALL ROLE NAMES
# ============================================================

mapfile -t ROLE_NAMES < <(
    printf '%s\n' "$ROLES_OUTPUT" |
    grep -o '"RoleName": "[^"]*"' |
    sed 's/"RoleName": "//;s/"$//' |
    sort -u
)

echo
echo "[+] Roles discovered: ${#ROLE_NAMES[@]}"

if [[ ${#ROLE_NAMES[@]} -gt 0 ]]; then
    for ROLE_NAME in "${ROLE_NAMES[@]}"; do
        echo "    -> $ROLE_NAME"
    done
else
    echo "    -> No roles discovered."
fi


# ============================================================
# 6. List Local Policies
# ============================================================

echo
echo "[6] aws iam list-policies --scope Local"
echo "------------------------------------------------------------"

POLICIES_OUTPUT=$(aws_cmd iam list-policies --scope Local 2>&1)

echo "$POLICIES_OUTPUT"


# ============================================================
# Extract ALL Local Policy ARNs
# ============================================================

mapfile -t POLICY_ARNS < <(
    printf '%s\n' "$POLICIES_OUTPUT" |
    grep -o '"Arn": "[^"]*"' |
    sed 's/"Arn": "//;s/"$//' |
    grep ':policy/' |
    sort -u
)

echo
echo "[+] Local policies discovered: ${#POLICY_ARNS[@]}"

if [[ ${#POLICY_ARNS[@]} -gt 0 ]]; then
    for POLICY_ARN in "${POLICY_ARNS[@]}"; do
        echo "    -> $POLICY_ARN"
    done
else
    echo "    -> No local policies discovered."
fi


# ============================================================
# 7. Current User Groups
# ============================================================

if [[ -n "${USERNAME:-}" ]]; then

    echo
    echo "[7] aws iam list-groups-for-user --user-name $USERNAME"
    echo "------------------------------------------------------------"

    USER_GROUPS_OUTPUT=$(aws_cmd iam list-groups-for-user \
        --user-name "$USERNAME" 2>&1)

    echo "$USER_GROUPS_OUTPUT"

else

    echo
    echo "[7] list-groups-for-user"
    echo "------------------------------------------------------------"
    echo "[!] Skipped because IAM username was not identified."

fi


# ============================================================
# 8. Enumerate EVERY GROUP
# ============================================================

echo
echo "============================================================"
echo "              GROUP ENUMERATION"
echo "============================================================"

for GROUPNAME in "${GROUP_NAMES[@]}"; do

    echo
    echo "############################################################"
    echo "# GROUP: $GROUPNAME"
    echo "############################################################"


    # --------------------------------------------------------
    # Attached Group Policies
    # --------------------------------------------------------

    echo
    echo "[+] aws iam list-attached-group-policies"
    echo "------------------------------------------------------------"

    ATTACHED_GROUP_OUTPUT=$(aws_cmd iam list-attached-group-policies \
        --group-name "$GROUPNAME" 2>&1)

    echo "$ATTACHED_GROUP_OUTPUT"


    # --------------------------------------------------------
    # Inline Group Policies
    # --------------------------------------------------------

    echo
    echo "[+] aws iam list-group-policies"
    echo "------------------------------------------------------------"

    INLINE_GROUP_OUTPUT=$(aws_cmd iam list-group-policies \
        --group-name "$GROUPNAME" 2>&1)

    echo "$INLINE_GROUP_OUTPUT"

done


# ============================================================
# 9. Current User Policies
# ============================================================

if [[ -n "${USERNAME:-}" ]]; then

    echo
    echo "============================================================"
    echo "              USER ENUMERATION"
    echo "============================================================"

    echo
    echo "[+] aws iam list-attached-user-policies"
    echo "------------------------------------------------------------"

    ATTACHED_USER_OUTPUT=$(aws_cmd iam list-attached-user-policies \
        --user-name "$USERNAME" 2>&1)

    echo "$ATTACHED_USER_OUTPUT"


    echo
    echo "[+] aws iam list-user-policies"
    echo "------------------------------------------------------------"

    INLINE_USER_OUTPUT=$(aws_cmd iam list-user-policies \
        --user-name "$USERNAME" 2>&1)

    echo "$INLINE_USER_OUTPUT"

else

    echo
    echo "============================================================"
    echo "              USER ENUMERATION"
    echo "============================================================"

    echo "[!] User policy enumeration skipped."
    echo "[!] Current credentials are not identified as an IAM user."

fi


# ============================================================
# 10. Enumerate Local Policies
# ============================================================

echo
echo "============================================================"
echo "              POLICY ENUMERATION"
echo "============================================================"

for POLICY_ARN in "${POLICY_ARNS[@]}"; do

    echo
    echo "############################################################"
    echo "# POLICY: $POLICY_ARN"
    echo "############################################################"

    # --------------------------------------------------------
    # Get Policy
    # --------------------------------------------------------

    echo
    echo "[+] aws iam get-policy"
    echo "------------------------------------------------------------"

    POLICY_OUTPUT=$(aws_cmd iam get-policy \
        --policy-arn "$POLICY_ARN" 2>&1)

    echo "$POLICY_OUTPUT"


    # --------------------------------------------------------
    # Extract DefaultVersionId
    # --------------------------------------------------------

    VERSION_ID=$(printf '%s\n' "$POLICY_OUTPUT" |
        grep -o '"DefaultVersionId": "[^"]*"' |
        sed 's/"DefaultVersionId": "//;s/"$//' |
        head -n 1)


    # --------------------------------------------------------
    # Extract Policy Name
    # --------------------------------------------------------

    POLICY_NAME=$(printf '%s\n' "$POLICY_OUTPUT" |
        grep -o '"PolicyName": "[^"]*"' |
        sed 's/"PolicyName": "//;s/"$//' |
        head -n 1)


    echo
    echo "[+] Policy Name : ${POLICY_NAME:-Unknown}"
    echo "[+] Policy ARN  : $POLICY_ARN"
    echo "[+] Version ID  : ${VERSION_ID:-Unknown}"


    # --------------------------------------------------------
    # Get Policy Version
    # --------------------------------------------------------

    if [[ -n "${VERSION_ID:-}" ]]; then

        echo
        echo "[+] aws iam get-policy-version"
        echo "------------------------------------------------------------"

        aws_cmd iam get-policy-version \
            --policy-arn "$POLICY_ARN" \
            --version-id "$VERSION_ID"

    else

        echo
        echo "[!] Default policy version could not be identified."

    fi

done


# ============================================================
# 11. Enumerate EVERY ROLE
# ============================================================

echo
echo "============================================================"
echo "              ROLE ENUMERATION"
echo "============================================================"

for ROLE_NAME in "${ROLE_NAMES[@]}"; do

    echo
    echo "############################################################"
    echo "# ROLE: $ROLE_NAME"
    echo "############################################################"


    # --------------------------------------------------------
    # Get Role
    # --------------------------------------------------------

    echo
    echo "[+] aws iam get-role --role-name $ROLE_NAME"
    echo "------------------------------------------------------------"

    aws_cmd iam get-role \
        --role-name "$ROLE_NAME"


    # --------------------------------------------------------
    # Attached Role Policies
    # --------------------------------------------------------

    echo
    echo "[+] aws iam list-attached-role-policies"
    echo "------------------------------------------------------------"

    ROLE_ATTACHED_OUTPUT=$(aws_cmd iam list-attached-role-policies \
        --role-name "$ROLE_NAME" 2>&1)

    echo "$ROLE_ATTACHED_OUTPUT"


    # --------------------------------------------------------
    # Inline Role Policies
    # --------------------------------------------------------

    echo
    echo "[+] aws iam list-role-policies"
    echo "------------------------------------------------------------"

    ROLE_INLINE_OUTPUT=$(aws_cmd iam list-role-policies \
        --role-name "$ROLE_NAME" 2>&1)

    echo "$ROLE_INLINE_OUTPUT"

done


# ============================================================
# Finished
# ============================================================

echo
echo
echo "============================================================"
echo "              ENUMERATION COMPLETED"
echo "============================================================"
echo "[+] Profile : $PROFILE"
echo "[+] Groups  : ${#GROUP_NAMES[@]}"
echo "[+] Roles   : ${#ROLE_NAMES[@]}"
echo "[+] Policies: ${#POLICY_ARNS[@]}"
echo "============================================================"
