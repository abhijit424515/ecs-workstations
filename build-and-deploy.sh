#!/bin/bash
# =============================================================================
# ECS Workstation — Build & Deploy
# =============================================================================
# One-shot script: decrypts secrets, writes them to EBS, builds the image,
# pushes to ECR, registers the ECS task definition, and deploys the service.
#
# Usage:
#   ./build-and-deploy.sh <workstation>
#
# Examples:
#   ./build-and-deploy.sh personal
#   ./build-and-deploy.sh work
#
# Prerequisites:
#   - AWS CLI logged in (correct profile)
#   - Docker running
#   - SOPS installed + KMS key access
#   - ECR login done (aws ecr-public get-login-password ...)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse workstation name
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <workstation>"
    echo ""
    echo "Examples:"
    echo "  $0 personal"
    echo "  $0 work"
    exit 1
fi

WORKSTATION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSTATION_DIR="${SCRIPT_DIR}/${WORKSTATION}"
SECRETS_FILE="${WORKSTATION_DIR}/secrets.yaml.sops"

if [ ! -d "${WORKSTATION_DIR}" ]; then
    echo "ERROR: Workstation directory not found at ${WORKSTATION_DIR}"
    echo "Create it first with the required files (Dockerfile, task-definition.json, etc.)"
    exit 1
fi

if [ ! -f "${SECRETS_FILE}" ]; then
    echo "ERROR: Encrypted secrets file not found at ${SECRETS_FILE}"
    echo "Create it with: cd ${WORKSTATION_DIR} && sops --encrypt secrets.yaml > secrets.yaml.sops"
    exit 1
fi

cd "${WORKSTATION_DIR}"

# ---------------------------------------------------------------------------
# Config (derived from workstation name)
# ---------------------------------------------------------------------------
ECR_REPO="public.ecr.aws/l0b6e2f4/${WORKSTATION}-devcontainer"
CLUSTER="aegis-cluster"
SERVICE="${WORKSTATION}-devcontainer"
TAG="$(date +%Y%m%d%H%M%S)"
TASK_DEF_FILE="task-definition.json"
AWS_PROFILE="${AWS_PROFILE:-personal}"
EC2_INSTANCE="i-015b311587953daad"
WORKSTATION_PATH="${WORKSTATION_PATH:-/mnt/workstations/${WORKSTATION}}"

# ---------------------------------------------------------------------------
# Step 1: Decrypt secrets and write to EBS
# ---------------------------------------------------------------------------
echo "=== Decrypting secrets ==="
SECRETS_JSON=$(sops -d --input-type yaml --output-type json "${SECRETS_FILE}" 2>/dev/null)

HERMES_ENV=$(echo "${SECRETS_JSON}" | jq -r '.hermes_env')
HERMES_ENV_SEP=$(echo "${SECRETS_JSON}" | jq -r '.hermes_env_separator')
AWS_CREDS=$(echo "${SECRETS_JSON}" | jq -r '.aws_credentials')
GITHUB_CONFIG=$(echo "${SECRETS_JSON}" | jq -r '.github // ""')

echo "=== Writing secrets to EBS ==="

# Base64 encode to avoid escaping issues in SSM
ENV_B64=$(echo -n "${HERMES_ENV}" | base64)
SEP_B64=$(echo -n "${HERMES_ENV_SEP}" | base64)
CREDS_B64=$(echo -n "${AWS_CREDS}" | base64)
GH_B64=$(echo -n "${GITHUB_CONFIG}" | base64)
# config.yaml is image-independent now: written to EBS so edits land without a rebuild
CONFIG_B64=$(base64 < config.yaml | tr -d '\n')

# Upload write-secrets.py to EC2 and execute it
SCRIPT_PATH="${SCRIPT_DIR}/personal/scripts/write-secrets.py"
SCRIPT_B64=$(base64 < "${SCRIPT_PATH}" | tr -d '\n')

aws ssm send-command \
    --instance-ids "${EC2_INSTANCE}" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[
        \"printf '%s' '${SCRIPT_B64}' | base64 -d > /tmp/write-secrets.py\",
        \"python3 /tmp/write-secrets.py '${ENV_B64}' '${SEP_B64}' '${CREDS_B64}' '${GH_B64}' '${WORKSTATION_PATH}' '${CONFIG_B64}'\",
        \"rm /tmp/write-secrets.py\"
    ]" \
    --region ap-south-1 \
    --profile "${AWS_PROFILE}" \
    --output json > /dev/null

echo "Secrets written to EBS."

# ---------------------------------------------------------------------------
# Step 2: Login to ECR (Public)
# ---------------------------------------------------------------------------
echo "=== Logging into ECR Public ==="
aws ecr-public get-login-password --region us-east-1 --profile "${AWS_PROFILE}" \
    | docker login --username AWS --password-stdin public.ecr.aws

# ---------------------------------------------------------------------------
# Step 3: Create ECR repo if not exists
# ---------------------------------------------------------------------------
echo "=== Ensuring ECR repo exists ==="
aws ecr-public describe-repositories \
    --repository-names "${WORKSTATION}-devcontainer" \
    --region us-east-1 \
    --profile "${AWS_PROFILE}" 2>/dev/null \
    || aws ecr-public create-repository \
        --repository-name "${WORKSTATION}-devcontainer" \
        --region us-east-1 \
        --profile "${AWS_PROFILE}" \
        --catalog-data "{\"description\":\"${WORKSTATION} remote workstation — Hermes devcontainer\"}" \
        --output json

# ---------------------------------------------------------------------------
# Step 4: Build image
# ---------------------------------------------------------------------------
echo "=== Building ${ECR_REPO}:${TAG} ==="
docker build -t "${ECR_REPO}:${TAG}" -t "${ECR_REPO}:latest" .

# ---------------------------------------------------------------------------
# Step 5: Push to ECR
# ---------------------------------------------------------------------------
echo "=== Pushing to ECR ==="
docker push "${ECR_REPO}:${TAG}"
docker push "${ECR_REPO}:latest"

# ---------------------------------------------------------------------------
# Step 6: Prepare task definition (substitute WORKSTATION + IMAGE_TAG)
# ---------------------------------------------------------------------------
echo "=== Preparing task definition ==="
sed -e "s|WORKSTATION_PATH|${WORKSTATION_PATH}|g" \
    -e "s|WORKSTATION|${WORKSTATION}|g" \
    -e "s/IMAGE_TAG/${TAG}/g" \
    "${TASK_DEF_FILE}" > /tmp/${WORKSTATION}-devcontainer-task-def.json

echo "Task definition written to /tmp/${WORKSTATION}-devcontainer-task-def.json"

# ---------------------------------------------------------------------------
# Step 7: Register task definition
# ---------------------------------------------------------------------------
echo "=== Registering task definition ==="
aws ecs register-task-definition \
    --cli-input-json file:///tmp/${WORKSTATION}-devcontainer-task-def.json \
    --profile "${AWS_PROFILE}" \
    --output json

TASK_DEF_ARN=$(aws ecs describe-task-definition \
    --task-definition "${WORKSTATION}-devcontainer" \
    --profile "${AWS_PROFILE}" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)
echo "Registered: ${TASK_DEF_ARN}"

# ---------------------------------------------------------------------------
# Step 8: Create or update ECS service
# ---------------------------------------------------------------------------
echo "=== Checking for existing service ==="
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --profile "${AWS_PROFILE}" \
    --query 'services[0].status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${SERVICE_EXISTS}" = "ACTIVE" ]; then
    echo "Service '${SERVICE}' exists — updating..."
    aws ecs update-service \
        --cluster "${CLUSTER}" \
        --service "${SERVICE}" \
        --task-definition "${WORKSTATION}-devcontainer" \
        --enable-execute-command \
        --force-new-deployment \
        --profile "${AWS_PROFILE}" \
        --output json
else
    echo "Creating service '${SERVICE}'..."
    aws ecs create-service \
        --cluster "${CLUSTER}" \
        --service-name "${SERVICE}" \
        --task-definition "${WORKSTATION}-devcontainer" \
        --desired-count 1 \
        --launch-type EC2 \
        --enable-execute-command \
        --profile "${AWS_PROFILE}" \
        --output json
fi

echo ""
echo "=== Done ==="
echo "Workstation: ${WORKSTATION}"
echo "Service: ${SERVICE}"
echo "Task def: ${WORKSTATION}-devcontainer"
echo "Check status: aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --profile ${AWS_PROFILE}"
