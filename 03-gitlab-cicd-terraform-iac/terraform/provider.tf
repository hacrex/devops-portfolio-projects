provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-portfolio"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
