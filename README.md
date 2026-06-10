# AWS Native FIM Demo

This Terraform project deploys a low-cost, standalone demo of an AWS-native File
Integrity Monitoring implementation for ECS on EC2.

The demo starts from its own VPC and creates:

- A VPC using `172.20.0.0/16` by default instead of `10.0.0.0/8`
- Two public subnets and an Internet Gateway
- No NAT Gateway, no load balancer, and no ECS services by default
- An ECS cluster backed by EC2 capacity
- A launch template and Auto Scaling Group with `max_size = 2`
- An S3 bucket for FIM baselines and change artifacts
- An SSM Parameter Store value containing monitored paths
- An SSM command document and scheduled association targeting instances tagged `FIM=enabled`
- IAM permissions for the EC2 hosts to read paths config, store baselines, and import Security Hub findings
- EventBridge and SNS plumbing for FIM findings imported into Security Hub

## Cost posture

The cheapest meaningful demo path keeps the ECS container instances in public
subnets with public IP addresses. This avoids NAT Gateway hourly charges. The
default desired capacity is `1` so the FIM association has a host to run on; set
`asg_desired_capacity = 0` when you want the infrastructure present but no EC2
instance running.

Security Hub can incur AWS charges. This project does not enable it by default.
Set `enable_security_hub = true` only when you want Terraform to enable Security
Hub in the selected account and region.

## Usage

```bash
cp .envrc.local.example .envrc.local
direnv allow
terraform init
terraform plan
terraform apply
```

This follows the same `.envrc` pattern as the existing Emojot Terraform dev
stack. The shared defaults live in `.envrc`, and local machine/account overrides
go in `.envrc.local`, which is ignored by git.

The first SSM run creates the baseline in S3 and exits without findings. Later
runs compare the latest hashes against the preserved baseline, upload change
details to S3, and import a finding into Security Hub when changes are detected.

## Demo notes

- Instances are selected by the SSM association using `tag:FIM = enabled`.
- The ECS optimized Amazon Linux 2023 AMI is resolved from the public SSM
  parameter `/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id`.
- Container Insights is disabled to keep the demo quiet and inexpensive.
- The root EBS volume is `20 GiB gp3` and encrypted.

## Tear down

```bash
terraform destroy
```

The FIM S3 bucket uses `force_destroy = true` so demo artifacts do not block
cleanup.
