# Terraform Synthesizer Examples

This directory contains practical examples showing how to use terraform-synthesizer for various infrastructure scenarios.

## Examples

### Basic Examples
- [`basic_vpc.rb`](basic_vpc.rb) - Simple VPC with public and private subnets
- [`simple_web_server.rb`](simple_web_server.rb) - Basic EC2 instance with security groups
- [`s3_static_website.rb`](s3_static_website.rb) - S3 bucket configured for static website hosting

### Advanced AWS Examples
- [`complete_web_app.rb`](complete_web_app.rb) - Full web application infrastructure with VPC, ALB, EC2, and RDS
- [`microservices_architecture.rb`](microservices_architecture.rb) - ECS-based microservices with service discovery
- [`serverless_application.rb`](serverless_application.rb) - Lambda functions with API Gateway and DynamoDB

### Multi-Cloud Examples  
- [`multi_cloud_backup.rb`](multi_cloud_backup.rb) - Backup strategy across AWS and GCP
- [`hybrid_kubernetes.rb`](hybrid_kubernetes.rb) - Kubernetes clusters on multiple cloud providers

### DevOps and CI/CD Examples
- [`jenkins_pipeline.rb`](jenkins_pipeline.rb) - Jenkins CI/CD infrastructure
- [`monitoring_stack.rb`](monitoring_stack.rb) - Prometheus and Grafana monitoring

### Specialized Use Cases
- [`data_pipeline.rb`](data_pipeline.rb) - ETL pipeline with EMR and Redshift
- [`machine_learning.rb`](machine_learning.rb) - ML infrastructure with SageMaker
- [`compliance_setup.rb`](compliance_setup.rb) - HIPAA/SOC2 compliant infrastructure

## Running Examples

To run any example:

```bash
cd examples
ruby basic_vpc.rb > basic_vpc.tf.json
terraform init && terraform plan -var-file="terraform.tfvars"
```

Each example generates Terraform JSON that can be used directly with the `terraform` CLI.

## Environment Variables

Some examples require environment variables:

```bash
export TF_VAR_db_password="your-secure-password"
export TF_VAR_api_key="your-api-key"
```

Check individual example files for specific requirements.