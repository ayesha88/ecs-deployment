variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = number
}

variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ecs_task_desired_count" {
  type = number
}

variable "ecs_task_deployment_minimum_healthy_percent" {
  type = number
}

variable "ecs_task_deployment_maximum_percent" {
  type = number
}

variable "container_name" {
  type = string
}

variable "container_port" {
  type = number
}

variable "ecs_task_cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "log_retention_in_days" {
  type = number
}

variable "ecs_task_max_count" {
  type = number
}

variable "ecs_task_min_count" {
  type = number
}

variable "cap_minimum_scaling_step_size" {
  type = number
}

variable "cap_maximum_scaling_step_size" {
  type = number
}

variable "cap_target_capacity" {
  type = number
}

variable "cpu_target_tracking_desired_value" {
  type = number
}

variable "memory_target_tracking_desired_value" {
  type = number
}

variable "autoscaling_min_size" {
  type = number
}

variable "autoscaling_max_size" {
  type = number
}

variable "domain_name" {
  type = string
  default = "autoverify-app.com"
}
