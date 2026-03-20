#!/usr/bin/env ruby
# Basic VPC Example
# Creates a VPC with public and private subnets, internet gateway, and NAT gateway

require 'terraform-synthesizer'
require 'json'

synth = TerraformSynthesizer.new

synth.synthesize do
  # Provider configuration
  provider :aws do
    region "us-west-2"
  end
  
  # Variables
  variable :vpc_cidr do
    description "CIDR block for VPC"
    type "string"
    default "10.0.0.0/16"
  end
  
  variable :environment do
    description "Environment name"
    type "string"
    default "development"
  end
  
  # Data sources
  data :aws_availability_zones, :available do
    state "available"
  end
  
  # Local values
  locals do
    common_tags do
      Environment "${var.environment}"
      Project "basic-vpc-example"
      ManagedBy "terraform-synthesizer"
    end
  end
  
  # VPC
  resource :aws_vpc, :main do
    cidr_block "${var.vpc_cidr}"
    enable_dns_hostnames true
    enable_dns_support true
    
    tags "${merge(local.common_tags, { Name = \"main-vpc\" })}"
  end
  
  # Internet Gateway
  resource :aws_internet_gateway, :main do
    vpc_id "${aws_vpc.main.id}"
    
    tags "${merge(local.common_tags, { Name = \"main-igw\" })}"
  end
  
  # Public Subnets
  resource :aws_subnet, :public do
    count 2
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 1}.0/24"
    availability_zone "${data.aws_availability_zones.available.names[count.index]}"
    map_public_ip_on_launch true
    
    tags "${merge(local.common_tags, { 
      Name = \"public-subnet-${count.index + 1}\"
      Type = \"public\"
    })}"
  end
  
  # Private Subnets
  resource :aws_subnet, :private do
    count 2
    vpc_id "${aws_vpc.main.id}"
    cidr_block "10.0.${count.index + 10}.0/24"
    availability_zone "${data.aws_availability_zones.available.names[count.index]}"
    
    tags "${merge(local.common_tags, { 
      Name = \"private-subnet-${count.index + 1}\"
      Type = \"private\"
    })}"
  end
  
  # Elastic IP for NAT Gateway
  resource :aws_eip, :nat do
    domain "vpc"
    depends_on ["aws_internet_gateway.main"]
    
    tags "${merge(local.common_tags, { Name = \"nat-eip\" })}"
  end
  
  # NAT Gateway
  resource :aws_nat_gateway, :main do
    allocation_id "${aws_eip.nat.id}"
    subnet_id "${aws_subnet.public[0].id}"
    
    tags "${merge(local.common_tags, { Name = \"main-nat\" })}"
  end
  
  # Route Table for Public Subnets
  resource :aws_route_table, :public do
    vpc_id "${aws_vpc.main.id}"
    
    route do
      cidr_block "0.0.0.0/0"
      gateway_id "${aws_internet_gateway.main.id}"
    end
    
    tags "${merge(local.common_tags, { Name = \"public-rt\" })}"
  end
  
  # Route Table for Private Subnets
  resource :aws_route_table, :private do
    vpc_id "${aws_vpc.main.id}"
    
    route do
      cidr_block "0.0.0.0/0"
      nat_gateway_id "${aws_nat_gateway.main.id}"
    end
    
    tags "${merge(local.common_tags, { Name = \"private-rt\" })}"
  end
  
  # Route Table Associations
  resource :aws_route_table_association, :public do
    count 2
    subnet_id "${aws_subnet.public[count.index].id}"
    route_table_id "${aws_route_table.public.id}"
  end
  
  resource :aws_route_table_association, :private do
    count 2
    subnet_id "${aws_subnet.private[count.index].id}"
    route_table_id "${aws_route_table.private.id}"
  end
  
  # Outputs
  output :vpc_id do
    description "ID of the VPC"
    value "${aws_vpc.main.id}"
  end
  
  output :vpc_cidr_block do
    description "CIDR block of the VPC"
    value "${aws_vpc.main.cidr_block}"
  end
  
  output :public_subnet_ids do
    description "IDs of the public subnets"
    value "${aws_subnet.public[*].id}"
  end
  
  output :private_subnet_ids do
    description "IDs of the private subnets"  
    value "${aws_subnet.private[*].id}"
  end
  
  output :internet_gateway_id do
    description "ID of the Internet Gateway"
    value "${aws_internet_gateway.main.id}"
  end
  
  output :nat_gateway_id do
    description "ID of the NAT Gateway"
    value "${aws_nat_gateway.main.id}"
  end
end

# Output the generated Terraform configuration
puts JSON.pretty_generate(synth.synthesis)