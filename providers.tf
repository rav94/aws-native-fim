provider "aws" {
  region  = var.AWS_REGION
  profile = var.AWS_PROFILE != "" ? var.AWS_PROFILE : null

  dynamic "assume_role" {
    for_each = var.AWS_ROLE_ARN != "" ? [1] : []
    content {
      role_arn     = var.AWS_ROLE_ARN
      session_name = var.AWS_ROLE_SESSION_NAME
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
