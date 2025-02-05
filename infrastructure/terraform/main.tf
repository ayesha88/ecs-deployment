## Create VPC
resource "aws_vpc" "ecs_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.env}-${var.project_name}"
  }
}

## Create Internet Gateway for the public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name = "${var.env}-${var.project_name}-internet-gateway"
  }
}

## Get all AZs available in the region
data "aws_availability_zones" "available_zones" {}

# Create one public subnet per AZ
resource "aws_subnet" "public_subnet" {
  count                   = var.availability_zones
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.ecs_vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env}-${var.project_name}-public-subnet-${count.index}"
  }
}

## Create public subnet Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.env}-${var.project_name}-public-route-table"
  }
}

## Associate Public Route Table with Public Subnets
resource "aws_route_table_association" "public_rt_association" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

## Create Elastic IPs (EIP) for NAT Gateways
resource "aws_eip" "eip" {
  count = var.availability_zones

  tags = {
    Name = "${var.env}-${var.project_name}-eip-${count.index}"
  }
}

## Create one NAT Gateway per AZ in Public Subnets
resource "aws_nat_gateway" "nat_gateway" {
  count         = var.availability_zones
  subnet_id     = aws_subnet.public_subnet[count.index].id
  allocation_id = aws_eip.eip[count.index].id

  tags = {
    Name = "${var.env}-${var.project_name}-nat-gateway-${count.index}"
  }
}

## Create one private subnet per AZ
resource "aws_subnet" "private_subnet" {
  count             = var.availability_zones
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + var.availability_zones)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.ecs_vpc.id

  tags = {
    Name = "${var.env}-${var.project_name}-private-subnet-${count.index}"
  }
}

## Create Private Route Tables (One per AZ)
resource "aws_route_table" "private_rt" {
  count  = var.availability_zones
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }

  tags = {
    Name = "${var.env}-${var.project_name}-private-rt-${count.index}"
  }
}

## Associate Private Route Tables with Private Subnets
resource "aws_route_table_association" "private_rt_association" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

resource "aws_ecr_repository" "ecr" {
  name  = "${var.env}-${var.project_name}-ecr"
}

## Get most recent AMI for an ECS-optimized Amazon Linux 2 instance
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  owners = ["amazon"]
}

## Launch template for all EC2 instances that are part of the ECS cluster

resource "aws_launch_template" "ecs_launch_template" {
  name                   = "${var.env}-${var.project_name}-launch-template"
  image_id               = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  user_data               = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    ENV_NAME     = var.env
    PROJECT_NAME = var.project_name
  }))
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_instance_role_profile.arn
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp2"
    }
  }

}

## Creates IAM Role to attach to EC2 Instances
resource "aws_iam_role" "ec2_role" {
  name               = "${var.env}-${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_instance_role_policy.json

}

resource "aws_iam_instance_profile" "ec2_instance_role_profile" {
  name = "${var.env}-${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_role.id

}

data "aws_iam_policy_document" "ec2_instance_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = [
        "ec2.amazonaws.com",
        "ecs.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_instance_role_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_instance_role_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

## Creates an ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.env}-${var.project_name}-ecs"
}

## Creates ECS Service
resource "aws_ecs_service" "ecs_service" {
  name                               = "${var.env}-${var.project_name}-ecs-service"
  iam_role                           = aws_iam_role.ecs_service_role.arn
  cluster                            = aws_ecs_cluster.ecs_cluster.id
  task_definition                    = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count                      = var.ecs_task_desired_count
  deployment_minimum_healthy_percent = var.ecs_task_deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.ecs_task_deployment_maximum_percent

  load_balancer {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  ## Spread tasks evenly accross all Availability Zones for High Availability
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
  
  ## Make use of all available space on the Container Instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  ## Do not update desired count again to avoid a reset to this number on every deployment
  # lifecycle {
  #   ignore_changes = [desired_count]
  # }
}

## Create service-linked role used by the ECS Service to manage the ECS Cluster
resource "aws_iam_role" "ecs_service_role" {
  name               = "${var.env}-${var.project_name}-ecs-service-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_policy.json
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com",]
    }
  }
}

resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name   = "${var.env}-${var.project_name}-ecs-service-role-policy"
  policy = data.aws_iam_policy_document.ecs_service_role_policy.json
  role   = aws_iam_role.ecs_service_role.id
}

data "aws_iam_policy_document" "ecs_service_role_policy" {
  statement {
    effect  = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets",
      "ec2:DescribeTags",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutSubscriptionFilter",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

## Creates ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family             = "${var.env}-${var.project_name}-task-definition"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_iam_role.arn

  container_definitions = jsonencode([
    {
      name         = var.container_name
      image        = "${aws_ecr_repository.ecr.repository_url}"
      cpu          = var.ecs_task_cpu
      memory       = var.memory
      essential    = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options   = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name,
          "awslogs-region"        = var.region
        }
      }
    }
  ])
}

## Create log group for our service
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "${var.env}-${var.project_name}-ecs-log-group"
  retention_in_days = var.log_retention_in_days
}

## IAM Role for ECS Task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.env}-${var.project_name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role_policy.json
}

data "aws_iam_policy_document" "task_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_iam_role" {
  name               = "${var.env}-${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role_policy.json
}

## Creates Capacity Provider linked with ASG and ECS Cluster
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name  = "${var.env}-${var.project_name}-ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_autoscaling_group.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = var.cap_maximum_scaling_step_size
      minimum_scaling_step_size = var.cap_minimum_scaling_step_size
      status                    = "ENABLED"
      target_capacity           = var.cap_target_capacity
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_providers" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]
}

## Define Target Tracking on ECS Cluster Task level
resource "aws_appautoscaling_target" "ecs_app_scaling_target" {
  max_capacity       = var.ecs_task_max_count
  min_capacity       = var.ecs_task_min_count
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.ecs_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

## Policy for CPU tracking
resource "aws_appautoscaling_policy" "ecs_cpu_scaling_policy" {
  name               = "${var.env}-${var.project_name}-ecs-cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_app_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_app_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_app_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.cpu_target_tracking_desired_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

## Policy for memory tracking
resource "aws_appautoscaling_policy" "ecs_memory_scaling_policy" {
  name               = "${var.env}-${var.project_name}-ecs-memory-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_app_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_app_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_app_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.memory_target_tracking_desired_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

## Creates an ASG linked with our main VPC
resource "aws_autoscaling_group" "ecs_autoscaling_group" {
  name                  = "${var.env}-${var.project_name}-asg"
  max_size              = var.autoscaling_max_size
  min_size              = var.autoscaling_min_size
  vpc_zone_identifier   = aws_subnet.private_subnet[*].id
  health_check_type     = "EC2"
  protect_from_scale_in = true

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.env}-${var.project_name}"
    propagate_at_launch = true
  }
}

# Get acm cerificate for the domain
data "aws_acm_certificate" "certificate" {
  domain   = var.domain_name
  types    = ["AMAZON_ISSUED"]
  most_recent = true
}

# create application load balancer
resource "aws_lb" "application_load_balancer" {
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.load_balancer_sg.id]
  subnets                    = aws_subnet.public_subnet[*].id

  tags = {
    Name  = "${var.env}-${var.project_name}-alb"
  }
}

resource "aws_lb_listener" "http_redirect_https_alb_listner" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  protocol          = "HTTP"
  port              = 80

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

}

resource "aws_lb_listener" "https_alb_listener" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  protocol          = "HTTPS"
  port              = 443
  certificate_arn   = data.aws_acm_certificate.certificate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }

}

# create target group for ALB
resource "aws_alb_target_group" "alb_target_group" {
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name  = "${var.env}-${var.project_name}-alb-target-group"
  }
}

# Define the security group for the Load Balancer
resource "aws_security_group" "load_balancer_sg" {
  description = "Allow incoming connections for load balancer"
  vpc_id      = aws_vpc.ecs_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming HTTP connections"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.env}-${var.project_name}-alb-sg"
  }
}

## SG for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = "${var.env}-${var.project_name}-ec2-sg"
  description = "Security group for EC2 instances in ECS cluster"
  vpc_id      = aws_vpc.ecs_vpc.id

  ingress {
    description     = "Allow ingress traffic from ALB on HTTP on ephemeral ports"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.env}-${var.project_name}-ec2-sg"
  }
}

## Get route53 zone id for domain 
data "aws_route53_zone" "domain_hosted_zone" {
  name = var.domain_name
}

## Create a record to point to ALB
resource "aws_route53_record" "hosted_zone_record" {
  zone_id = data.aws_route53_zone.domain_hosted_zone.zone_id
  name    = var.env == "prod" ? "${var.domain_name}" : "${var.env}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.application_load_balancer.dns_name
    zone_id                = aws_lb.application_load_balancer.zone_id
    evaluate_target_health = true
  }
}