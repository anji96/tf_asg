locals {
  public_subnet_cidr = "10.10.10.0/24"
}

provider "aws" {
  region = var.aws_region
  profile = var.profile
  shared_credentials_file = "~/.aws/credentials"
  max_retries = 1
}
resource "aws_vpc" "terra_vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "TerraformVPC"
  }
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_subnet" "terra_private_subnets" {
  vpc_id            =   "${aws_vpc.terra_vpc.id}"
  count             =   2
  availability_zone =   "${data.aws_availability_zones.azs.names[count.index]}"
  cidr_block        =   cidrsubnet(local.public_subnet_cidr, 2, count.index)

  tags = {
    Name = "Terra-app-${count.index}"
  }
}

# -------------   Security Groups -----------------

resource "aws_security_group" "terra_app_server_sg" {
  name        = "terra_app_server_sg"
  description = "Allow all inbound traffic to PrivateSubnet ASG using SSM only"
  vpc_id     = "${aws_vpc.terra_vpc.id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.terra_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra_app_server_sg_endpoints"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

# -----------  VPC endpoints ------------------------

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id            = "${aws_vpc.terra_vpc.id}"
  service_name      = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_subnet.terra_private_subnets.*.id
  security_group_ids = [ aws_security_group.terra_app_server_sg.id ]
  private_dns_enabled = true
}
 
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id            = "${aws_vpc.terra_vpc.id}"
  service_name      = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_subnet.terra_private_subnets.*.id
  security_group_ids = [ aws_security_group.terra_app_server_sg.id ]
  private_dns_enabled = true
}
 
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = "${aws_vpc.terra_vpc.id}"
  service_name      = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_subnet.terra_private_subnets.*.id
  security_group_ids = [ aws_security_group.terra_app_server_sg.id ]
  private_dns_enabled = true
}

# -------------- IAM role for EC2 instances for connecting using SSM ---------

resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-private-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json
}
 
data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
 
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
 
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}
 
resource "aws_iam_role_policy_attachment" "ec2_ssm_role_policy_attachment" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# =================================================

data "template_file" "user_data" {
  template = "${file("userdata.sh")}"
}

resource "aws_launch_configuration" "appServers" {
    name_prefix = "app-"
    image_id = "ami-0947d2ba12ee1ff75" 
    user_data  = "${data.template_file.user_data.rendered}"
    instance_type = "t2.micro"
    key_name = "chanakg"
    iam_instance_profile = "${aws_iam_instance_profile.ec2_ssm_instance_profile.id}"
    security_groups = ["${aws_security_group.terra_app_server_sg.id}"]
      lifecycle {
         create_before_destroy = true
      }
}

resource "aws_autoscaling_group" "private_asg" {
  # Force a redeployment when launch configuration changes.
  # This will reset the desired capacity if it was changed due to
  # autoscaling events.
  name = "${aws_launch_configuration.appServers.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 3
  health_check_type    = "EC2"
  launch_configuration = "${aws_launch_configuration.appServers.name}"
  vpc_zone_identifier  = "${aws_subnet.terra_private_subnets.*.id}"

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }
}


