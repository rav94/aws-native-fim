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

## Run locally

Install these tools first:

- Terraform `>= 1.6`
- AWS CLI v2
- direnv

Check the tools:

```bash
terraform version
aws --version
direnv version
```

This project follows the same `.envrc` pattern as the existing Emojot Terraform
dev stack. The shared defaults live in `.envrc`, and local machine/account
overrides go in `.envrc.local`, which is ignored by git.

### Option 1: AWS profile or SSO

Use this when you already have an AWS CLI profile.

```bash
cp .envrc.local.example .envrc.local
```

Edit `.envrc.local`:

```bash
export TF_VAR_AWS_REGION="us-east-1"
export TF_VAR_AWS_PROFILE="emojot-dev"
export AWS_PROFILE="$TF_VAR_AWS_PROFILE"
export TF_VAR_AWS_ROLE_ARN=""
export TF_VAR_AWS_ROLE_SESSION_NAME="terraform-local-session"
export TF_VAR_root_volume_size="30"
export TF_VAR_asg_desired_capacity="1"
export TF_VAR_asg_max_size="2"
export TF_VAR_enable_security_hub="false"
```

If the profile uses AWS SSO, log in before running Terraform:

```bash
aws sso login --profile emojot-dev
aws sts get-caller-identity --profile emojot-dev
direnv allow
terraform init
terraform plan
terraform apply
```

### Option 2: Access keys without SSO

Use this when the person running the demo does not have AWS SSO configured.

```bash
cp .envrc.local.example .envrc.local
```

Edit `.envrc.local` and add the access keys directly. Do not commit this file.

```bash
export AWS_ACCESS_KEY_ID="replace-me"
export AWS_SECRET_ACCESS_KEY="replace-me"
export AWS_SESSION_TOKEN=""
export AWS_DEFAULT_REGION="us-east-1"

export TF_VAR_AWS_REGION="$AWS_DEFAULT_REGION"
export TF_VAR_AWS_PROFILE=""
export TF_VAR_AWS_ROLE_ARN=""
export TF_VAR_AWS_ROLE_SESSION_NAME="terraform-local-session"
export TF_VAR_root_volume_size="30"
export TF_VAR_asg_desired_capacity="1"
export TF_VAR_asg_max_size="2"
export TF_VAR_enable_security_hub="false"
```

Then run:

```bash
direnv allow
aws sts get-caller-identity
terraform init
terraform plan
terraform apply
```

If you use temporary STS credentials, set `AWS_SESSION_TOKEN`. If you use
long-lived IAM user credentials, leave `AWS_SESSION_TOKEN` empty.

### Optional: assume a role

For either setup, set `TF_VAR_AWS_ROLE_ARN` when Terraform should assume a role
after loading the base credentials.

```bash
export TF_VAR_AWS_ROLE_ARN="arn:aws:iam::123456789012:role/example-terraform-role"
export TF_VAR_AWS_ROLE_SESSION_NAME="terraform-local-session"
```

### Minimum AWS permissions

The identity running Terraform needs permissions to create and manage the demo
resources: VPC, subnets, route tables, Internet Gateway, security groups, IAM
roles and instance profiles, ECS, Auto Scaling, EC2 launch templates, S3, SSM,
SNS, EventBridge, and optionally Security Hub.

### Apply troubleshooting

If the ECS Auto Scaling Group fails with `Volume of size 20GB is smaller than
snapshot ... expect size >= 30GB`, use `TF_VAR_root_volume_size="30"` or larger.
The ECS optimized Amazon Linux 2023 AMI snapshot currently requires at least
30 GiB.

If Security Hub fails with `Account is already subscribed to Security Hub`, keep
`TF_VAR_enable_security_hub="false"`. The FIM check can still import findings
when Security Hub is already enabled outside this Terraform project. Only set it
to `true` in accounts where you want this project to enable Security Hub.

If SSM Parameter Store rejects a name as reserved, make sure the monitored paths
parameter uses the current `/fim-demo/...` prefix. AWS reserves names beginning
with `/aws`.

The first SSM run creates the baseline in S3 and exits without findings. Later
runs compare the latest hashes against the preserved baseline, upload change
details to S3, and import a finding into Security Hub when changes are detected.

## Demo notes

- Instances are selected by the SSM association using `tag:FIM = enabled`.
- The ECS optimized Amazon Linux 2023 AMI is resolved from the public SSM
  parameter `/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id`.
- Container Insights is disabled to keep the demo quiet and inexpensive.
- The root EBS volume is `30 GiB gp3` and encrypted.

## Tear down

```bash
terraform destroy
```

The FIM S3 bucket uses `force_destroy = true` so demo artifacts do not block
cleanup.
