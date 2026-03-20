#!/usr/bin/env ruby
# Multi-Cloud Backup Strategy
# Demonstrates backup strategy across AWS and Google Cloud Platform

require 'terraform-synthesizer'
require 'json'

synth = TerraformSynthesizer.new

synth.synthesize do
  # Provider configuration
  terraform do
    required_version ">= 1.0"
    required_providers do
      aws do
        source "hashicorp/aws"
        version "~> 5.0"
      end
      google do
        source "hashicorp/google"
        version "~> 4.0"
      end
      random do
        source "hashicorp/random"
        version "~> 3.1"
      end
    end
  end
  
  provider :aws do
    region "us-west-2"
  end
  
  provider :google do
    project "${var.gcp_project_id}"
    region "us-central1"
  end
  
  # Variables
  variable :gcp_project_id do
    description "GCP Project ID"
    type "string"
  end
  
  variable :environment do
    description "Environment name"
    type "string"
    default "production"
  end
  
  variable :backup_retention_days do
    description "Number of days to retain backups"
    type "number"
    default 30
  end
  
  # Random suffix for globally unique names
  resource :random_id, :suffix do
    byte_length 4
  end
  
  # Local values
  locals do
    name_prefix "backup-${var.environment}"
    suffix "${random_id.suffix.hex}"
    
    common_tags do
      Environment "${var.environment}"
      Purpose "backup"
      ManagedBy "terraform-synthesizer"
    end
  end
  
  # AWS Resources
  # Primary S3 bucket for backups
  resource :aws_s3_bucket, :primary_backup do
    bucket "${local.name_prefix}-primary-${local.suffix}"
    
    tags local.common_tags
  end
  
  resource :aws_s3_bucket_versioning, :primary_backup do
    bucket "${aws_s3_bucket.primary_backup.id}"
    versioning_configuration do
      status "Enabled"
    end
  end
  
  resource :aws_s3_bucket_lifecycle_configuration, :primary_backup do
    bucket "${aws_s3_bucket.primary_backup.id}"
    
    rule do
      id "backup_lifecycle"
      status "Enabled"
      
      expiration do
        days "${var.backup_retention_days}"
      end
      
      noncurrent_version_expiration do
        noncurrent_days 7
      end
      
      abort_incomplete_multipart_upload do
        days_after_initiation 1
      end
    end
  end
  
  resource :aws_s3_bucket_server_side_encryption_configuration, :primary_backup do
    bucket "${aws_s3_bucket.primary_backup.id}"
    
    rule do
      apply_server_side_encryption_by_default do
        sse_algorithm "AES256"
      end
    end
  end
  
  resource :aws_s3_bucket_public_access_block, :primary_backup do
    bucket "${aws_s3_bucket.primary_backup.id}"
    
    block_public_acls       true
    block_public_policy     true
    ignore_public_acls      true
    restrict_public_buckets true
  end
  
  # Cross-region replication bucket
  resource :aws_s3_bucket, :replication do
    provider "aws"
    bucket "${local.name_prefix}-replication-${local.suffix}"
    
    tags local.common_tags
  end
  
  resource :aws_s3_bucket_versioning, :replication do
    bucket "${aws_s3_bucket.replication.id}"
    versioning_configuration do
      status "Enabled"
    end
  end
  
  # IAM role for S3 replication
  resource :aws_iam_role, :replication do
    name "${local.name_prefix}-replication-role"
    
    assume_role_policy jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "s3.amazonaws.com"
          }
        }
      ]
    })
    
    tags local.common_tags
  end
  
  resource :aws_iam_policy, :replication do
    name "${local.name_prefix}-replication-policy"
    
    policy jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl"
          ]
          Resource = "${aws_s3_bucket.primary_backup.arn}/*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket"
          ]
          Resource = aws_s3_bucket.primary_backup.arn
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete"
          ]
          Resource = "${aws_s3_bucket.replication.arn}/*"
        }
      ]
    })
  end
  
  resource :aws_iam_role_policy_attachment, :replication do
    role "${aws_iam_role.replication.name}"
    policy_arn "${aws_iam_policy.replication.arn}"
  end
  
  # S3 bucket replication configuration
  resource :aws_s3_bucket_replication_configuration, :primary_backup do
    role "${aws_iam_role.replication.arn}"
    bucket "${aws_s3_bucket.primary_backup.id}"
    
    rule do
      id "replicate_all"
      status "Enabled"
      priority 1
      
      destination do
        bucket "${aws_s3_bucket.replication.arn}"
        storage_class "STANDARD_IA"
      end
    end
    
    depends_on ["aws_s3_bucket_versioning.primary_backup"]
  end
  
  # Google Cloud Storage Resources
  # GCS bucket for off-site backup
  resource :google_storage_bucket, :offsite_backup do
    name "${local.name_prefix}-offsite-${local.suffix}"
    location "US"
    storage_class "COLDLINE"
    
    uniform_bucket_level_access true
    
    versioning do
      enabled true
    end
    
    lifecycle_rule do
      condition do
        age 90
      end
      action do
        type "Delete"
      end
    end
    
    lifecycle_rule do
      condition do
        age 30
      end
      action do
        type "SetStorageClass"
        storage_class "ARCHIVE"
      end
    end
    
    labels local.common_tags
  end
  
  # Cloud Function for automated backup transfer
  resource :google_storage_bucket, :cloud_function_source do
    name "${local.name_prefix}-function-source-${local.suffix}"
    location "US"
  end
  
  # Service account for backup operations
  resource :google_service_account, :backup_sa do
    account_id "${local.name_prefix}-backup-sa"
    display_name "Backup Service Account"
    description "Service account for backup operations"
  end
  
  resource :google_project_iam_member, :backup_sa_storage do
    project "${var.gcp_project_id}"
    role "roles/storage.admin"
    member "serviceAccount:${google_service_account.backup_sa.email}"
  end
  
  # Lambda function for backup orchestration
  resource :aws_iam_role, :backup_lambda do
    name "${local.name_prefix}-lambda-role"
    
    assume_role_policy jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "lambda.amazonaws.com"
          }
        }
      ]
    })
    
    tags local.common_tags
  end
  
  resource :aws_iam_policy, :backup_lambda do
    name "${local.name_prefix}-lambda-policy"
    
    policy jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:*:*:*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket",
            "s3:PutObject"
          ]
          Resource = [
            aws_s3_bucket.primary_backup.arn,
            "${aws_s3_bucket.primary_backup.arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "rds:CreateDBSnapshot",
            "rds:DescribeDBSnapshots",
            "rds:DeleteDBSnapshot"
          ]
          Resource = "*"
        }
      ]
    })
  end
  
  resource :aws_iam_role_policy_attachment, :backup_lambda do
    role "${aws_iam_role.backup_lambda.name}"
    policy_arn "${aws_iam_policy.backup_lambda.arn}"
  end
  
  # CloudWatch Events for scheduled backups
  resource :aws_cloudwatch_event_rule, :daily_backup do
    name "${local.name_prefix}-daily-backup"
    description "Trigger daily backup"
    schedule_expression "rate(1 day)"
    
    tags local.common_tags
  end
  
  # SNS topic for backup notifications
  resource :aws_sns_topic, :backup_notifications do
    name "${local.name_prefix}-notifications"
    
    tags local.common_tags
  end
  
  resource :aws_sns_topic_subscription, :email do
    topic_arn "${aws_sns_topic.backup_notifications.arn}"
    protocol "email"
    endpoint "${var.notification_email}"
  end
  
  # CloudWatch alarms for backup monitoring
  resource :aws_cloudwatch_metric_alarm, :backup_failure do
    alarm_name "${local.name_prefix}-backup-failure"
    comparison_operator "GreaterThanThreshold"
    evaluation_periods "1"
    metric_name "Errors"
    namespace "AWS/Lambda"
    period "86400"
    statistic "Sum"
    threshold "0"
    alarm_description "This metric monitors backup failures"
    alarm_actions ["${aws_sns_topic.backup_notifications.arn}"]
    
    dimensions do
      FunctionName "${aws_lambda_function.backup_orchestrator.function_name}"
    end
    
    tags local.common_tags
  end
  
  # Variables for email notifications
  variable :notification_email do
    description "Email address for backup notifications"
    type "string"
    default ""
  end
  
  # Lambda function (would need actual deployment package)
  resource :aws_lambda_function, :backup_orchestrator do
    filename "backup_orchestrator.zip"
    function_name "${local.name_prefix}-orchestrator"
    role "${aws_iam_role.backup_lambda.arn}"
    handler "lambda_function.lambda_handler"
    runtime "python3.9"
    timeout 300
    
    environment do
      variables do
        PRIMARY_BUCKET "${aws_s3_bucket.primary_backup.id}"
        GCS_BUCKET "${google_storage_bucket.offsite_backup.name}"
        SNS_TOPIC "${aws_sns_topic.backup_notifications.arn}"
      end
    end
    
    tags local.common_tags
  end
  
  resource :aws_lambda_permission, :allow_cloudwatch do
    statement_id "AllowExecutionFromCloudWatch"
    action "lambda:InvokeFunction"
    function_name "${aws_lambda_function.backup_orchestrator.function_name}"
    principal "events.amazonaws.com"
    source_arn "${aws_cloudwatch_event_rule.daily_backup.arn}"
  end
  
  resource :aws_cloudwatch_event_target, :lambda_target do
    rule "${aws_cloudwatch_event_rule.daily_backup.name}"
    target_id "BackupLambdaTarget"
    arn "${aws_lambda_function.backup_orchestrator.arn}"
  end
  
  # Outputs
  output :aws_primary_backup_bucket do
    description "Primary backup bucket in AWS"
    value "${aws_s3_bucket.primary_backup.id}"
  end
  
  output :aws_replication_bucket do
    description "Replication backup bucket in AWS"
    value "${aws_s3_bucket.replication.id}"
  end
  
  output :gcs_offsite_backup_bucket do
    description "Offsite backup bucket in GCS"
    value "${google_storage_bucket.offsite_backup.name}"
  end
  
  output :backup_lambda_function do
    description "Lambda function for backup orchestration"
    value "${aws_lambda_function.backup_orchestrator.function_name}"
  end
  
  output :sns_topic_arn do
    description "SNS topic for backup notifications"
    value "${aws_sns_topic.backup_notifications.arn}"
  end
  
  output :gcp_service_account_email do
    description "GCP service account for backup operations"
    value "${google_service_account.backup_sa.email}"
  end
end

# Output the generated Terraform configuration
puts JSON.pretty_generate(synth.synthesis)