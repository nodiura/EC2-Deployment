# # Variables
# variable "prefix" {
#   type    = string
#   default = "GoGreen"
# }
# # AWS Key Pair Creation
# resource "aws_key_pair" "my_key" {
#   key_name   = "fist-deployer-key"
#   public_key = file("/Users/nodiraurazbaeva/.ssh/id_ed25519.pub")  # Use an absolute path if needed
# }
# variable "instance_count" {
#   type    = number
#   default = 2  # Set to 2 for two instances
# }
# # Local values
# locals {
#   instance_server = ["GoGreen", "GuildofCloud"]  
# }
# # Data Sources
# data "aws_availability_zones" "available" {}
# # VPC Creation
# resource "aws_vpc" "main" {
#   cidr_block = "172.16.0.0/16"
  
#   tags = {
#     Name = "${var.prefix}-vpc"
#   }
# }
# # Internet Gateway
# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id
# }
# # Subnets Creation
# resource "aws_subnet" "subnet" {
#   count             = 2
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
#   availability_zone = element(data.aws_availability_zones.available.names, count.index)
#   tags = {
#     Name = "${var.prefix}-subnet-${count.index + 1}"
#   }
# }
# # Route Table and Association
# resource "aws_route_table" "main" {
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
# }
# resource "aws_route_table_association" "main" {
#   count           = length(aws_subnet.subnet)
#   subnet_id       = aws_subnet.subnet[count.index].id
#   route_table_id  = aws_route_table.main.id
# }
# # Security Group Module
# module "security_gr" {
#   source         = "app.terraform.io/GuildofCloud/security_gr/aws"
#   version        = "1.0.1"
#   vpc_id         = aws_vpc.main.id
  
#   security_groups = {
#     "web" = {
#       description = "Security Group for Web Tier"
#       ingress_rules = [
#         {
#           to_port     = 22
#           from_port   = 22
#           cidr_blocks = ["0.0.0.0/0"]
#           protocol    = "tcp"
#           description = "SSH ingress rule"
#         },
#         {
#           to_port     = 80
#           from_port   = 80
#           cidr_blocks = ["0.0.0.0/0"]
#           protocol    = "tcp"
#           description = "HTTP ingress rule"
#         },
#         {
#           to_port     = 443
#           from_port   = 443
#           cidr_blocks = ["0.0.0.0/0"]
#           protocol    = "tcp"
#           description = "HTTPS ingress rule"
#         }
#       ],
#       egress_rules = [
#         {
#           to_port     = 0
#           from_port   = 0
#           cidr_blocks = ["0.0.0.0/0"]
#           protocol    = "-1"
#           description = "Allow all outbound traffic"
#         }
#       ]
#     },
#     "rds" = {
#       description = "Security Group for RDS"
#       ingress_rules = [
#         {
#           to_port     = 3306
#           from_port   = 3306
#           cidr_blocks = ["172.16.0.0/16"]  # Allow access from VPC
#           protocol    = "tcp"
#           description = "Allow MySQL/Aurora access"
#         }
#       ],
#       egress_rules = [
#         {
#           to_port     = 0
#           from_port   = 0
#           cidr_blocks = ["0.0.0.0/0"]
#           protocol    = "-1"
#           description = "Allow all outbound traffic"
#         }
#       ]
#     }
#   }
# }
# # EC2 Instances Creation
# resource "aws_instance" "server" {
#   for_each               = toset(local.instance_server)
#   ami                    = "ami-0cf4e1fcfd8494d5b"  # Replace with a valid AMI ID for your region
#   instance_type         = "t2.micro"
#   key_name              = aws_key_pair.my_key.key_name
#   subnet_id             = aws_subnet.subnet[0].id  # Deploying instances in the first subnet
#   vpc_security_group_ids = [module.security_gr.my-security_gr_id["web"]]
#   user_data = <<-EOF
#               #!/bin/bash -ex
#               {
#                 # Update the system
#                 sudo dnf -y update
#                 # Install Apache and PHP
#                 sudo dnf -y install httpd php
#                 # Start and enable Apache
#                 sudo systemctl start httpd
#                 sudo systemctl enable httpd
#                 # Download and extract application
#                 cd /var/www/html
#                 sudo wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/CUR-TF-200-ACACAD/studentdownload/lab-app.tgz
#                 sudo tar xvfz lab-app.tgz
#                 sudo chown apache:root /var/www/html/rds.conf.php
#               } &> /var/log/user_data.log
#               EOF
#   lifecycle {
#     create_before_destroy = true
#   }
#   tags = {
#     Name = each.key
#   }
# }
# # Elastic IP for Each Instance
# resource "aws_eip" "instance_ip" {
#   for_each = aws_instance.server
#   instance = each.value.id
#   domain   = "vpc"
# }
# # RDS Instance Creation
# resource "aws_db_instance" "default" {
#   identifier         = "${lower(var.prefix)}-db"
#   engine             = "mysql"  # Change if using a different database engine
#   engine_version     = "8.0"   # Specify the version of MySQL
#   instance_class     = "db.t3.micro"
#   allocated_storage   = 20  # Minimum storage for RDS
#   storage_type       = "gp2"
#   username           = "admin"
#   password           = "YourPassword123!"  # Change this to a strong password
#   db_name            = "mydatabase"  # Initial database name
#   skip_final_snapshot = true  # Set to false for production environments
#   vpc_security_group_ids = [module.security_gr.my-security_gr_id["rds"]]
#   db_subnet_group_name = aws_db_subnet_group.default.name
#   tags = {
#     Name = "${var.prefix}-rds"
#   }
# }
# # DB Subnet Group
# resource "aws_db_subnet_group" "default" {
#   name       = "${lower(var.prefix)}-db-subnet-group"
#   subnet_ids = aws_subnet.subnet[*].id
#   tags = {
#     Name = "${var.prefix}-db-subnet-group"
#   }
# }
# # Outputs
# output "instance_public_ips" {
#   value = { for k, v in aws_eip.instance_ip : k => v.public_ip }
# }
# output "subnet_ids" {
#   value = aws_subnet.subnet[*].id
# }
# output "subnet_availability_zones" {
#   value = aws_subnet.subnet[*].availability_zone
# }
# output "rds_endpoint" {
#   value = aws_db_instance.default.endpoint
# }
# # Load Balancer
# resource "aws_lb" "main" {
#   name               = "${var.prefix}-lb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [module.security_gr.my-security_gr_id["web"]]
#   subnets            = aws_subnet.subnet[*].id
#   enable_deletion_protection = false
#   tags = {
#     Name = "${var.prefix}-load-balancer"
#   }
# }
# # Target Group
# resource "aws_lb_target_group" "main" {
#   name     = "${var.prefix}-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.main.id
#   health_check {
#     path                = "/"
#     interval            = 30
#     timeout             = 5
#     healthy_threshold  = 2
#     unhealthy_threshold = 2
#   }
#   tags = {
#     Name = "${var.prefix}-target-group"
#   }
# }
# # Register Instances with Target Group
# resource "aws_lb_target_group_attachment" "main" {
#   for_each           = aws_instance.server
#   target_group_arn   = aws_lb_target_group.main.arn
#   target_id          = each.value.id
#   port               = 80
# }
# # ALB Listener
# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 80
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main.arn
#   }
# }