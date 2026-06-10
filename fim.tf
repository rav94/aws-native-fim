resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0
}

resource "aws_s3_bucket" "fim_baselines" {
  bucket        = local.fim_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "fim_baselines" {
  bucket = aws_s3_bucket.fim_baselines.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "fim_baselines" {
  bucket = aws_s3_bucket.fim_baselines.id

  rule {
    id     = "delete-fim-baseline-content-after-30-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fim_baselines" {
  bucket = aws_s3_bucket.fim_baselines.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "fim_baselines" {
  bucket = aws_s3_bucket.fim_baselines.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "fim_baselines" {
  bucket = aws_s3_bucket.fim_baselines.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.fim_baselines.arn,
          "${aws_s3_bucket.fim_baselines.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_ssm_parameter" "fim_monitored_paths" {
  name        = "/fim-demo/${local.name_prefix}/security/fim/monitored-paths"
  description = "Paths monitored by AWS-native FIM on ECS EC2 container hosts"
  type        = "String"
  value       = join("\n", local.fim_monitored_paths)
}

resource "aws_iam_role_policy" "ecs_ec2_fim_policy" {
  name = "${local.name_prefix}-ecs-ec2-fim"
  role = aws_iam_role.ecs_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListFimBaselineBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.fim_baselines.arn
      },
      {
        Sid    = "ReadWriteFimBaselineObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.fim_baselines.arn}/*"
      },
      {
        Sid    = "ReadFimMonitoredPaths"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = aws_ssm_parameter.fim_monitored_paths.arn
      },
      {
        Sid    = "ImportFimFindingsToSecurityHub"
        Effect = "Allow"
        Action = [
          "securityhub:BatchImportFindings",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssm_document" "fim_ecs_ec2_check" {
  name            = "fim-${local.name_prefix}-ecs-ec2-check"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "AWS-native FIM check for ECS EC2 container instances"
    parameters = {
      BucketName = {
        type        = "String"
        description = "S3 bucket used to store FIM baselines"
        default     = aws_s3_bucket.fim_baselines.bucket
      }
      Region = {
        type        = "String"
        description = "AWS region"
        default     = var.AWS_REGION
      }
      SeverityLabel = {
        type        = "String"
        description = "Security Hub severity label"
        default     = var.fim_severity_label
      }
      MonitoredPathsParameter = {
        type        = "String"
        description = "SSM Parameter Store name containing newline-separated monitored paths"
        default     = aws_ssm_parameter.fim_monitored_paths.name
      }
      SecurityHubProductArn = {
        type        = "String"
        description = "Security Hub product ARN to use in imported findings"
        default     = coalesce(var.security_hub_product_arn, "default")
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "RunFimCheck"
        inputs = {
          timeoutSeconds = "900"
          runCommand = [
            <<-EOT
            #!/bin/bash
            set -euo pipefail

            BUCKET_NAME="{{ BucketName }}"
            REGION="{{ Region }}"
            SEVERITY_LABEL="{{ SeverityLabel }}"
            MONITORED_PATHS_PARAMETER="{{ MonitoredPathsParameter }}"
            SECURITY_HUB_PRODUCT_ARN="{{ SecurityHubProductArn }}"
            PRODUCT_NAME="AWS Native FIM Demo"
            COMPANY_NAME="Demo"
            WORK_DIR="/tmp/aws-native-fim"

            mkdir -p "$WORK_DIR"

            if ! command -v jq >/dev/null 2>&1; then
              echo "[INFO] jq is not installed. Attempting installation."
              if command -v dnf >/dev/null 2>&1; then
                dnf install -y jq
              elif command -v yum >/dev/null 2>&1; then
                yum install -y jq
              elif command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y jq
              else
                echo "[ERROR] jq is required but no supported package manager was found."
                exit 2
              fi
            fi

            if ! command -v aws >/dev/null 2>&1; then
              echo "[INFO] AWS CLI is not installed. Attempting installation."
              if command -v dnf >/dev/null 2>&1; then
                dnf install -y awscli
              elif command -v yum >/dev/null 2>&1; then
                yum install -y awscli
              elif command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y awscli
              else
                echo "[ERROR] AWS CLI is required but no supported package manager was found."
                exit 2
              fi
            fi

            TOKEN="$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' || true)"
            if [ -n "$TOKEN" ]; then
              INSTANCE_ID="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo unknown-instance)"
            else
              INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo unknown-instance)"
            fi

            HOSTNAME="$(hostname)"
            ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region "$REGION")"
            if [ "$SECURITY_HUB_PRODUCT_ARN" = "default" ]; then
              SECURITY_HUB_PRODUCT_ARN="arn:aws:securityhub:$REGION:$ACCOUNT_ID:product/$ACCOUNT_ID/default"
            fi

            BASE_PREFIX="fim/$ACCOUNT_ID/$REGION/$INSTANCE_ID"
            BASELINE_FILE="$WORK_DIR/baseline.json"
            LATEST_FILE="$WORK_DIR/latest.json"
            ADDED_FILE="$WORK_DIR/added.txt"
            DELETED_FILE="$WORK_DIR/deleted.txt"
            MODIFIED_FILE="$WORK_DIR/modified.txt"
            FINDINGS_FILE="$WORK_DIR/findings.json"
            BASELINE_PATHS_FILE="$WORK_DIR/baseline_paths.txt"
            LATEST_PATHS_FILE="$WORK_DIR/latest_paths.txt"

            S3_BASELINE="s3://$BUCKET_NAME/$BASE_PREFIX/baseline.json"
            S3_LATEST="s3://$BUCKET_NAME/$BASE_PREFIX/latest.json"
            S3_CHANGE_PREFIX="s3://$BUCKET_NAME/$BASE_PREFIX/changes"

            echo "[INFO] Starting AWS-native FIM check"
            echo "[INFO] Instance: $INSTANCE_ID"
            echo "[INFO] Hostname: $HOSTNAME"

            MONITORED_PATHS_VALUE="$(aws ssm get-parameter --name "$MONITORED_PATHS_PARAMETER" --region "$REGION" --query Parameter.Value --output text)"
            mapfile -t MONITORED_PATHS < <(printf '%s\n' "$MONITORED_PATHS_VALUE" | sed '/^[[:space:]]*$/d')

            if [ "$${#MONITORED_PATHS[@]}" -eq 0 ]; then
              echo "[ERROR] No monitored paths were found in $MONITORED_PATHS_PARAMETER."
              exit 2
            fi

            : > "$LATEST_FILE.tmp"

            for path in "$${MONITORED_PATHS[@]}"; do
              if [ -e "$path" ]; then
                if [ -f "$path" ]; then
                  sha256sum "$path" >> "$LATEST_FILE.tmp" 2>/dev/null || true
                elif [ -d "$path" ]; then
                  find "$path" \
                    -type f \
                    ! -path "/var/lib/docker/overlay2/*" \
                    ! -path "/var/lib/docker/containers/*" \
                    ! -path "/var/log/*" \
                    ! -path "/tmp/*" \
                    -exec sha256sum {} \; >> "$LATEST_FILE.tmp" 2>/dev/null || true
                fi
              fi
            done

            awk '{
              hash=$1;
              $1="";
              sub(/^ /, "", $0);
              gsub(/\\/,"\\\\",$0);
              gsub(/"/,"\\\"",$0);
              if (!seen[$0]++) {
                printf "{\"hash\":\"%s\",\"path\":\"%s\"}\n", hash, $0
              }
            }' "$LATEST_FILE.tmp" | jq -s -c 'sort_by(.path)[]' > "$LATEST_FILE"

            if aws s3 cp "$S3_BASELINE" "$BASELINE_FILE" --region "$REGION" >/dev/null 2>&1; then
              echo "[INFO] Existing baseline downloaded"
            else
              echo "[INFO] No baseline found. Creating initial baseline."
              aws s3 cp "$LATEST_FILE" "$S3_BASELINE" --region "$REGION"
              aws s3 cp "$LATEST_FILE" "$S3_LATEST" --region "$REGION"
              echo "[INFO] Initial baseline created. No findings generated."
              exit 0
            fi

            jq -r '.path' "$BASELINE_FILE" | sort > "$BASELINE_PATHS_FILE"
            jq -r '.path' "$LATEST_FILE" | sort > "$LATEST_PATHS_FILE"

            comm -13 "$BASELINE_PATHS_FILE" "$LATEST_PATHS_FILE" > "$ADDED_FILE"
            comm -23 "$BASELINE_PATHS_FILE" "$LATEST_PATHS_FILE" > "$DELETED_FILE"

            : > "$MODIFIED_FILE"
            while read -r path; do
              old_hash="$(jq -r --arg p "$path" 'select(.path==$p) | .hash' "$BASELINE_FILE" | head -n 1)"
              new_hash="$(jq -r --arg p "$path" 'select(.path==$p) | .hash' "$LATEST_FILE" | head -n 1)"
              if [ -n "$old_hash" ] && [ -n "$new_hash" ] && [ "$old_hash" != "$new_hash" ]; then
                echo "$path|$old_hash|$new_hash" >> "$MODIFIED_FILE"
              fi
            done < <(comm -12 "$BASELINE_PATHS_FILE" "$LATEST_PATHS_FILE")

            ADDED_COUNT="$(wc -l < "$ADDED_FILE" | tr -d ' ')"
            DELETED_COUNT="$(wc -l < "$DELETED_FILE" | tr -d ' ')"
            MODIFIED_COUNT="$(wc -l < "$MODIFIED_FILE" | tr -d ' ')"

            echo "[INFO] Added: $ADDED_COUNT, Deleted: $DELETED_COUNT, Modified: $MODIFIED_COUNT"

            TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            CHANGE_ID="$(date -u +"%Y%m%d%H%M%S")"

            aws s3 cp "$LATEST_FILE" "$S3_LATEST" --region "$REGION"
            aws s3 cp "$ADDED_FILE" "$S3_CHANGE_PREFIX/$CHANGE_ID-added.txt" --region "$REGION" >/dev/null
            aws s3 cp "$DELETED_FILE" "$S3_CHANGE_PREFIX/$CHANGE_ID-deleted.txt" --region "$REGION" >/dev/null
            aws s3 cp "$MODIFIED_FILE" "$S3_CHANGE_PREFIX/$CHANGE_ID-modified.txt" --region "$REGION" >/dev/null

            if [ "$ADDED_COUNT" -eq 0 ] && [ "$DELETED_COUNT" -eq 0 ] && [ "$MODIFIED_COUNT" -eq 0 ]; then
              echo "[INFO] No FIM changes detected."
              exit 0
            fi

            jq -n \
              --arg region "$REGION" \
              --arg account_id "$ACCOUNT_ID" \
              --arg product_arn "$SECURITY_HUB_PRODUCT_ARN" \
              --arg instance_id "$INSTANCE_ID" \
              --arg change_id "$CHANGE_ID" \
              --arg timestamp "$TIMESTAMP" \
              --arg severity_label "$SEVERITY_LABEL" \
              --arg hostname "$HOSTNAME" \
              --arg product_name "$PRODUCT_NAME" \
              --arg company_name "$COMPANY_NAME" \
              --arg added_count "$ADDED_COUNT" \
              --arg deleted_count "$DELETED_COUNT" \
              --arg modified_count "$MODIFIED_COUNT" \
              --arg s3_baseline "$S3_BASELINE" \
              --arg s3_latest "$S3_LATEST" \
              --arg s3_change_prefix "$S3_CHANGE_PREFIX/$CHANGE_ID" \
              '{
                Findings: [
                  {
                    SchemaVersion: "2018-10-08",
                    Id: ("aws-native-fim-" + $instance_id + "-" + $change_id),
                    ProductArn: $product_arn,
                    GeneratorId: "aws-native-fim-demo",
                    AwsAccountId: $account_id,
                    Types: ["Software and Configuration Checks/File Integrity"],
                    CreatedAt: $timestamp,
                    UpdatedAt: $timestamp,
                    Severity: { Label: $severity_label },
                    Title: "FIM changes detected on ECS EC2 container host",
                    Description: ("AWS-native FIM detected file changes on ECS EC2 host " + $instance_id + ". Added=" + $added_count + ", Deleted=" + $deleted_count + ", Modified=" + $modified_count + "."),
                    Resources: [
                      {
                        Type: "AwsEc2Instance",
                        Id: ("arn:aws:ec2:" + $region + ":" + $account_id + ":instance/" + $instance_id),
                        Partition: "aws",
                        Region: $region,
                        Details: {
                          AwsEc2Instance: {
                            Type: "ECS EC2 Container Instance"
                          }
                        }
                      }
                    ],
                    ProductFields: {
                      ProductName: $product_name,
                      CompanyName: $company_name,
                      Hostname: $hostname,
                      InstanceId: $instance_id,
                      AddedCount: $added_count,
                      DeletedCount: $deleted_count,
                      ModifiedCount: $modified_count,
                      BaselineS3Uri: $s3_baseline,
                      LatestS3Uri: $s3_latest,
                      ChangeDetailsS3Prefix: $s3_change_prefix
                    },
                    Workflow: { Status: "NEW" },
                    RecordState: "ACTIVE"
                  }
                ]
              }' > "$FINDINGS_FILE"

            aws securityhub batch-import-findings \
              --region "$REGION" \
              --cli-input-json "file://$FINDINGS_FILE"

            echo "[INFO] Security Hub finding imported."
            echo "[INFO] Latest snapshot uploaded, baseline preserved for review."
            EOT
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "fim_ecs_ec2_check" {
  name                = aws_ssm_document.fim_ecs_ec2_check.name
  association_name    = "fim-${local.name_prefix}-ecs-ec2-check"
  schedule_expression = var.fim_schedule_expression

  targets {
    key    = "tag:FIM"
    values = ["enabled"]
  }

  parameters = {
    BucketName              = aws_s3_bucket.fim_baselines.bucket
    Region                  = var.AWS_REGION
    SeverityLabel           = var.fim_severity_label
    MonitoredPathsParameter = aws_ssm_parameter.fim_monitored_paths.name
    SecurityHubProductArn   = coalesce(var.security_hub_product_arn, "default")
  }
}

resource "aws_sns_topic" "fim_findings" {
  name = "${local.name_prefix}-security-fim-findings"
}

resource "aws_sns_topic_policy" "fim_findings" {
  arn = aws_sns_topic.fim_findings.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublishFimFindings"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.fim_findings.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.fim_securityhub_findings.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "fim_securityhub_findings" {
  name        = "${local.name_prefix}-security-hub-fim-findings"
  description = "Capture AWS-native FIM demo findings imported into Security Hub"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        GeneratorId = ["aws-native-fim-demo"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "fim_securityhub_findings" {
  target_id = "${local.name_prefix}-security-fim-findings-sns"
  rule      = aws_cloudwatch_event_rule.fim_securityhub_findings.name
  arn       = aws_sns_topic.fim_findings.arn
}
