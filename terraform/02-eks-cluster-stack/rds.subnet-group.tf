# Cria o grupo de subnets privadas para o RDS
resource "aws_db_subnet_group" "this" {
  name        = var.rds_subnet_group.name
  subnet_ids  = data.aws_subnets.private.ids
  description = var.rds_subnet_group.description

  tags = merge(var.tags, { Name = var.rds_subnet_group.name })

}