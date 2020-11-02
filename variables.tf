variable "vpc_cidr" {
  description = "VPC CIDR"
  default = "10.10.0.0/16"
}
variable "aws_region" {
  description = "Default region"
  default = "us-east-1"
}
variable "profile" {
  description = "Credentials profile"
  default = "personal_user"
}
