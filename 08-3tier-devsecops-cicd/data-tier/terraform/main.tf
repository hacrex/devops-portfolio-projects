terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "devsecops-terraform-state"
    key            = "data-tier/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["devsecops-vpc"]
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_security_group" "app_tier" {
  filter {
    name   = "tag:Name"
    values = ["devsecops-app-sg"]
  }
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption - ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name        = "devsecops-rds-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/devsecops-rds-${var.environment}"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_subnet_group" "main" {
  name       = "devsecops-${var.environment}-db-subnet"
  subnet_ids = data.aws_subnet_ids.private.ids
  tags = {
    Name = "devsecops-${var.environment}-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "devsecops-${var.environment}-rds-sg"
  description = "Security group for RDS - allows traffic only from application tier"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.app_tier.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devsecops-${var.environment}-rds-sg"
  }
}

resource "aws_db_instance" "main" {
  identifier = "devsecops-${var.environment}-db"

  engine               = "postgres"
  engine_version       = "16.1"
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type         = "gp3"
  storage_encrypted    = true
  kms_key_id           = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  multi_az               = var.environment == "production"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  skip_final_snapshot     = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "devsecops-${var.environment}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  copy_tags_to_snapshot   = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn

  deletion_protection = var.environment == "production"
  apply_immediately   = var.environment != "production"

  tags = {
    Name        = "devsecops-${var.environment}-db"
    Environment = var.environment
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "devsecops-${var.environment}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
