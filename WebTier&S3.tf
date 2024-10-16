# Variables
variable "prefix" {
  type    = string
  default = "GoGreen"
}
# AWS Key Pair Creation
resource "aws_key_pair" "my_key" {
  key_name   = "first-deployer-key"
  public_key = file("/Users/nodiraurazbaeva/.ssh/id_ed25519.pub")
}
variable "instance_count" {
  type    = number
  default = 2  
}
# Local values
locals {
  instance_server = ["GoGreen", "GuildofCloud"]
}
# Data Sources
data "aws_availability_zones" "available" {}
# VPC Creation
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
  
  tags = {
    Name = "${var.prefix}-vpc"
  }
}
# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
# Subnets Creation
resource "aws_subnet" "subnet" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "${var.prefix}-subnet-${count.index + 1}"
  }
}
# Route Table and Association
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "main" {
  count           = length(aws_subnet.subnet)
  subnet_id       = aws_subnet.subnet[count.index].id
  route_table_id  = aws_route_table.main.id
}
# Security Group Module
module "security_gr" {
  source         = "app.terraform.io/GuildofCloud/security_gr/aws"
  version        = "1.0.1"
  vpc_id         = aws_vpc.main.id
  security_groups = {
    "web" = {
      description = "Security Group for Web Tier"
      ingress_rules = [
        {
          to_port     = 22
          from_port   = 22
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "SSH ingress rule"
        },
        {
          to_port     = 80
          from_port   = 80
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "HTTP ingress rule"
        },
        {
          to_port     = 443
          from_port   = 443
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "HTTPS ingress rule"
        }
      ],
      egress_rules = [
        {
          to_port     = 0
          from_port   = 0
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "-1"
          description = "Allow all outbound traffic"
        }
      ]
    },
    "rds" = {
      description = "Security Group for RDS"
      ingress_rules = [
        {
          to_port     = 3306
          from_port   = 3306
          cidr_blocks = ["172.16.0.0/16"]
          protocol    = "tcp"
          description = "Allow MySQL/Aurora access"
        }
      ],
      egress_rules = [
        {
          to_port     = 0
          from_port   = 0
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "-1"
          description = "Allow all outbound traffic"
        }
      ]
    }
  }
}
# EC2 Instances Creation
resource "aws_instance" "server" {
  for_each               = toset(local.instance_server)
  ami                    = "ami-0cf4e1fcfd8494d5b"  # Replace with a valid AMI ID for your region
  instance_type         = "t2.micro"
  key_name              = aws_key_pair.my_key.key_name
  subnet_id             = aws_subnet.subnet[0].id  # Deploying instances in the first subnet
  vpc_security_group_ids = [module.security_gr.my-security_gr_id["web"]]
  
  user_data = <<-EOF
              #!/bin/bash -ex
              {
                # Update the system
                sudo dnf -y update
                # Install Apache and PHP
                sudo dnf -y install httpd php
                # Start and enable Apache
                sudo systemctl start httpd
                sudo systemctl enable httpd
                # Download and extract application
                cd /var/www/html
                sudo wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/CUR-TF-200-ACACAD/studentdownload/lab-app.tgz
                sudo tar xvfz lab-app.tgz
                sudo chown apache:root /var/www/html/rds.conf.php
              } &> /var/log/user_data.log
              EOF
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = each.key
  }
}
# Elastic IP for Each Instance
resource "aws_eip" "instance_ip" {
  for_each = aws_instance.server
  instance = each.value.id
  domain   = "vpc"
}
# Secrets Manager Resource for DB Credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.prefix}-db-credentials-${random_string.secret_suffix.result}"  # Change name to make it unique
  description = "Database credentials for GoGreen"
  tags = {
    Name = "GoGreenDBCredentials"
  }
}
# Random Password for RDS Credentials
resource "random_password" "db_password" {
  length           = 16                     
  special          = false                   # No special characters
  upper            = true                    # Include uppercase letters
  lower            = true                    # Include lowercase letters              
  override_special = ""                      # Ensuring no invalid special characters
}
resource "random_string" "secret_suffix" {
  length  = 8
  special = false  # Generate a simple suffix
}
# Use a null resource to create the secret version after the RDS instance is created
resource "null_resource" "update_db_credentials" {
  depends_on = [aws_db_instance.default]
  provisioner "local-exec" {
    command = <<EOT
      aws secretsmanager put-secret-value --secret-id ${aws_secretsmanager_secret.db_credentials.id} --secret-string '{"username": "dbadmin", "password": "${random_password.db_password.result}", "host": "${aws_db_instance.default.endpoint}"}'
EOT
  }
}
# RDS Instance Creation - Ensure compatibility with instance class and engine
resource "aws_db_instance" "default" {
  identifier         = "${lower(var.prefix)}-db"
  engine             = "mysql"  
  engine_version     = "8.0.32"   # Ensure this is a valid version from your region
  instance_class     = "db.t3.micro"  # Ensure this is a supported instance class
  allocated_storage   = 20  
  storage_type       = "gp2"
  username           = "dbadmin"  
  password           = random_password.db_password.result  
  db_name            = "mydatabase"  
  skip_final_snapshot = true  
  vpc_security_group_ids = [module.security_gr.my-security_gr_id["rds"]]
  db_subnet_group_name = aws_db_subnet_group.default.name
  tags = {
    Name = "${var.prefix}-rds"
  }
}
# DB Subnet Group
resource "aws_db_subnet_group" "default" {
  name       = "${lower(var.prefix)}-db-subnet-group"
  subnet_ids = aws_subnet.subnet[*].id
  tags = {
    Name = "${var.prefix}-db-subnet-group"
  }
}
# S3 Buckets Configuration
resource "aws_s3_bucket" "static_assets" {
  bucket = "${lower(var.prefix)}-static-assets"
  tags = {
    Name = "${var.prefix}-StaticAssets"
  }
}
# Enable Versioning for static assets bucket
resource "aws_s3_bucket_versioning" "static_assets_versioning" {
  bucket = aws_s3_bucket.static_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}
# Enable Lifecycle Configuration for Static Assets to transition to GLACIER after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "static_assets_lifecycle" {
  bucket = aws_s3_bucket.static_assets.id
  
  rule {
    id     = "StaticAssetsLifecycleRule"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}
# Archival Bucket Configuration
resource "aws_s3_bucket" "archival_bucket" {
  bucket = "${lower(var.prefix)}-archive-bucket"
  tags = {
    Name = "${var.prefix}-ArchiveBucket"
  }
}
# Enable Versioning for archival bucket
resource "aws_s3_bucket_versioning" "archival_bucket_versioning" {
  bucket = aws_s3_bucket.archival_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# S3 Bucket Lifecycle Configuration for Archival Bucket
resource "aws_s3_bucket_lifecycle_configuration" "archival_lifecycle" {
  bucket = aws_s3_bucket.archival_bucket.id
  
  rule {
    id     = "MoveToGlacier"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}
# Outputs
output "db_instance_endpoint" {
  value = aws_db_instance.default.endpoint
}
output "instance_public_ips" {
  value = { for k, v in aws_eip.instance_ip : k => v.public_ip }
}
output "db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}
output "subnet_ids" {
  value = aws_subnet.subnet[*].id
}
output "subnet_availability_zones" {
  value = aws_subnet.subnet[*].availability_zone
}
# Load Balancer
resource "aws_lb" "main" {
  name               = "${lower(var.prefix)}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security_gr.my-security_gr_id["web"]]
  subnets            = aws_subnet.subnet[*].id
  enable_deletion_protection = false
  tags = {
    Name = "${var.prefix}-load-balancer"
  }
}
# Target Group
resource "aws_lb_target_group" "main" {
  name     = "${lower(var.prefix)}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold  = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "${var.prefix}-target-group"
  }
}
# Register Instances with Target Group
resource "aws_lb_target_group_attachment" "main" {
  for_each           = aws_instance.server
  target_group_arn   = aws_lb_target_group.main.arn
  target_id          = each.value.id
  port               = 80
}
# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}