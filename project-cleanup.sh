#!/usr/bin/env bash
# cleanup-project2.sh - removes ONLY the AWS resources from the GitHub Actions OIDC project
#
#   ./cleanup-project2.sh             dry run (shows what would be deleted)
#   ./cleanup-project2.sh --execute   deletes the SSM parameter and the IAM role
#   add --include-oidc to also delete the GitHub OIDC identity provider

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="github-actions-oidc-aws-role"
PARAM_NAME="hello_aws-gh-oidc"
OIDC_HOST="token.actions.githubusercontent.com"

EXECUTE=0
INCLUDE_OIDC=0
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --include-oidc) INCLUDE_OIDC=1 ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || exit 1
echo "Account: $ACCOUNT_ID   Region: $REGION"

run() {
  if [ "$EXECUTE" -eq 1 ]; then
    echo "RUN: $*"
    "$@" || echo "  (failed or already gone)"
  else
    echo "DRY-RUN: $*"
  fi
}

if [ "$EXECUTE" -eq 1 ]; then
  read -r -p "Type the account ID to confirm deletion: " typed
  [ "$typed" = "$ACCOUNT_ID" ] || { echo "Mismatch. Aborting."; exit 1; }
fi

# 1. SSM parameter
run aws ssm delete-parameter --name "$PARAM_NAME" --region "$REGION"

# 2. IAM role: remove its policies first, then the role
for p in $(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text 2>/dev/null); do
  run aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$p"
done
for arn in $(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
  run aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$arn"
done
run aws iam delete-role --role-name "$ROLE_NAME"

# 3. OIDC provider (optional, other projects may reuse it)
if [ "$INCLUDE_OIDC" -eq 1 ]; then
  run aws iam delete-open-id-connect-provider \
    --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"
else
  echo "Skipping the OIDC provider. Add --include-oidc to delete it."
fi