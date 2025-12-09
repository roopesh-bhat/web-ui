# Evaluation Reports Web UI - Terraform Infrastructure

This directory contains Terraform configuration to deploy the Evaluation Reports Web UI on AWS ECS with Fargate.

## Architecture

- **ECS Fargate**: Serverless container hosting
- **Application Load Balancer**: Public endpoint with health checks
- **VPC**: Isolated network with public subnets
- **ECR**: Container registry for Docker images
- **IAM**: Secure S3 access for the application
- **CloudWatch**: Logging and monitoring

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **Docker** for building and pushing images
4. **S3 bucket** with evaluation reports (configured in variables)

## Quick Start

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables for your environment
nano terraform.tfvars
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

### 5. Build and Push Docker Image

After the infrastructure is deployed, you'll get an ECR repository URL. Use it to build and push your Docker image:

```bash
# Get the ECR repository URL from terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

# Build the image
docker build -t evaluation-reports-web-ui:latest .

# Tag for ECR
docker tag evaluation-reports-web-ui:latest $ECR_URL:latest

# Push to ECR
docker push $ECR_URL:latest
```

### 6. Update ECS Service

After pushing the image, update the ECS service to use the new image:

```bash
# Force new deployment
aws ecs update-service --cluster evaluation-reports-cluster --service evaluation-reports-web-ui-service --force-new-deployment
```

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for resources | `us-east-1` |
| `project_name` | Project name for resource naming | `evaluation-reports` |
| `s3_bucket_name` | S3 bucket with evaluation reports | `agentix-evaluation-reports-dev` |
| `task_cpu` | CPU units for ECS task | `512` |
| `task_memory` | Memory for ECS task (MB) | `1024` |
| `desired_count` | Number of service instances | `1` |

### S3 Bucket Requirements

The S3 bucket should contain evaluation reports with the following structure:
```
bucket-name/
├── channel1/
│   ├── 2024-01-15/
│   │   ├── report1.html
│   │   └── report1.json
│   └── 2024-01-16/
│       └── report2.html
└── channel2/
    └── 2024-01-15/
        └── report3.html
```

## Outputs

After deployment, you'll get:

- **Web UI URL**: Public URL to access the application
- **ECR Repository URL**: For pushing Docker images
- **ECS Cluster Name**: For managing the service
- **CloudWatch Log Group**: For viewing application logs

## Accessing the Application

1. **Get the URL**:
   ```bash
   terraform output web_ui_url
   ```

2. **Open in browser**: The URL will be something like `http://your-alb-dns-name`

## Monitoring and Logs

### CloudWatch Logs
```bash
# View application logs
aws logs tail /ecs/evaluation-reports-web-ui --follow
```

### ECS Service Status
```bash
# Check service status
aws ecs describe-services --cluster evaluation-reports-cluster --services evaluation-reports-web-ui-service
```

### Health Checks
The application includes health checks at `/health` endpoint.

## Scaling

### Horizontal Scaling
```bash
# Scale the service
aws ecs update-service --cluster evaluation-reports-cluster --service evaluation-reports-web-ui-service --desired-count 3
```

### Vertical Scaling
Update the `task_cpu` and `task_memory` variables and run `terraform apply`.

## Security

- **IAM Roles**: Least privilege access to S3 bucket
- **Security Groups**: Restricted network access
- **VPC**: Isolated network environment
- **HTTPS**: Can be added with ACM certificate

## Cost Optimization

- **Fargate Spot**: Can be enabled for cost savings
- **Auto Scaling**: Configure based on CPU/memory usage
- **Log Retention**: Set appropriate CloudWatch log retention

## Troubleshooting

### Common Issues

1. **Container won't start**: Check CloudWatch logs
2. **Health check failures**: Verify `/health` endpoint
3. **S3 access denied**: Check IAM permissions
4. **ALB not responding**: Check security group rules

### Debug Commands

```bash
# Check ECS service events
aws ecs describe-services --cluster evaluation-reports-cluster --services evaluation-reports-web-ui-service --query 'services[0].events'

# Check task definition
aws ecs describe-task-definition --task-definition evaluation-reports-web-ui

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw alb_target_group_arn)
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including the ECR repository and any stored images.

## Next Steps

1. **SSL Certificate**: Add ACM certificate for HTTPS
2. **Custom Domain**: Configure Route 53 for custom domain
3. **Auto Scaling**: Set up application auto scaling
4. **Monitoring**: Add CloudWatch alarms and dashboards
5. **CI/CD**: Set up automated deployment pipeline

