locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )

  private_subnet_cidrs = [
    for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index)
  ]

  api_access_log_group_name = "/aws/${local.name}/api-access"
}
