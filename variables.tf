variable "AWS_REGION" {
  description = "AWS region to deploy the demo into."
  type        = string
  default     = "us-east-1"
}

variable "AWS_PROFILE" {
  description = "AWS shared config profile used by Terraform."
  type        = string
  default     = "emojot-dev"
}

variable "AWS_ROLE_ARN" {
  description = "Optional IAM role ARN for Terraform to assume."
  type        = string
  default     = ""
}

variable "AWS_ROLE_SESSION_NAME" {
  description = "STS session name used when AWS_ROLE_ARN is set."
  type        = string
  default     = "terraform-local-session"
}

variable "project_name" {
  description = "Short project name used in resource names."
  type        = string
  default     = "aws-native-fim"
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "Demo VPC CIDR. Defaults to a private range outside 10.0.0.0/8."
  type        = string
  default     = "172.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && !startswith(var.vpc_cidr, "10.")
    error_message = "Use a valid CIDR that does not start with 10.x.x.x."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for low-cost ECS EC2 capacity. No NAT Gateway is created."
  type        = list(string)
  default     = ["172.20.0.0/24", "172.20.1.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for ECS container instances."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB. ECS optimized Amazon Linux 2023 currently requires at least 30 GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB for the selected ECS optimized AMI snapshot."
  }
}

variable "asg_min_size" {
  description = "Minimum ECS EC2 Auto Scaling Group size."
  type        = number
  default     = 0
}

variable "asg_desired_capacity" {
  description = "Desired ECS EC2 Auto Scaling Group size. Use 1 to have a host ready for the FIM demo."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum ECS EC2 Auto Scaling Group size."
  type        = number
  default     = 2

  validation {
    condition     = var.asg_max_size <= 2
    error_message = "This demo is intentionally capped at 2 ECS EC2 instances."
  }
}

variable "fim_schedule_expression" {
  description = "SSM association schedule for the FIM check."
  type        = string
  default     = "rate(6 hours)"
}

variable "fim_severity_label" {
  description = "Security Hub severity label used by imported FIM findings."
  type        = string
  default     = "MEDIUM"
}

variable "fim_bucket_name" {
  description = "Optional globally unique S3 bucket name for FIM baselines. Leave null to generate one."
  type        = string
  default     = null
}

variable "security_hub_product_arn" {
  description = "Optional Security Hub product ARN. Leave null to use the account default product ARN."
  type        = string
  default     = null
}

variable "enable_security_hub" {
  description = "Whether Terraform should enable Security Hub in this account/region. Keep false when Security Hub is already enabled."
  type        = bool
  default     = false
}
