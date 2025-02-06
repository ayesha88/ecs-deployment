# Table of Contents

- [Access App URL](#access-app-url)
- [Architecture Overview](#architecture-overview)
- [Prerequisites to Setting Up Cluster](#prerequisites-to-setting-up-cluster-one-time-ops)
- [AWS ECS Deployment & Terraform Infrastructure Pipeline](#aws-ecs-deployment--terraform-infrastructure-pipeline)
  - [Terraform Infrastructure Pipeline](#terraform-infrastructure-pipeline)
  - [Deployment Workflow](#deployment-workflow)
- [Destroying Terraform Resources](#destroying-terraform-resources)

# Access app url
- Prod: https://autoverify-app.com/health
- Stage: https://stage.autoverify-app.com/health (stack is not up)

# Architecture Overview
The infrastructure is designed to host a containerized application on AWS ECS (Elastic Container Service) using the EC2 launch type. It ensures high availability, security, and scalability by using VPC, ALB (Application Load Balancer), Autoscaling, IAM, Route53, and CloudWatch Logs.

## Infrastructure Components
### Networking (VPC, Subnets, NAT, Internet Gateway)
- **VPC (`aws_vpc`)**: Creates an isolated network for AWS resources.
- **Public Subnets (`aws_subnet.public_subnet`)**: Hosts NAT gateways and ALB.
- **Private Subnets (`aws_subnet.private_subnet`)**: Hosts ECS instances.
- **Internet Gateway (`aws_internet_gateway`)**: Allows public traffic.
- **Route Tables (`aws_route_table`)**: Manages routes for public and private subnets.
- **NAT Gateway (`aws_nat_gateway`)**: Allows private subnets to access the internet without being exposed.

## Security Groups
- **Load Balancer Security Group (`aws_security_group.load_balancer_sg`)**: Allows inbound traffic on ports 80 and 443.
- **EC2 Security Group (`aws_security_group.ec2_sg`)**: Allows inbound traffic from ALB and all outbound traffic.

## Compute & Scaling
- **ECS Cluster (`aws_ecs_cluster`)**: Manages ECS tasks.
- **ECS Capacity Provider (`aws_ecs_capacity_provider`)**: Links ECS with Auto Scaling.
- **Auto Scaling Group (`aws_autoscaling_group`)**: Manages EC2 instances.
- **Launch Template (`aws_launch_template`)**: Defines the EC2 configuration.
- **IAM Roles (`aws_iam_role`)**: Manages permissions for EC2, ECS, and Auto Scaling.

## Application Load Balancer (ALB)
- **ALB (`aws_lb.application_load_balancer`)**: Distributes traffic.
- **Target Group (`aws_alb_target_group`)**: Routes requests to container instances.
- **ALB Listeners (`aws_lb_listener`)**: Redirects HTTP to HTTPS and forwards HTTPS requests to ECS.

## ECS & Containerization
- **ECS Task Definition (`aws_ecs_task_definition`)**: Defines container settings.
- **ECS Service (`aws_ecs_service`)**: Deploys and manages containers.
- **ECR Repository (`aws_ecr_repository`)**: Stores container images.

## Logging & Monitoring
- **CloudWatch Logs (`aws_cloudwatch_log_group`)**: Captures ECS logs.
- **Auto Scaling Policies (`aws_appautoscaling_policy`)**: Adjusts ECS tasks based on CPU and memory utilization.

## Domain Name System (DNS) & SSL
- **Route 53 (`aws_route53_record`)**: Creates a DNS record for ALB.
- **ACM Certificate (`data.aws_acm_certificate`)**: Provides an SSL certificate.

# Prerequisites to Setting Up Cluster (one time ops)
- A registered domain name in AWS Route 53. (domain used in this stack is autoverify-app.com)
- An AWS Certificate Manager (ACM) certificate for the domain.
- A CloudFormation stack for Terraform S3 state storage and DynamoDB lock table (`infrastructure/cloudformation/terraform-state-resources`).

## AWS ECS Deployment & Terraform Infrastructure Pipeline
This repository contains GitHub Actions workflows for deploying a containerized application to AWS ECS and managing infrastructure using Terraform.

## Terraform Infrastructure Pipeline
This workflow automates Terraform execution to provision and manage AWS infrastructure.
### Steps:
1. Navigate to the **Actions** tab in GitHub.
2. Select **Terraform Infrastructure Pipeline**.
3. Click **Run workflow** and choose the desired environment (`stage` or `prod`).
4. Wait for the workflow to complete.

## Deployment Workflow
This workflow handles building, pushing, and deploying a Docker container to AWS ECS.
### Steps:
1. Navigate to the **Actions** tab in GitHub.
2. Select **Deploy to AWS ECS**.
3. Click **Run workflow** and choose the desired environment (`stage` or `prod`).
4. Wait for the workflow to complete.

## Destroying Terraform Resources
To remove infrastructure managed by Terraform:
1. Configure `[av-sandbox]` AWS profile in `~/.aws/credentials`.
2. Navigate to the appropriate environment directory:
   ```sh
   cd infrastructure/terraform/environments/prod  # or stage
   ```
3. Run the Terraform destroy command:
   ```sh
   terraform destroy
   ```

