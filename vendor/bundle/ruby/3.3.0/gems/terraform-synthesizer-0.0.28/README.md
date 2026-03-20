# terraform-synthesizer

A Ruby DSL for generating Terraform configurations programmatically. Build Terraform resources, providers, variables, and more using clean Ruby syntax.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'terraform-synthesizer'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install terraform-synthesizer

## Usage

The terraform-synthesizer provides a Ruby DSL that maps directly to Terraform's HCL (HashiCorp Configuration Language) constructs. It supports all major Terraform blocks including providers, resources, data sources, variables, locals, and outputs.

### Basic Resource Creation

```ruby
require 'terraform-synthesizer'

synth = TerraformSynthesizer.new

synth.synthesize do
  resource :aws_vpc, :main do
    cidr_block "10.0.0.0/16"
    enable_dns_hostnames true
    enable_dns_support true
    
    tags do
      Name "main-vpc"
      Environment "production"
    end
  end
  
  resource :aws_subnet, :public do
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.1.0/24"
    availability_zone "us-west-2a"
    map_public_ip_on_launch true
  end
end

# Access the generated configuration
puts synth.synthesis.inspect
# Outputs a nested hash structure that mirrors Terraform's JSON format
```

### Converting to Terraform JSON

```ruby
require 'json'

# Generate and pretty-print Terraform JSON configuration
terraform_json = JSON.pretty_generate(synth.synthesis)
puts terraform_json

# Write to a .tf.json file that Terraform can use directly
File.write('infrastructure.tf.json', terraform_json)
```

### Provider Configuration

```ruby
synth.synthesize do
  provider :aws do
    region "us-west-2"
    access_key "your-access-key"
    secret_key "your-secret-key"
  end
  
  provider :datadog do
    api_key "your-api-key"
    app_key "your-app-key"
  end
end
```

### Variables and Locals

```ruby
synth.synthesize do
  variable :environment do
    description "The deployment environment"
    type "string"
    default "development"
  end
  
  locals do
    common_tags do
      Environment "${var.environment}"
      Project "terraform-synthesizer"
    end
  end
  
  resource :aws_instance, :web do
    ami "ami-0c02fb55956c7d316"
    instance_type "t3.micro"
    tags "${local.common_tags}"
  end
end
```

### Data Sources and Outputs

```ruby
synth.synthesize do
  data :aws_ami, :ubuntu do
    most_recent true
    owners ["099720109477"] # Canonical
    
    filter do
      name "name"
      values ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    end
  end
  
  resource :aws_instance, :web do
    ami "${data.aws_ami.ubuntu.id}"
    instance_type "t3.micro"
  end
  
  output :instance_ip do
    description "The public IP of the web instance"
    value "${aws_instance.web.public_ip}"
  end
end
```

### Advanced AWS Infrastructure Example

```ruby
require 'terraform-synthesizer'

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
    end
  end
  
  provider :aws do
    region "us-west-2"
  end
  
  # Variables
  variable :environment do
    description "Environment name (dev, staging, prod)"
    type "string"
    default "dev"
  end
  
  variable :instance_count do
    description "Number of web instances to create"
    type "number"
    default 2
  end
  
  variable :db_password do
    description "Database password"
    type "string"
    sensitive true
  end
  
  # Data sources
  data :aws_availability_zones, :available do
    state "available"
  end
  
  data :aws_ami, :ubuntu do
    most_recent true
    owners ["099720109477"] # Canonical
    
    filter do
      name "name"
      values ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    end
    
    filter do
      name "virtualization-type"
      values ["hvm"]
    end
  end
  
  # Local values
  locals do
    common_tags do
      Environment "${var.environment}"
      Project "terraform-synthesizer-demo"
      ManagedBy "terraform"
    end
    
    availability_zones "${data.aws_availability_zones.available.names}"
  end
  
  # VPC and networking
  resource :aws_vpc, :main do
    cidr_block "10.0.0.0/16"
    enable_dns_hostnames true
    enable_dns_support true
    
    tags "${merge(local.common_tags, { Name = \"main-vpc\" })}"
  end
  
  resource :aws_internet_gateway, :main do
    vpc_id "${aws_vpc.main.id}"
    
    tags "${merge(local.common_tags, { Name = \"main-igw\" })}"
  end
  
  # Public subnets
  resource :aws_subnet, :public do
    count 2
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 1}.0/24"
    availability_zone "${local.availability_zones[count.index]}"
    map_public_ip_on_launch true
    
    tags "${merge(local.common_tags, { 
      Name = \"public-subnet-${count.index + 1}\"
      Type = \"public\"
    })}"
  end
  
  # Private subnets  
  resource :aws_subnet, :private do
    count 2
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 10}.0/24"
    availability_zone "${local.availability_zones[count.index]}"
    
    tags "${merge(local.common_tags, { 
      Name = \"private-subnet-${count.index + 1}\"
      Type = \"private\"
    })}"
  end
  
  # Route table for public subnets
  resource :aws_route_table, :public do
    vpc_id "${aws_vpc.main.id}"
    
    route do
      cidr_block "0.0.0.0/0"
      gateway_id "${aws_internet_gateway.main.id}"
    end
    
    tags "${merge(local.common_tags, { Name = \"public-rt\" })}"
  end
  
  resource :aws_route_table_association, :public do
    count 2
    subnet_id "${aws_subnet.public[count.index].id}"
    route_table_id "${aws_route_table.public.id}"
  end
  
  # Security groups
  resource :aws_security_group, :web do
    name_prefix "web-"
    vpc_id "${aws_vpc.main.id}"
    description "Security group for web servers"
    
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
    
    tags "${merge(local.common_tags, { Name = \"web-sg\" })}"
  end
  
  resource :aws_security_group, :database do
    name_prefix "database-"
    vpc_id "${aws_vpc.main.id}"
    description "Security group for database"
    
    ingress do
      from_port 3306
      to_port 3306
      protocol "tcp"
      security_groups ["${aws_security_group.web.id}"]
    end
    
    tags "${merge(local.common_tags, { Name = \"database-sg\" })}"
  end
  
  # Load balancer
  resource :aws_lb, :web do
    name "web-lb"
    load_balancer_type "application"
    subnets "${aws_subnet.public[*].id}"
    security_groups ["${aws_security_group.web.id}"]
    
    tags local.common_tags
  end
  
  # EC2 instances
  resource :aws_instance, :web do
    count "${var.instance_count}"
    ami "${data.aws_ami.ubuntu.id}"
    instance_type "t3.micro"
    subnet_id "${aws_subnet.public[count.index % length(aws_subnet.public)].id}"
    vpc_security_group_ids ["${aws_security_group.web.id}"]
    
    user_data <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y nginx
      systemctl start nginx
      systemctl enable nginx
      echo "<h1>Web Server ${count.index + 1}</h1>" > /var/www/html/index.html
    EOF
    
    tags "${merge(local.common_tags, { 
      Name = \"web-server-${count.index + 1}\"
      Role = \"webserver\"
    })}"
  end
  
  # RDS Database
  resource :aws_db_subnet_group, :main do
    name "main-db-subnet-group"
    subnet_ids "${aws_subnet.private[*].id}"
    
    tags "${merge(local.common_tags, { Name = \"main-db-subnet-group\" })}"
  end
  
  resource :aws_db_instance, :main do
    identifier "main-database"
    engine "mysql"
    engine_version "8.0"
    instance_class "db.t3.micro"
    allocated_storage 20
    storage_encrypted true
    
    db_name "app_database"
    username "admin"
    password "${var.db_password}"
    
    db_subnet_group_name "${aws_db_subnet_group.main.name}"
    vpc_security_group_ids ["${aws_security_group.database.id}"]
    
    backup_retention_period 7
    backup_window "03:00-04:00"
    maintenance_window "sun:04:00-sun:05:00"
    
    skip_final_snapshot true # Don't do this in production!
    
    tags "${merge(local.common_tags, { 
      Name = \"main-database\"
      Role = \"database\"
    })}"
  end
  
  # S3 bucket for static assets
  resource :aws_s3_bucket, :assets do
    bucket "my-app-assets-${random_id.bucket_suffix.hex}"
    
    tags local.common_tags
  end
  
  resource :random_id, :bucket_suffix do
    byte_length 4
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
  
  output :public_subnet_ids do
    description "IDs of the public subnets"
    value "${aws_subnet.public[*].id}"
  end
  
  output :private_subnet_ids do
    description "IDs of the private subnets"
    value "${aws_subnet.private[*].id}"
  end
  
  output :web_instance_ips do
    description "Public IP addresses of web instances"
    value "${aws_instance.web[*].public_ip}"
  end
  
  output :load_balancer_dns do
    description "DNS name of the load balancer"
    value "${aws_lb.web.dns_name}"
  end
  
  output :database_endpoint do
    description "RDS instance endpoint"
    value "${aws_db_instance.main.endpoint}"
    sensitive true
  end
  
  output :s3_bucket_name do
    description "Name of the S3 assets bucket"
    value "${aws_s3_bucket.assets.id}"
  end
end

# Convert to JSON for Terraform
require 'json'
puts JSON.pretty_generate(synth.synthesis)
```

## Multi-Cloud and Dynamic Examples

### Multi-Provider Configuration

```ruby
synth.synthesize do
  # Configure multiple providers
  provider :aws do
    region "us-west-2"
    alias "west"
  end
  
  provider :aws do
    region "us-east-1"
    alias "east"  
  end
  
  provider :google do
    project "my-project"
    region "us-central1"
  end
  
  # Use aliased providers
  resource :aws_s3_bucket, :west_backup do
    provider "aws.west"
    bucket "my-west-backup-bucket"
  end
  
  resource :aws_s3_bucket, :east_backup do
    provider "aws.east"
    bucket "my-east-backup-bucket"
  end
  
  # Google Cloud resources
  resource :google_storage_bucket, :gcs_backup do
    name "my-gcs-backup-bucket"
    location "US"
  end
end
```

### Dynamic Infrastructure with Loops

```ruby
# Create multiple environments programmatically
environments = ['dev', 'staging', 'prod']

environments.each do |env|
  synth = TerraformSynthesizer.new
  
  synth.synthesize do
    variable :environment do
      default env
    end
    
    resource :aws_vpc, :"#{env}_vpc" do
      cidr_block case env
                 when 'prod' then "10.0.0.0/16"
                 when 'staging' then "10.1.0.0/16" 
                 else "10.2.0.0/16"
                 end
      
      tags do
        Environment env
        Name "#{env}-vpc"
      end
    end
    
    # Different instance sizes per environment
    resource :aws_instance, :"#{env}_web" do
      ami "ami-0c02fb55956c7d316"
      instance_type case env
                    when 'prod' then "t3.large"
                    when 'staging' then "t3.medium"
                    else "t3.micro"
                    end
                    
      tags do
        Environment env
        Name "#{env}-web-server"
      end
    end
  end
  
  # Write environment-specific configuration
  File.write("#{env}.tf.json", JSON.pretty_generate(synth.synthesis))
end
```

### Kubernetes and Container Examples

```ruby
synth.synthesize do
  provider :kubernetes do
    config_path "~/.kube/config"
  end
  
  provider :helm do
    kubernetes do
      config_path "~/.kube/config"
    end
  end
  
  # Kubernetes namespace
  resource :kubernetes_namespace, :app do
    metadata do
      name "my-application"
      labels do
        environment "production"
      end
    end
  end
  
  # Kubernetes deployment
  resource :kubernetes_deployment, :app do
    metadata do
      name "app-deployment"
      namespace "${kubernetes_namespace.app.metadata.0.name}"
    end
    
    spec do
      replicas 3
      selector do
        match_labels do
          app "my-app"
        end
      end
      
      template do
        metadata do
          labels do
            app "my-app"
          end
        end
        
        spec do
          container do
            image "nginx:1.21"
            name "nginx"
            port do
              container_port 80
            end
            
            resources do
              limits do
                cpu "100m"
                memory "128Mi"
              end
              requests do
                cpu "50m"
                memory "64Mi"
              end
            end
          end
        end
      end
    end
  end
  
  # Helm chart deployment
  resource :helm_release, :monitoring do
    name "prometheus"
    repository "https://prometheus-community.github.io/helm-charts"
    chart "kube-prometheus-stack"
    namespace "${kubernetes_namespace.app.metadata.0.name}"
    
    values [<<-EOF
      grafana:
        enabled: true
        adminPassword: "admin123"
      prometheus:
        prometheusSpec:
          retention: "30d"
    EOF
    ]
  end
end
```

### Modular and Reusable Patterns

```ruby
# Define reusable methods for common patterns
class InfrastructureBuilder
  def initialize
    @synth = TerraformSynthesizer.new
  end
  
  def create_vpc(name, cidr, region = "us-west-2")
    @synth.synthesize do
      resource :aws_vpc, name.to_sym do
        cidr_block cidr
        enable_dns_hostnames true
        enable_dns_support true
        
        tags do
          Name name
          Region region
        end
      end
    end
  end
  
  def create_web_tier(vpc_name, subnet_cidr, instance_count = 2)
    @synth.synthesize do
      resource :aws_subnet, :web do
        vpc_id "${aws_vpc.#{vpc_name}.id}"
        cidr_block subnet_cidr
        map_public_ip_on_launch true
        
        tags do
          Name "#{vpc_name}-web-subnet"
          Tier "web"
        end
      end
      
      resource :aws_instance, :web do
        count instance_count
        ami "ami-0c02fb55956c7d316"
        instance_type "t3.micro"
        subnet_id "${aws_subnet.web.id}"
        
        tags do
          Name "web-server-${count.index + 1}"
          Tier "web"
        end
      end
    end
  end
  
  def create_database_tier(vpc_name, subnet_cidrs, engine = "mysql")
    @synth.synthesize do
      # Create multiple subnets for RDS subnet group
      subnet_cidrs.each_with_index do |cidr, index|
        resource :aws_subnet, :"db_subnet_#{index}" do
          vpc_id "${aws_vpc.#{vpc_name}.id}"
          cidr_block cidr
          availability_zone "us-west-2#{('a'.ord + index).chr}"
          
          tags do
            Name "#{vpc_name}-db-subnet-#{index + 1}"
            Tier "database"
          end
        end
      end
      
      resource :aws_db_subnet_group, :main do
        name "#{vpc_name}-db-subnet-group"
        subnet_ids subnet_cidrs.map.with_index { |_, i| "${aws_subnet.db_subnet_#{i}.id}" }
        
        tags do
          Name "#{vpc_name}-db-subnet-group"
        end
      end
      
      resource :aws_db_instance, :main do
        identifier "#{vpc_name}-database"
        engine engine
        instance_class "db.t3.micro"
        allocated_storage 20
        
        db_subnet_group_name "${aws_db_subnet_group.main.name}"
        skip_final_snapshot true
        
        tags do
          Name "#{vpc_name}-database"
          Tier "database"
        end
      end
    end
  end
  
  def synthesis
    @synth.synthesis
  end
end

# Use the builder
builder = InfrastructureBuilder.new
builder.create_vpc("production", "10.0.0.0/16")
builder.create_web_tier("production", "10.0.1.0/24", 3)
builder.create_database_tier("production", ["10.0.10.0/24", "10.0.11.0/24"], "postgresql")

puts JSON.pretty_generate(builder.synthesis)
```

## Supported Resource Types

The synthesizer supports all standard Terraform configuration blocks:

- `terraform` - Terraform configuration and requirements
- `provider` - Provider configurations (AWS, GCP, Azure, Kubernetes, etc.)
- `resource` - Resource definitions (EC2, VPC, RDS, S3, etc.)
- `variable` - Input variables with types and validation
- `locals` - Local computed values and expressions
- `output` - Output values with descriptions and sensitivity
- `data` - Data sources for external resource references

## Key Features

### 🔧 **Full Terraform Compatibility**
Generates valid Terraform JSON that works with all Terraform versions and providers

### 🚀 **Ruby-Powered Flexibility** 
Use Ruby's full programming capabilities: loops, conditionals, methods, classes

### 🌍 **Multi-Cloud Support**
Works with any Terraform provider: AWS, GCP, Azure, Kubernetes, and 3000+ others

### 🏗️ **Modular Architecture**
Build reusable infrastructure components and share them across projects

### 🔒 **Type Safety**
Validates resource types against the supported Terraform block types

### 📝 **Clean Syntax**
Intuitive Ruby DSL that mirrors Terraform's structure while adding Ruby's power

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/drzln/terraform-synthesizer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/drzln/terraform-synthesizer/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [Apache License 2.0](https://opensource.org/licenses/Apache-2.0).