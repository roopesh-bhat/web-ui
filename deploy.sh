#!/bin/bash

# Deploy Evaluation Reports Web UI to ECS
set -e

# Configuration
PROJECT_NAME="reports-web-ui"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="${PROJECT_NAME}"
IMAGE_TAG="latest"
FULL_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "🚀 Deploying Evaluation Reports Web UI..."
echo "📋 Configuration:"
echo "   - Project: ${PROJECT_NAME}"
echo "   - AWS Region: ${AWS_REGION}"
echo "   - AWS Account: ${AWS_ACCOUNT_ID}"
echo "   - ECR Repository: ${ECR_REPOSITORY}"
echo "   - Image URI: ${FULL_IMAGE_URI}"
echo ""

# Step 1: Create ECR repository if it doesn't exist
echo "📦 Step 1: Setting up ECR repository..."
if ! aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "Creating ECR repository: ${ECR_REPOSITORY}"
    aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_REGION}
    echo "✅ ECR repository created!"
else
    echo "✅ ECR repository already exists!"
fi
echo ""

# Step 2: Build Docker image
echo "🔨 Step 2: Building Docker image..."
docker build --platform linux/amd64 -t ${ECR_REPOSITORY}:${IMAGE_TAG} .
echo "✅ Docker image built successfully!"
echo ""

# Step 3: Test Docker image locally
echo "🧪 Step 3: Testing Docker image locally..."
echo "Starting container on port 8081 (to avoid conflicts)..."

# Kill any existing container
docker stop reports-web-ui-test 2>/dev/null || true
docker rm reports-web-ui-test 2>/dev/null || true

# Start test container
docker run -d --name reports-web-ui-test -p 8081:8080 \
  -e AWS_DEFAULT_REGION=${AWS_REGION} \
  -e S3_BUCKET=agentix-evaluation-reports-dev \
  ${ECR_REPOSITORY}:${IMAGE_TAG}

# Wait for container to start
echo "⏳ Waiting for container to start..."
sleep 10

# Test health endpoint
echo "🏥 Testing health endpoint..."
if curl -f http://localhost:8081/health; then
    echo ""
    echo "✅ Health check passed!"
else
    echo ""
    echo "❌ Health check failed!"
    docker logs reports-web-ui-test
    docker stop reports-web-ui-test
    docker rm reports-web-ui-test
    exit 1
fi

# Cleanup test container
echo ""
echo "🧹 Cleaning up test container..."
docker stop reports-web-ui-test
docker rm reports-web-ui-test
echo "✅ Local testing completed successfully!"
echo ""

# Step 4: Login to ECR
echo "🔐 Step 4: Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
echo "✅ ECR login successful!"
echo ""

# Step 5: Tag and push image to ECR
echo "🏷️ Step 5: Tagging and pushing image to ECR..."
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${FULL_IMAGE_URI}
docker push ${FULL_IMAGE_URI}
echo "✅ Image pushed to ECR successfully!"
echo ""

echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Update your ECS service to use the new image:"
echo "   Image URI: ${FULL_IMAGE_URI}"
echo ""
echo "2. Environment variables to set in ECS:"
echo "   - S3_BUCKET=agentix-evaluation-reports-dev"
echo "   - AWS_REGION=${AWS_REGION}"
echo "   - PORT=8080"
echo ""
echo "3. Required IAM permissions:"
echo "   - s3:GetObject on the reports bucket"
echo "   - s3:ListBucket on the reports bucket"
echo ""
echo "4. Health check endpoint: /health"
echo "5. Application will be available on port 8080"
echo ""
echo "🌐 To test locally:"
echo "   docker run -p 8080:8080 -e S3_BUCKET=agentix-evaluation-reports-dev ${FULL_IMAGE_URI}"
echo ""
