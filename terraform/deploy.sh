#!/bin/bash

# Evaluation Reports Web UI - Deployment Script
# This script automates the deployment process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check if aws cli is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "All prerequisites met!"
}

# Initialize terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    print_success "Terraform initialized!"
}

# Plan terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    print_success "Terraform plan created!"
}

# Apply terraform
apply_terraform() {
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    print_success "Infrastructure deployed!"
}

# Get ECR repository URL
get_ecr_url() {
    ECR_URL=$(terraform output -raw ecr_repository_url)
    print_status "ECR Repository URL: $ECR_URL"
}

# Login to ECR
login_ecr() {
    print_status "Logging in to ECR..."
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
    print_success "Logged in to ECR!"
}

# Build Docker image
build_image() {
    print_status "Building Docker image..."
    cd ..
    docker build -t evaluation-reports-web-ui:latest .
    print_success "Docker image built!"
}

# Tag and push image
push_image() {
    print_status "Tagging and pushing image to ECR..."
    docker tag evaluation-reports-web-ui:latest $ECR_URL:latest
    docker push $ECR_URL:latest
    print_success "Image pushed to ECR!"
}

# Update ECS service
update_ecs_service() {
    print_status "Updating ECS service with new image..."
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(terraform output -raw ecs_service_name)
    
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force-new-deployment \
        --query 'service.{serviceName:serviceName,status:status,desiredCount:desiredCount,runningCount:runningCount}' \
        --output table
    
    print_success "ECS service updated!"
}

# Wait for service to be stable
wait_for_service() {
    print_status "Waiting for ECS service to be stable..."
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(terraform output -raw ecs_service_name)
    
    aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME
    print_success "ECS service is stable!"
}

# Get application URL
get_app_url() {
    APP_URL=$(terraform output -raw web_ui_url)
    print_success "Application URL: $APP_URL"
    print_status "You can now access the web UI at: $APP_URL"
}

# Show deployment summary
show_summary() {
    print_status "Deployment Summary:"
    echo "===================="
    echo "Application URL: $(terraform output -raw web_ui_url)"
    echo "ECR Repository: $(terraform output -raw ecr_repository_url)"
    echo "ECS Cluster: $(terraform output -raw ecs_cluster_name)"
    echo "ECS Service: $(terraform output -raw ecs_service_name)"
    echo "CloudWatch Logs: $(terraform output -raw cloudwatch_log_group)"
    echo ""
    print_status "To view logs: aws logs tail $(terraform output -raw cloudwatch_log_group) --follow"
    print_status "To check service status: aws ecs describe-services --cluster $(terraform output -raw ecs_cluster_name) --services $(terraform output -raw ecs_service_name)"
}

# Main deployment function
deploy() {
    print_status "Starting deployment of Evaluation Reports Web UI..."
    
    check_prerequisites
    init_terraform
    plan_terraform
    
    # Ask for confirmation
    echo ""
    print_warning "This will create AWS resources that may incur costs."
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled."
        exit 0
    fi
    
    apply_terraform
    get_ecr_url
    login_ecr
    build_image
    push_image
    update_ecs_service
    wait_for_service
    get_app_url
    show_summary
    
    print_success "Deployment completed successfully!"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up resources..."
    terraform destroy -auto-approve
    print_success "Cleanup completed!"
}

# Show help
show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  deploy    Deploy the application (default)"
    echo "  cleanup   Destroy all resources"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 cleanup"
}

# Main script logic
case "${1:-deploy}" in
    "deploy")
        deploy
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        print_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

