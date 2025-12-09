#!/bin/bash

# Script to build and push Docker image to AWS ECR and deploy to ECS
# This script handles ECR login, image build, tag, push, and ECS deployment

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Web UI Build & Deploy to ECS${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY_NAME="${ECR_REPOSITORY_NAME:-evaluation-reports-web-ui}"
ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-evaluation-reports-cluster}"
ECS_SERVICE_NAME="${ECS_SERVICE_NAME:-evaluation-reports-web-ui-service}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Construct ECR URI
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}"

echo -e "${BLUE}Configuration:${NC}"
echo -e "  AWS Account ID: ${GREEN}${AWS_ACCOUNT_ID}${NC}"
echo -e "  AWS Region: ${GREEN}${AWS_REGION}${NC}"
echo -e "  ECR Repository: ${GREEN}${ECR_REPOSITORY_NAME}${NC}"
echo -e "  ECS Cluster: ${GREEN}${ECS_CLUSTER_NAME}${NC}"
echo -e "  ECS Service: ${GREEN}${ECS_SERVICE_NAME}${NC}"
echo -e "  Image Tag: ${GREEN}${IMAGE_TAG}${NC}"
echo -e "  Full ECR URI: ${GREEN}${ECR_URI}:${IMAGE_TAG}${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}Script directory: ${NC}$SCRIPT_DIR"
echo -e "${BLUE}Build context directory: ${NC}$(pwd)"
echo ""

# Step 1: Check if ECR repository exists, create if not
echo -e "${BLUE}Step 1: Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names "${ECR_REPOSITORY_NAME}" --region "${AWS_REGION}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ECR repository exists${NC}"
else
    echo -e "${YELLOW}⚠ ECR repository not found. Creating...${NC}"
    aws ecr create-repository \
        --repository-name "${ECR_REPOSITORY_NAME}" \
        --region "${AWS_REGION}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 > /dev/null
    echo -e "${GREEN}✓ ECR repository created${NC}"
fi
echo ""

# Step 2: Login to ECR
echo -e "${BLUE}Step 2: Logging in to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo -e "${GREEN}✓ Successfully logged in to ECR${NC}"
echo ""

# Step 3: Build Docker image
echo -e "${BLUE}Step 3: Building Docker image...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
echo -e "  Context: $(pwd)"
echo -e "  Dockerfile: ${SCRIPT_DIR}/Dockerfile"
echo ""

docker build --platform linux/amd64 \
    -f "${SCRIPT_DIR}/Dockerfile" \
    -t "${ECR_REPOSITORY_NAME}:${IMAGE_TAG}" \
    "${SCRIPT_DIR}"

echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

# Step 4: Tag image for ECR
echo -e "${BLUE}Step 4: Tagging image for ECR...${NC}"
docker tag "${ECR_REPOSITORY_NAME}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker tag "${ECR_REPOSITORY_NAME}:${IMAGE_TAG}" "${ECR_URI}:latest"
echo -e "${GREEN}✓ Image tagged: ${ECR_URI}:${IMAGE_TAG}${NC}"
echo ""

# Step 5: Push image to ECR
echo -e "${BLUE}Step 5: Pushing image to ECR...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
docker push "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:latest"
echo -e "${GREEN}✓ Image pushed successfully${NC}"
echo ""

# Step 6: Get image details
echo -e "${BLUE}Step 6: Verifying image in ECR...${NC}"
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" \
    --query 'imageDetails[0].imageDigest' \
    --output text)

IMAGE_SIZE=$(aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" \
    --query 'imageDetails[0].imageSizeInBytes' \
    --output text)

IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))

echo -e "${GREEN}✓ Image verified in ECR${NC}"
echo -e "  Digest: ${IMAGE_DIGEST}"
echo -e "  Size: ${IMAGE_SIZE_MB} MB"
echo ""

# Step 7: Check ECS service exists
echo -e "${BLUE}Step 7: Checking ECS service...${NC}"
if aws ecs describe-services --cluster "${ECS_CLUSTER_NAME}" --services "${ECS_SERVICE_NAME}" --region "${AWS_REGION}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ECS service exists${NC}"
else
    echo -e "${RED}✗ ECS service not found. Please run terraform apply first.${NC}"
    echo -e "${YELLOW}Run: cd ${SCRIPT_DIR}/terraform && terraform apply${NC}"
    exit 1
fi
echo ""

# Step 8: Update ECS service
echo -e "${BLUE}Step 8: Updating ECS service...${NC}"
echo -e "${YELLOW}This will trigger a new deployment...${NC}"

aws ecs update-service \
    --cluster "${ECS_CLUSTER_NAME}" \
    --service "${ECS_SERVICE_NAME}" \
    --force-new-deployment \
    --region "${AWS_REGION}" \
    --query 'service.{serviceName:serviceName,status:status,desiredCount:desiredCount,runningCount:runningCount}' \
    --output table

echo -e "${GREEN}✓ ECS service update initiated${NC}"
echo ""

# Step 9: Wait for deployment (optional)
echo -e "${BLUE}Step 9: Waiting for deployment to complete...${NC}"
echo -e "${YELLOW}This may take 3-5 minutes...${NC}"
echo -e "${YELLOW}You can monitor progress in the AWS ECS console${NC}"
echo ""

# Wait for service to be stable (with timeout)
if timeout 300 aws ecs wait services-stable \
    --cluster "${ECS_CLUSTER_NAME}" \
    --services "${ECS_SERVICE_NAME}" \
    --region "${AWS_REGION}" 2>/dev/null; then
    echo -e "${GREEN}✓ Deployment completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠ Deployment is taking longer than expected${NC}"
    echo -e "${YELLOW}Check the ECS console for more details${NC}"
fi
echo ""

# Step 10: Get Web UI URL
echo -e "${BLUE}Step 10: Getting Web UI URL...${NC}"
if [ -f "${SCRIPT_DIR}/terraform/terraform.tfstate" ]; then
    cd "${SCRIPT_DIR}/terraform"
    WEB_UI_URL=$(terraform output -raw web_ui_url 2>/dev/null || echo "")
    cd "${SCRIPT_DIR}"
    
    if [ -n "$WEB_UI_URL" ]; then
        echo -e "${GREEN}✓ Web UI URL found${NC}"
        echo ""
        echo -e "${BLUE}================================================${NC}"
        echo -e "${GREEN}🌐 Web UI URL:${NC}"
        echo -e "${YELLOW}${WEB_UI_URL}${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo ""
    else
        echo -e "${YELLOW}⚠ Could not get Web UI URL from Terraform${NC}"
        echo -e "${YELLOW}Check the ALB DNS name in the AWS console${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Terraform state not found${NC}"
    echo -e "${YELLOW}Run: cd ${SCRIPT_DIR}/terraform && terraform apply${NC}"
fi

# Summary
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✓ Build and Deploy Complete!${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${BLUE}Deployment Summary:${NC}"
echo -e "  Repository: ${GREEN}${ECR_REPOSITORY_NAME}${NC}"
echo -e "  Tag: ${GREEN}${IMAGE_TAG}${NC}"
echo -e "  Full URI: ${GREEN}${ECR_URI}:${IMAGE_TAG}${NC}"
echo -e "  Size: ${GREEN}${IMAGE_SIZE_MB} MB${NC}"
echo -e "  ECS Cluster: ${GREEN}${ECS_CLUSTER_NAME}${NC}"
echo -e "  ECS Service: ${GREEN}${ECS_SERVICE_NAME}${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Open the Web UI URL in your browser"
echo -e "  2. Check logs: ${YELLOW}aws logs tail /ecs/evaluation-reports-web-ui --follow --region ${AWS_REGION}${NC}"
echo -e "  3. Check service: ${YELLOW}aws ecs describe-services --cluster ${ECS_CLUSTER_NAME} --services ${ECS_SERVICE_NAME} --region ${AWS_REGION}${NC}"
echo ""