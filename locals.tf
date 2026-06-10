locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "aws-native-fim-demo"
  }

  fim_bucket_name = coalesce(var.fim_bucket_name, "${local.name_prefix}-fim-baselines-${random_id.bucket_suffix.hex}")

  fim_monitored_paths = [
    "/etc/passwd",
    "/etc/group",
    "/etc/shadow",
    "/etc/gshadow",
    "/etc/ssh",
    "/etc/sudoers",
    "/etc/sudoers.d",
    "/etc/pam.d",
    "/etc/security",
    "/etc/systemd/system",
    "/etc/systemd/system.conf",
    "/etc/systemd/system.conf.d",
    "/etc/cron.d",
    "/etc/crontab",
    "/var/spool/cron",
    "/etc/ecs",
    "/etc/docker",
    "/etc/containerd",
    "/etc/audit",
    "/etc/yum.repos.d",
    "/etc/cloud/cloud.cfg",
    "/etc/cloud/cloud.cfg.d",
    "/opt/aws/amazon-cloudwatch-agent/etc",
  ]
}

