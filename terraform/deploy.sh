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

PROJECT_NAME="evaluation-reports"
AWS_REGION="us-east-1"
ACCOUNT_ID=""
export AWS_PROFILE="roopesh_sandbox"

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed."
        exit 1
    fi
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed."
        exit 1
    fi
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed."
        exit 1
    fi
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "All prerequisites met! (Account: $ACCOUNT_ID)"
}

# Import a resource into Terraform state if it's not already tracked
import_if_missing() {
    local resource_addr="$1"
    local resource_id="$2"

    if terraform state show "$resource_addr" &> /dev/null; then
        print_status "Already in state: $resource_addr — skipping import"
    else
        print_warning "Importing existing resource: $resource_addr ($resource_id)"
        terraform import "$resource_addr" "$resource_id"
        print_success "Imported: $resource_addr"
    fi
}

# Handle VPC limit — reuse existing project VPC or prompt to delete one
handle_vpc() {
    # Check if already in state
    if terraform state show aws_vpc.main &> /dev/null; then
        print_status "VPC already in state — skipping"
        return
    fi

    # Check if a VPC tagged with this project already exists
    EXISTING_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

    if [[ "$EXISTING_VPC_ID" != "None" && -n "$EXISTING_VPC_ID" ]]; then
        print_warning "Found existing project VPC: $EXISTING_VPC_ID — importing"
        terraform import aws_vpc.main "$EXISTING_VPC_ID"
        print_success "Imported VPC: $EXISTING_VPC_ID"
        return
    fi

    # Check VPC count
    VPC_COUNT=$(aws ec2 describe-vpcs --query 'length(Vpcs)' --output text)
    if [[ "$VPC_COUNT" -ge 5 ]]; then
        print_error "VPC limit reached ($VPC_COUNT/5). Please delete an unused VPC in the AWS console or via:"
        echo ""
        aws ec2 describe-vpcs --query 'Vpcs[*].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' --output table
        echo ""
        print_error "Then re-run this script."
        exit 1
    fi
}

# Import all resources that already exist in AWS but not in Terraform state
import_existing_resources() {
    print_status "Checking for existing AWS resources to import..."

    # VPC (special handling for limit)
    handle_vpc

    # Internet Gateway
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=${PROJECT_NAME}-igw" \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
    if [[ "$IGW_ID" != "None" && -n "$IGW_ID" ]]; then
        import_if_missing "aws_internet_gateway.main" "$IGW_ID"
    fi

    # Subnets (10.0.1.0/24 and 10.0.2.0/24 inside the project VPC)
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    if [[ "$VPC_ID" != "None" && -n "$VPC_ID" ]]; then
        for i in 0 1; do
            CIDR="10.0.$((i+1)).0/24"
            SUBNET_ID=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidrBlock,Values=$CIDR" \
                --query 'Subnets[0].SubnetId' --output text 2>/dev/null)
            if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
                import_if_missing "aws_subnet.public[$i]" "$SUBNET_ID"
            fi
        done
    fi

    # Route Table
    RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=tag:Name,Values=${PROJECT_NAME}-public-rt" \
        --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
    if [[ "$RT_ID" != "None" && -n "$RT_ID" ]]; then
        import_if_missing "aws_route_table.public" "$RT_ID"
    fi

    # Route Table Associations
    if [[ "$RT_ID" != "None" && -n "$RT_ID" && "$VPC_ID" != "None" && -n "$VPC_ID" ]]; then
        for i in 0 1; do
            CIDR="10.0.$((i+1)).0/24"
            SUBNET_ID=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidrBlock,Values=$CIDR" \
                --query 'Subnets[0].SubnetId' --output text 2>/dev/null)
            if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
                ASSOC_ID=$(aws ec2 describe-route-tables \
                    --route-table-ids "$RT_ID" \
                    --query "RouteTables[0].Associations[?SubnetId=='$SUBNET_ID'].RouteTableAssociationId" \
                    --output text 2>/dev/null)
                if [[ "$ASSOC_ID" != "None" && -n "$ASSOC_ID" ]]; then
                    import_if_missing "aws_route_table_association.public[$i]" "$ASSOC_ID"
                fi
            fi
        done
    fi

    # Security Groups
    ALB_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-alb-sg" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    if [[ "$ALB_SG_ID" != "None" && -n "$ALB_SG_ID" ]]; then
        import_if_missing "aws_security_group.alb" "$ALB_SG_ID"
    fi

    ECS_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-ecs-sg" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    if [[ "$ECS_SG_ID" != "None" && -n "$ECS_SG_ID" ]]; then
        import_if_missing "aws_security_group.ecs" "$ECS_SG_ID"
    fi

    # ALB
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --names "${PROJECT_NAME}-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
    if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
        import_if_missing "aws_lb.main" "$ALB_ARN"
    fi

    # ALB Target Group
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names "${PROJECT_NAME}-tg" \
        --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
        import_if_missing "aws_lb_target_group.main" "$TG_ARN"
    fi

    # ALB Listener
    if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
        LISTENER_ARN=$(aws elbv2 describe-listeners \
            --load-balancer-arn "$ALB_ARN" \
            --query 'Listeners[?Port==`80`].ListenerArn' --output text 2>/dev/null || echo "")
        if [[ -n "$LISTENER_ARN" && "$LISTENER_ARN" != "None" ]]; then
            import_if_missing "aws_lb_listener.main" "$LISTENER_ARN"
        fi
    fi

    # ECS Cluster
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${PROJECT_NAME}-cluster" \
        --query 'clusters[0].status' --output text 2>/dev/null)
    if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
        import_if_missing "aws_ecs_cluster.main" "${PROJECT_NAME}-cluster"
    fi

    # ECR Repository
    ECR_EXISTS=$(aws ecr describe-repositories --repository-names "${PROJECT_NAME}-web-ui" \
        --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "")
    if [[ "$ECR_EXISTS" == "${PROJECT_NAME}-web-ui" ]]; then
        import_if_missing "aws_ecr_repository.web_ui" "${PROJECT_NAME}-web-ui"
    fi

    # IAM Roles
    if aws iam get-role --role-name "${PROJECT_NAME}-ecs-task-execution-role" &> /dev/null; then
        import_if_missing "aws_iam_role.ecs_task_execution_role" "${PROJECT_NAME}-ecs-task-execution-role"
    fi
    if aws iam get-role --role-name "${PROJECT_NAME}-ecs-task-role" &> /dev/null; then
        import_if_missing "aws_iam_role.ecs_task_role" "${PROJECT_NAME}-ecs-task-role"
    fi

    # IAM Policy
    POLICY_ARN=$(aws iam list-policies --scope Local \
        --query "Policies[?PolicyName=='${PROJECT_NAME}-s3-access'].Arn" --output text 2>/dev/null)
    if [[ -n "$POLICY_ARN" && "$POLICY_ARN" != "None" ]]; then
        import_if_missing "aws_iam_policy.s3_access" "$POLICY_ARN"
    fi

    # CloudWatch Log Group
    LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/ecs/${PROJECT_NAME}-web-ui" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null)
    if [[ "$LOG_GROUP_EXISTS" == "/ecs/${PROJECT_NAME}-web-ui" ]]; then
        import_if_missing "aws_cloudwatch_log_group.web_ui" "/ecs/${PROJECT_NAME}-web-ui"
    fi

    print_success "Resource import check complete!"
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
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
    print_success "Logged in to ECR!"
}

# Build Docker image
build_image() {
    print_status "Building Docker image..."
    cd ..
    docker build -t evaluation-reports-web-ui:latest .
    cd terraform
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
    print_status "Waiting for ECS service to be stable (this may take a few minutes)..."
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(terraform output -raw ecs_service_name)

    aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME
    print_success "ECS service is stable!"
}

# Get application URL
get_app_url() {
    APP_URL=$(terraform output -raw web_ui_url)
    print_success "Application URL: $APP_URL"
}

# Show deployment summary
show_summary() {
    echo ""
    print_status "Deployment Summary:"
    echo "===================="
    echo "Application URL:  $(terraform output -raw web_ui_url)"
    echo "ECR Repository:   $(terraform output -raw ecr_repository_url)"
    echo "ECS Cluster:      $(terraform output -raw ecs_cluster_name)"
    echo "ECS Service:      $(terraform output -raw ecs_service_name)"
    echo "CloudWatch Logs:  $(terraform output -raw cloudwatch_log_group)"
    echo ""
    print_status "View logs:          aws logs tail $(terraform output -raw cloudwatch_log_group) --follow"
    print_status "Check service:      aws ecs describe-services --cluster $(terraform output -raw ecs_cluster_name) --services $(terraform output -raw ecs_service_name)"
}

# Main deployment function
deploy() {
    print_status "Starting deployment of Evaluation Reports Web UI..."

    check_prerequisites
    init_terraform
    import_existing_resources
    plan_terraform

    echo ""
    print_warning "This will create/update AWS resources that may incur costs."
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
