variable "region" {
  type = string
  default = "us-east-1"
}

variable "env" {
  type = string
  default = "prod"
}

variable "project_name" {
  type = string
  default = "av-ecs-app"
}

variable "aws_profile" {
  type = string
  default = "av-sandbox"
}