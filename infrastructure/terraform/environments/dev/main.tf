// Configuring S3 and DDB for state storage and lock
terraform {
    backend "s3" {
        profile = "av-sandbox"
        encrypt = true
        bucket = "av-ecs-app-state-bucket"
        dynamodb_table = "av-ecs-app-tf-state-lock"
        region = "us-east-1"
        key = "terraform/stack/us-east-1/dev/terraform.tfstate"
    }
}

// Configuring provider
provider "aws" {
    // Provide access key and id otherwise will get one automatically from AWS toolkit
    profile = var.aws_profile
    region = var.region
    default_tags {
        tags = {
            Environment = var.env
            Project     = var.project_name
        }
    }
}

module "main" {
    source = "../../"
    vpc_cidr = "10.0.0.0/16"
    availability_zones = 2
    project_name = var.project_name
    env = var.env
    region = var.region
    instance_type = "t3.micro"
    ecs_task_desired_count = 2  # Number of instances of the task definition to place and keep running
    ecs_task_deployment_minimum_healthy_percent = 50 #  Lower limit (as a percentage of the service's desiredCount) of the number of running tasks that must remain running and healthy in a service during a deployment
    ecs_task_deployment_maximum_percent = 100 # Upper limit (as a percentage of the service's desiredCount) of the number of running tasks that can be running in a service during a deployment
    container_name = "av-ecs-app"
    container_port = 8000
    ecs_task_cpu = 100  # Number of cpu units used by the task
    memory = 200    # Amount (in MiB) of memory used by the task
    log_retention_in_days = 7
    ecs_task_max_count = 10 # maximum number of tasks that may run simultaneously
    ecs_task_min_count = 2  # minimum number of tasks that may run simultaneously
    cap_minimum_scaling_step_size = 1   # min EC2 Instances the capacity provider may simultaneously increase
    cap_maximum_scaling_step_size = 5   # max EC2 Instances the capacity provider may simultaneously increase
    cap_target_capacity = 100   # Target utilization for the capacity provider
    cpu_target_tracking_desired_value = 70 # Target value for the cpu usage metric
    memory_target_tracking_desired_value = 70 # Target value for the memory usage metric
    autoscaling_min_size = 2
    autoscaling_max_size = 4
}