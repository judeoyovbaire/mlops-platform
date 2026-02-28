# RDS PostgreSQL for MLflow Metadata Backend

resource "aws_db_subnet_group" "mlflow" {
  name       = "${var.cluster_name}-mlflow"
  subnet_ids = module.vpc.private_subnets

  tags = var.tags
}

resource "aws_security_group" "mlflow_rds" {
  name        = "${var.cluster_name}-mlflow-rds"
  description = "Security group for MLflow RDS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL access from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # Restrict egress to VPC CIDR only - RDS doesn't need internet access
  egress {
    description = "Allow egress within VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags
}

resource "aws_db_instance" "mlflow" {
  identifier = "${var.cluster_name}-mlflow"

  engine                = "postgres"
  engine_version        = var.mlflow_db_engine_version
  instance_class        = var.mlflow_db_instance_class
  allocated_storage     = var.mlflow_db_allocated_storage
  max_allocated_storage = var.mlflow_db_max_allocated_storage

  db_name  = "mlflow"
  username = "mlflow"

  # Use RDS-managed secrets via AWS Secrets Manager (no plaintext passwords in Terraform state)
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = [aws_security_group.mlflow_rds.id]

  # Security settings
  publicly_accessible = false
  storage_encrypted   = true
  kms_key_id          = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null

  # Backup and recovery settings
  backup_retention_period   = var.mlflow_db_backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  skip_final_snapshot       = var.mlflow_db_skip_final_snapshot
  final_snapshot_identifier = var.mlflow_db_skip_final_snapshot ? null : "${var.cluster_name}-mlflow-final-snapshot"
  deletion_protection       = var.mlflow_db_deletion_protection

  # High availability
  multi_az = var.mlflow_db_multi_az

  # Performance settings
  performance_insights_enabled = true

  tags = var.tags
}
