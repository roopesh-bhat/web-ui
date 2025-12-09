variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "evaluation-reports"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket containing evaluation reports"
  type        = string
  default     = "agentix-evaluation-reports-dev"
}

variable "task_cpu" {
  description = "CPU units for the ECS task (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Memory for the ECS task in MB"
  type        = string
  default     = "1024"
}

variable "desired_count" {
  description = "Desired number of ECS service instances"
  type        = number
  default     = 1
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Project     = "Evaluation Reports"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
