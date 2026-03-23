resource "aws_db_instance" "this" {
  identifier              = var.rds.identifier
  allocated_storage       = var.rds.allocated_storage
  storage_type            = var.rds.storage_type
  engine                  = var.rds.engine
  engine_version          = var.rds.engine_version
  instance_class          = var.rds.instance_class
  username                = var.rds.username
  password                = var.rds.password
  db_name                 = var.rds.db_name
  parameter_group_name    = var.rds.parameter_group_name
  publicly_accessible     = var.rds.publicly_accessible
  skip_final_snapshot     = var.rds.skip_final_snapshot
  backup_retention_period = var.rds.backup_retention_period
  multi_az                = var.rds.multi_az
  storage_encrypted       = var.rds.storage_encrypted
  vpc_security_group_ids  = [aws_security_group.bia_eks_db.id]
  db_subnet_group_name    = aws_db_subnet_group.this.name


  tags = {
    Name = var.rds.identifier
  }

}