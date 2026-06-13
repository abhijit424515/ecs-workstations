#!/bin/bash
# =============================================================================
# ECS Workstation — Build & Deploy
# =============================================================================
# One-shot script: builds the workstation image, pushes to ECR, registers the
# ECS task definition, and creates/updates the ECS service.
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
#   - ECR login done (aws ecr-public get-login-password ...)
#
# Environment variables (set before running):
#   HERMES_TELEGRAM_TOKEN  — Telegram bot token
#   DEEPSEEK_API_KEY       — Your DeepSeek API key
#   AWS_PROFILE            — AWS profile (default: personal)
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
WORKSTATION_DIR="$(cd "$(dirname "$0")" && pwd)/${WORKSTATION}"

if [ ! -d "${WORKSTATION_DIR}" ]; then
    echo "ERROR: Workstation directory not found at ${WORKSTATION_DIR}"
    echo "Create it first with the required files (Dockerfile, task-definition.json, etc.)"
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

# ---------------------------------------------------------------------------
# Validate required secrets
# ---------------------------------------------------------------------------
if [ -z "${HERMES_TELEGRAM_TOKEN:-}" ]; then
    echo "ERROR: HERMES_TELEGRAM_TOKEN is not set."
    echo "Get a token from @BotFather on Telegram and export it."
    exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    echo "ERROR: DEEPSEEK_API_KEY is not set."
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Login to ECR (Public)
# ---------------------------------------------------------------------------
echo "=== Logging into ECR Public ==="
aws ecr-public get-login-password --region us-east-1 --profile "${AWS_PROFILE}" \
    | docker login --username AWS --password-stdin public.ecr.aws

# ---------------------------------------------------------------------------
# Step 2: Create ECR repo if not exists
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
# Step 3: Build image
# ---------------------------------------------------------------------------
echo "=== Building ${ECR_REPO}:${TAG} ==="
docker build -t "${ECR_REPO}:${TAG}" -t "${ECR_REPO}:latest" .

# ---------------------------------------------------------------------------
# Step 4: Push to ECR
# ---------------------------------------------------------------------------
echo "=== Pushing to ECR ==="
docker push "${ECR_REPO}:${TAG}"
docker push "${ECR_REPO}:latest"

# ---------------------------------------------------------------------------
# Step 5: Prepare task definition (substitute WORKSTATION + env vars)
# ---------------------------------------------------------------------------
echo "=== Preparing task definition ==="
sed -e "s/WORKSTATION/${WORKSTATION}/g" \
    -e "s/IMAGE_TAG/${TAG}/g" \
    -e "s/TELEGRAM_BOT_TOKEN/${HERMES_TELEGRAM_TOKEN}/g" \
    -e "s/DEEPSEEK_API_KEY/${DEEPSEEK_API_KEY}/g" \
    "${TASK_DEF_FILE}" > /tmp/${WORKSTATION}-devcontainer-task-def.json

echo "Task definition written to /tmp/${WORKSTATION}-devcontainer-task-def.json"

# ---------------------------------------------------------------------------
# Step 6: Register task definition
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
# Step 7: Create or update ECS service
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
        --profile "${AWS_PROFILE}" \
        --output json
fi

echo ""
echo "=== Done ==="
echo "Workstation: ${WORKSTATION}"
echo "Service: ${SERVICE}"
echo "Task def: ${WORKSTATION}-devcontainer"
echo "Check status: aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --profile ${AWS_PROFILE}"
