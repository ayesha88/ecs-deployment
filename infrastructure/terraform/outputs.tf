output "ecr_repository_url" {
  value = aws_ecr_repository.ecr.repository_url
}

output "site_url" {
  value = var.env == "prod" ? "${var.domain_name}" : "${var.env}.${var.domain_name}"
}