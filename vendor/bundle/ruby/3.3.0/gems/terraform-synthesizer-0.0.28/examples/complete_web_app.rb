#!/usr/bin/env ruby
# Complete Web Application Infrastructure
# Creates a full 3-tier web application with load balancer, auto-scaling, and database

require 'terraform-synthesizer'
require 'json'

synth = TerraformSynthesizer.new

synth.synthesize do
  # Terraform and provider configuration
  terraform do
    required_version ">= 1.0"
    required_providers do
      aws do
        source "hashicorp/aws"
        version "~> 5.0"
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
  
  # Variables
  variable :environment do
    description "Environment name (dev, staging, prod)"
    type "string"
    default "production"
  end
  
  variable :app_name do
    description "Application name"
    type "string"
    default "webapp"
  end
  
  variable :instance_type do
    description "EC2 instance type"
    type "string"
    default "t3.medium"
  end
  
  variable :min_size do
    description "Minimum number of instances"
    type "number"
    default 2
  end
  
  variable :max_size do
    description "Maximum number of instances"
    type "number"
    default 10
  end
  
  variable :desired_capacity do
    description "Desired number of instances"
    type "number"
    default 3
  end
  
  variable :db_password do
    description "Database master password"
    type "string"
    sensitive true
  end
  
  variable :ssl_certificate_arn do
    description "SSL certificate ARN for load balancer"
    type "string"
    default ""
  end
  
  # Data sources
  data :aws_availability_zones, :available do
    state "available"
  end
  
  data :aws_ami, :amazon_linux do
    most_recent true
    owners ["amazon"]
    
    filter do
      name "name"
      values ["amzn2-ami-hvm-*-x86_64-gp2"]
    end
  end
  
  # Random password for database
  resource :random_password, :db_password do
    length 16
    special true
    override_special "!#$%&*()-_=+[]{}<>:?"
  end
  
  # Local values
  locals do
    name_prefix "${var.app_name}-${var.environment}"
    
    common_tags do
      Environment "${var.environment}"
      Application "${var.app_name}"
      ManagedBy "terraform-synthesizer"
      CreatedAt "${timestamp()}"
    end
    
    availability_zones "${slice(data.aws_availability_zones.available.names, 0, 3)}"
  end
  
  # VPC and Networking
  resource :aws_vpc, :main do
    cidr_block "10.0.0.0/16"
    enable_dns_hostnames true
    enable_dns_support true
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-vpc\" })}"
  end
  
  resource :aws_internet_gateway, :main do
    vpc_id "${aws_vpc.main.id}"
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-igw\" })}"
  end
  
  # Public Subnets (for load balancer)
  resource :aws_subnet, :public do
    count "${length(local.availability_zones)}"
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 1}.0/24"
    availability_zone "${local.availability_zones[count.index]}"
    map_public_ip_on_launch true
    
    tags "${merge(local.common_tags, { 
      Name = \"${local.name_prefix}-public-${count.index + 1}\"
      Type = \"public\"
    })}"
  end
  
  # Private Subnets (for application servers)
  resource :aws_subnet, :private_app do
    count "${length(local.availability_zones)}"
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 10}.0/24"
    availability_zone "${local.availability_zones[count.index]}"
    
    tags "${merge(local.common_tags, { 
      Name = \"${local.name_prefix}-private-app-${count.index + 1}\"
      Type = \"private-app\"
    })}"
  end
  
  # Private Subnets (for database)
  resource :aws_subnet, :private_db do
    count "${length(local.availability_zones)}"
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 20}.0/24"
    availability_zone "${local.availability_zones[count.index]}"
    
    tags "${merge(local.common_tags, { 
      Name = \"${local.name_prefix}-private-db-${count.index + 1}\"
      Type = \"private-db\"
    })}"
  end
  
  # NAT Gateways
  resource :aws_eip, :nat do
    count "${length(local.availability_zones)}"
    domain "vpc"
    depends_on ["aws_internet_gateway.main"]
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-nat-eip-${count.index + 1}\" })}"
  end
  
  resource :aws_nat_gateway, :main do
    count "${length(local.availability_zones)}"
    allocation_id "${aws_eip.nat[count.index].id}"
    subnet_id "${aws_subnet.public[count.index].id}"
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-nat-${count.index + 1}\" })}"
  end
  
  # Route Tables
  resource :aws_route_table, :public do
    vpc_id "${aws_vpc.main.id}"
    
    route do
      cidr_block "0.0.0.0/0"
      gateway_id "${aws_internet_gateway.main.id}"
    end
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-public-rt\" })}"
  end
  
  resource :aws_route_table, :private_app do
    count "${length(local.availability_zones)}"
    vpc_id "${aws_vpc.main.id}"
    
    route do
      cidr_block "0.0.0.0/0"
      nat_gateway_id "${aws_nat_gateway.main[count.index].id}"
    end
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-private-app-rt-${count.index + 1}\" })}"
  end
  
  # Route Table Associations
  resource :aws_route_table_association, :public do
    count "${length(aws_subnet.public)}"
    subnet_id "${aws_subnet.public[count.index].id}"
    route_table_id "${aws_route_table.public.id}"
  end
  
  resource :aws_route_table_association, :private_app do
    count "${length(aws_subnet.private_app)}"
    subnet_id "${aws_subnet.private_app[count.index].id}"
    route_table_id "${aws_route_table.private_app[count.index].id}"
  end
  
  # Security Groups
  resource :aws_security_group, :alb do
    name_prefix "${local.name_prefix}-alb-"
    vpc_id "${aws_vpc.main.id}"
    description "Security group for Application Load Balancer"
    
    ingress do
      from_port 80
      to_port 80
      protocol "tcp"
      cidr_blocks ["0.0.0.0/0"]
    end
    
    ingress do
      from_port 443
      to_port 443
      protocol "tcp"
      cidr_blocks ["0.0.0.0/0"]
    end
    
    egress do
      from_port 0
      to_port 0
      protocol "-1"
      cidr_blocks ["0.0.0.0/0"]
    end
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-alb-sg\" })}"
  end
  
  resource :aws_security_group, :web do
    name_prefix "${local.name_prefix}-web-"
    vpc_id "${aws_vpc.main.id}"
    description "Security group for web servers"
    
    ingress do
      from_port 80
      to_port 80
      protocol "tcp"
      security_groups ["${aws_security_group.alb.id}"]
    end
    
    ingress do
      from_port 22
      to_port 22
      protocol "tcp"
      cidr_blocks ["10.0.0.0/16"]
    end
    
    egress do
      from_port 0
      to_port 0
      protocol "-1"
      cidr_blocks ["0.0.0.0/0"]
    end
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-web-sg\" })}"
  end
  
  resource :aws_security_group, :database do
    name_prefix "${local.name_prefix}-db-"
    vpc_id "${aws_vpc.main.id}"
    description "Security group for database"
    
    ingress do
      from_port 3306
      to_port 3306
      protocol "tcp"
      security_groups ["${aws_security_group.web.id}"]
    end
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-db-sg\" })}"
  end
  
  # Application Load Balancer
  resource :aws_lb, :main do
    name "${local.name_prefix}-alb"
    load_balancer_type "application"
    subnets "${aws_subnet.public[*].id}"
    security_groups ["${aws_security_group.alb.id}"]
    
    enable_deletion_protection false
    
    tags local.common_tags
  end
  
  resource :aws_lb_target_group, :web do
    name "${local.name_prefix}-web-tg"
    port 80
    protocol "HTTP"
    vpc_id "${aws_vpc.main.id}"
    target_type "instance"
    
    health_check do
      enabled true
      healthy_threshold 2
      unhealthy_threshold 2
      timeout 5
      interval 30
      path "/health"
      matcher "200"
      port "traffic-port"
      protocol "HTTP"
    end
    
    tags local.common_tags
  end
  
  resource :aws_lb_listener, :web do
    load_balancer_arn "${aws_lb.main.arn}"
    port "80"
    protocol "HTTP"
    
    default_action do
      type "forward"
      target_group_arn "${aws_lb_target_group.web.arn}"
    end
  end
  
  # Launch Template for Auto Scaling
  resource :aws_launch_template, :web do
    name_prefix "${local.name_prefix}-web-"
    image_id "${data.aws_ami.amazon_linux.id}"
    instance_type "${var.instance_type}"
    
    vpc_security_group_ids ["${aws_security_group.web.id}"]
    
    user_data "${base64encode(templatefile(\"${path.module}/user_data.sh\", {
      app_name = var.app_name
      environment = var.environment
    }))}"
    
    iam_instance_profile do
      name "${aws_iam_instance_profile.web.name}"
    end
    
    tag_specifications do
      resource_type "instance"
      tags "${merge(local.common_tags, { 
        Name = \"${local.name_prefix}-web\"
        Role = \"web-server\"
      })}"
    end
    
    lifecycle do
      create_before_destroy true
    end
  end
  
  # Auto Scaling Group
  resource :aws_autoscaling_group, :web do
    name "${local.name_prefix}-asg"
    vpc_zone_identifier "${aws_subnet.private_app[*].id}"
    target_group_arns ["${aws_lb_target_group.web.arn}"]
    health_check_type "ELB"
    health_check_grace_period 300
    
    min_size "${var.min_size}"
    max_size "${var.max_size}"
    desired_capacity "${var.desired_capacity}"
    
    launch_template do
      id "${aws_launch_template.web.id}"
      version "$Latest"
    end
    
    enabled_metrics [
      "GroupMinSize",
      "GroupMaxSize",
      "GroupDesiredCapacity",
      "GroupInServiceInstances",
      "GroupTotalInstances"
    ]
    
    tag do
      key "Name"
      value "${local.name_prefix}-asg"
      propagate_at_launch false
    end
    
    dynamic "tag" do
      for_each local.common_tags
      content do
        key "${tag.key}"
        value "${tag.value}"
        propagate_at_launch true
      end
    end
    
    instance_refresh do
      strategy "Rolling"
      preferences do
        min_healthy_percentage 50
      end
    end
  end
  
  # Auto Scaling Policies
  resource :aws_autoscaling_policy, :scale_up do
    name "${local.name_prefix}-scale-up"
    scaling_adjustment 2
    adjustment_type "ChangeInCapacity"
    cooldown 300
    autoscaling_group_name "${aws_autoscaling_group.web.name}"
  end
  
  resource :aws_autoscaling_policy, :scale_down do
    name "${local.name_prefix}-scale-down"
    scaling_adjustment -1
    adjustment_type "ChangeInCapacity"
    cooldown 300
    autoscaling_group_name "${aws_autoscaling_group.web.name}"
  end
  
  # CloudWatch Alarms
  resource :aws_cloudwatch_metric_alarm, :cpu_high do
    alarm_name "${local.name_prefix}-cpu-high"
    comparison_operator "GreaterThanThreshold"
    evaluation_periods "2"
    metric_name "CPUUtilization"
    namespace "AWS/EC2"
    period "120"
    statistic "Average"
    threshold "80"
    alarm_description "This metric monitors ec2 cpu utilization"
    alarm_actions ["${aws_autoscaling_policy.scale_up.arn}"]
    
    dimensions do
      AutoScalingGroupName "${aws_autoscaling_group.web.name}"
    end
    
    tags local.common_tags
  end
  
  resource :aws_cloudwatch_metric_alarm, :cpu_low do
    alarm_name "${local.name_prefix}-cpu-low"
    comparison_operator "LessThanThreshold"
    evaluation_periods "2"
    metric_name "CPUUtilization"
    namespace "AWS/EC2"
    period "120"
    statistic "Average"
    threshold "10"
    alarm_description "This metric monitors ec2 cpu utilization"
    alarm_actions ["${aws_autoscaling_policy.scale_down.arn}"]
    
    dimensions do
      AutoScalingGroupName "${aws_autoscaling_group.web.name}"
    end
    
    tags local.common_tags
  end
  
  # IAM Role for EC2 instances
  resource :aws_iam_role, :web do
    name "${local.name_prefix}-web-role"
    
    assume_role_policy jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
        }
      ]
    })
    
    tags local.common_tags
  end
  
  resource :aws_iam_role_policy_attachment, :web_ssm do
    role "${aws_iam_role.web.name}"
    policy_arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  end
  
  resource :aws_iam_instance_profile, :web do
    name "${local.name_prefix}-web-profile"
    role "${aws_iam_role.web.name}"
  end
  
  # RDS Database
  resource :aws_db_subnet_group, :main do
    name "${local.name_prefix}-db-subnet-group"
    subnet_ids "${aws_subnet.private_db[*].id}"
    
    tags "${merge(local.common_tags, { Name = \"${local.name_prefix}-db-subnet-group\" })}"
  end
  
  resource :aws_db_parameter_group, :main do
    family "mysql8.0"
    name "${local.name_prefix}-db-params"
    description "DB parameter group for ${local.name_prefix}"
    
    parameter do
      name "innodb_buffer_pool_size"
      value "{DBInstanceClassMemory*3/4}"
    end
    
    tags local.common_tags
  end
  
  resource :aws_db_instance, :main do
    identifier "${local.name_prefix}-database"
    allocated_storage 20
    max_allocated_storage 1000
    storage_type "gp2"
    storage_encrypted true
    
    engine "mysql"
    engine_version "8.0"
    instance_class "db.t3.micro"
    
    db_name "webapp"
    username "admin"
    password "${var.db_password != \"\" ? var.db_password : random_password.db_password.result}"
    
    vpc_security_group_ids ["${aws_security_group.database.id}"]
    db_subnet_group_name "${aws_db_subnet_group.main.name}"
    parameter_group_name "${aws_db_parameter_group.main.name}"
    
    backup_retention_period 7
    backup_window "03:00-04:00"
    maintenance_window "sun:04:00-sun:05:00"
    
    skip_final_snapshot false
    final_snapshot_identifier "${local.name_prefix}-final-snapshot-${formatdate(\"YYYY-MM-DD-hhmm\", timestamp())}"
    
    tags "${merge(local.common_tags, { 
      Name = \"${local.name_prefix}-database\"
      Role = \"database\"
    })}"
  end
  
  # S3 Bucket for application assets
  resource :aws_s3_bucket, :assets do
    bucket "${local.name_prefix}-assets-${random_id.bucket_suffix.hex}"
    
    tags local.common_tags
  end
  
  resource :random_id, :bucket_suffix do
    byte_length 4
  end
  
  resource :aws_s3_bucket_versioning, :assets do
    bucket "${aws_s3_bucket.assets.id}"
    versioning_configuration do
      status "Enabled"
    end
  end
  
  resource :aws_s3_bucket_public_access_block, :assets do
    bucket "${aws_s3_bucket.assets.id}"
    
    block_public_acls       true
    block_public_policy     true
    ignore_public_acls      true
    restrict_public_buckets true
  end
  
  # Outputs
  output :vpc_id do
    description "ID of the VPC"
    value "${aws_vpc.main.id}"
  end
  
  output :load_balancer_dns_name do
    description "DNS name of the load balancer"
    value "${aws_lb.main.dns_name}"
  end
  
  output :load_balancer_zone_id do
    description "Zone ID of the load balancer"
    value "${aws_lb.main.zone_id}"
  end
  
  output :database_endpoint do
    description "RDS instance endpoint"
    value "${aws_db_instance.main.endpoint}"
    sensitive true
  end
  
  output :database_port do
    description "RDS instance port"
    value "${aws_db_instance.main.port}"
  end
  
  output :s3_bucket_name do
    description "Name of the S3 assets bucket"
    value "${aws_s3_bucket.assets.id}"
  end
  
  output :autoscaling_group_name do
    description "Name of the Auto Scaling Group"
    value "${aws_autoscaling_group.web.name}"
  end
end

# Output the generated Terraform configuration
puts JSON.pretty_generate(synth.synthesis)