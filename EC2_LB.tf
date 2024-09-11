variable "prefix" {
  type    = string
  default = "project-aug-28"
}
# Create a map of instance configurations for the loop.
variable "instance_count" {
  type    = number
  default = 3
}
# Create a list for instance names
locals {
  instance_names = [for i in range(var.instance_count) : "${var.prefix}-ec2-${i + 1}"]
}
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = join("-", [var.prefix, "vpc"])
  }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "172.16.0.0/24"
  tags = {
    Name = join("-", [var.prefix, "subnet"])
  }
}
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}
module "security_gr" {
  source  = "app.terraform.io/027-spring-cld/security_gr/aws"
  version = "1.0.1"
  vpc_id  = aws_vpc.main.id
  security_groups = {
    "web" = {
      description = "Security Group for Web Tier"
      ingress_rules = [
        {
          to_port     = 22
          from_port   = 22
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "ssh ingress rule"
        },
        {
          to_port     = 80
          from_port   = 80
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "http ingress rule"
        },
        {
          to_port     = 443
          from_port   = 443
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "tcp"
          description = "https ingress rule"
        }
      ],
      egress_rules = [
        {
          to_port     = 0
          from_port   = 0
          cidr_blocks = ["0.0.0.0/0"]
          protocol    = "-1" # This allows all outbound traffic
          description = "allow all outbound traffic"
        }
      ]
    }
  }
}
resource "aws_instance" "server" {
  for_each               = toset(local.instance_names)
  ami                    = "ami-066784287e358dad1"
  instance_type         = "t2.micro"
  key_name              = aws_key_pair.deployer.key_name
  subnet_id             = aws_subnet.main.id
  vpc_security_group_ids = [module.security_gr.my-security_gr_id["web"]]
  
  user_data = <<-EOF
                     #!/bin/bash
                     sudo yum update -y
                     sudo yum install -y httpd
                     sudo systemctl start httpd.service
                     sudo systemctl enable httpd.service
                     echo "<h1> Hello World from Nodira </h1>" | sudo tee /var/www/html/index.html
  EOF
  tags = {
    Name = each.key  # Use the instance name
  }
}
# Elastic IP resource for each instance
resource "aws_eip" "instance_ip" {
  for_each = aws_instance.server
  instance = each.value.id
  domain   = "vpc"
}
output "instance_public_ips" {
  value = { for k, v in aws_eip.instance_ip : k => v.public_ip }
}
variable "public_key_content" {
  description = "The content of the public key"
  type        = string
}
resource "aws_key_pair" "deployer" {
  key_name   = "my-key-name"
  public_key = var.public_key_content
}
# Load Balancer
resource "aws_lb" "main" {
  name               = "${var.prefix}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security_gr.my-security_gr_id["web"]]
  subnets            = [aws_subnet.main.id]
  enable_deletion_protection = false
  tags = {
    Name = join("-", [var.prefix, "load-balancer"])
  }
}
# Target group
resource "aws_lb_target_group" "main" {
  name     = "${var.prefix}-tg"
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
    Name = join("-", [var.prefix, "target-group"])
  }
}
# Register the instances with the target group
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