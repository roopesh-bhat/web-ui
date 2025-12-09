# Build and Deploy Script

This script automates the complete build and deployment process for the Evaluation Reports Web UI.

## What It Does

1. ✅ Checks all prerequisites (AWS CLI, Docker, Terraform)
2. ✅ Verifies AWS credentials
3. ✅ Sets up ECR repository (creates if needed)
4. ✅ Builds Docker image
5. ✅ Pushes image to ECR
6. ✅ Updates ECS service with new image
7. ✅ Waits for deployment to complete
8. ✅ Shows deployment summary with Web UI URL

## Prerequisites

Before running the script, ensure you have:

- **AWS CLI** configured with valid credentials
- **Docker** installed and running
- **Terraform** infrastructure already deployed (run `terraform apply` in the `terraform/` directory first)

## Usage

### Basic Usage

```bash
# Make the script executable (first time only)
chmod +x build_and_deploy.sh

# Run the deployment
./build_and_deploy.sh
```

### Advanced Options

```bash
# Skip waiting for deployment (faster, but won't verify completion)
./build_and_deploy.sh --skip-wait

# Skip building Docker image (use existing local image)
./build_and_deploy.sh --skip-build

# Clean up old images after deployment
./build_and_deploy.sh --cleanup

# Use a specific image tag
./build_and_deploy.sh --tag v1.0.0

# Combine options
./build_and_deploy.sh --tag v1.0.0 --cleanup --skip-wait

# Show help
./build_and_deploy.sh --help
```

## Complete Deployment Process

### First-Time Deployment

If you haven't deployed the infrastructure yet:

```bash
# Step 1: Deploy infrastructure with Terraform
cd terraform/
terraform init
terraform plan -out=tfplan
terraform apply tfplan
cd ..

# Step 2: Build and deploy the application
./build_and_deploy.sh
```

### Subsequent Deployments

For code updates after infrastructure is already deployed:

```bash
# Just run the build and deploy script
./build_and_deploy.sh
```

## What Gets Created/Updated

### ECR Repository
- **Name**: `evaluation-reports-web-ui`
- **Region**: `us-east-1`
- **Features**: Image scanning enabled

### Docker Image
- **Tags**: `latest` and custom tag (if specified)
- **Pushed to**: AWS ECR

### ECS Service
- **Cluster**: `evaluation-reports-cluster`
- **Service**: `evaluation-reports-web-ui-service`
- **Update**: Forces new deployment with latest image

## Script Options

| Option | Description |
|--------|-------------|
| `--skip-wait` | Don't wait for deployment to complete |
| `--skip-build` | Skip Docker build, use existing local image |
| `--cleanup` | Remove old images, keep 5 most recent |
| `--tag TAG` | Use custom image tag instead of `latest` |
| `--help` | Show help message |

## Output

The script provides colored output with:

- 🔵 **INFO**: General information
- 🟢 **SUCCESS**: Successful operations
- 🟡 **WARNING**: Non-critical issues
- 🔴 **ERROR**: Critical errors that stop execution

### Example Output

```
========================================
Evaluation Reports Web UI - Build and Deploy
========================================

[INFO] Checking prerequisites...
[SUCCESS] AWS Account ID: 497455650719
[SUCCESS] All prerequisites met!

========================================
Building Docker Image
========================================

[INFO] Building image: evaluation-reports-web-ui:latest
[SUCCESS] Docker image built successfully!

========================================
Pushing Image to ECR
========================================

[INFO] Logging in to ECR...
[INFO] Pushing image to ECR...
[SUCCESS] Image pushed to ECR

========================================
Deployment Summary
========================================

✓ Image: 497455650719.dkr.ecr.us-east-1.amazonaws.com/evaluation-reports-web-ui:latest
✓ ECS Cluster: evaluation-reports-cluster
✓ ECS Service: evaluation-reports-web-ui-service
✓ Desired Tasks: 1
✓ Running Tasks: 1

========================================
🌐 Web UI URL:
http://evaluation-reports-alb-1234567890.us-east-1.elb.amazonaws.com
========================================
```

## Troubleshooting

### AWS Credentials Error

```
[ERROR] AWS credentials not configured or expired.
```

**Solution**: Export fresh AWS credentials:
```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_SESSION_TOKEN="your-token"
```

### Docker Daemon Not Running

```
[ERROR] Docker daemon is not running.
```

**Solution**: Start Docker Desktop or the Docker daemon.

### ECS Cluster/Service Not Found

```
[ERROR] ECS cluster 'evaluation-reports-cluster' not found or not active.
```

**Solution**: Deploy infrastructure first:
```bash
cd terraform/
terraform apply
cd ..
./build_and_deploy.sh
```

### Build Failures

If the Docker build fails:
```bash
# Clean up Docker cache and rebuild
docker system prune -f
./build_and_deploy.sh
```

## Monitoring Deployment

### View Application Logs

```bash
aws logs tail /ecs/evaluation-reports-web-ui --follow --region us-east-1
```

### Check ECS Service Status

```bash
aws ecs describe-services \
  --cluster evaluation-reports-cluster \
  --services evaluation-reports-web-ui-service \
  --region us-east-1
```

### Check Running Tasks

```bash
aws ecs list-tasks \
  --cluster evaluation-reports-cluster \
  --service-name evaluation-reports-web-ui-service \
  --region us-east-1
```

## Manual Steps (if script fails)

If you need to run steps manually:

```bash
# 1. Get ECR URL
ECR_URL=$(aws ecr describe-repositories \
  --repository-names evaluation-reports-web-ui \
  --region us-east-1 \
  --query 'repositories[0].repositoryUri' \
  --output text)

# 2. Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# 3. Build image
docker build -t evaluation-reports-web-ui:latest .

# 4. Tag and push
docker tag evaluation-reports-web-ui:latest $ECR_URL:latest
docker push $ECR_URL:latest

# 5. Update ECS service
aws ecs update-service \
  --cluster evaluation-reports-cluster \
  --service evaluation-reports-web-ui-service \
  --force-new-deployment \
  --region us-east-1
```

## Performance Tips

### Faster Deployments

```bash
# Skip waiting for deployment to complete (saves 3-5 minutes)
./build_and_deploy.sh --skip-wait
```

### Incremental Builds

Docker uses layer caching, so subsequent builds are faster. To maximize caching:
- Don't modify `requirements.txt` unless necessary
- Make code changes before dependency changes

### Parallel Development

For local testing before deploying:
```bash
# Build and test locally first
docker build -t evaluation-reports-web-ui:latest .
docker run -d -p 8080:8080 \
  -e S3_BUCKET=agentix-evaluation-reports-dev \
  -e AWS_REGION=us-east-1 \
  evaluation-reports-web-ui:latest

# Test at http://localhost:8080
# Then deploy when satisfied
./build_and_deploy.sh
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Web UI

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Deploy
        run: |
          cd agentic-evals/infra/automatic_report_generator/web-ui
          ./build_and_deploy.sh --skip-wait --cleanup
```

## Cost Considerations

- **ECR Storage**: Charged per GB per month (~$0.10/GB)
- **ECR Data Transfer**: Free for same-region transfers
- **ECS Task**: Charged per vCPU and memory per second

**Tip**: Use `--cleanup` flag regularly to remove old images and save on ECR storage costs.

## Security Notes

- The script automatically logs in to ECR (temporary credentials)
- Images are scanned on push for vulnerabilities
- Only IAM roles with proper permissions can deploy
- Service uses least-privilege IAM roles for S3 access

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review CloudWatch logs: `aws logs tail /ecs/evaluation-reports-web-ui --follow`
3. Verify AWS credentials are valid: `aws sts get-caller-identity`
4. Ensure Docker is running: `docker info`
