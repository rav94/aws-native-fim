output "vpc_id" {
  description = "Demo VPC ID."
  value       = aws_vpc.this.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "asg_name" {
  description = "ECS EC2 Auto Scaling Group name."
  value       = aws_autoscaling_group.ecs.name
}

output "fim_bucket_name" {
  description = "S3 bucket storing FIM baselines and change artifacts."
  value       = aws_s3_bucket.fim_baselines.bucket
}

output "fim_ssm_document_name" {
  description = "SSM command document used to run the FIM check."
  value       = aws_ssm_document.fim_ecs_ec2_check.name
}

output "fim_sns_topic_arn" {
  description = "SNS topic that receives matching Security Hub FIM events."
  value       = aws_sns_topic.fim_findings.arn
}

