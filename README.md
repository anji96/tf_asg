# tf_asg

Terraform

Create an asg in private subnet without bastion hosts..

Use case:

Using Terraform create a VPC and launch an auto scaling group where the instances are in a private subnet. 
With your instances in the private subnet, configure it so a system administrator can access the server to debug an issue, without going through a public bastion host.
