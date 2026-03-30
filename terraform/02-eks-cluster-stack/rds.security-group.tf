resource "aws_security_group" "bia_eks_db" {
  name        = var.rds_security_group.name
  description = var.rds_security_group.description
  vpc_id      = data.aws_vpc.this.id

  ingress {
    description     = var.rds_security_group.ingress_rule.description
    from_port       = var.rds_security_group.ingress_rule.from_port
    to_port         = var.rds_security_group.ingress_rule.to_port
    protocol        = var.rds_security_group.ingress_rule.protocol
    cidr_blocks     = var.rds_security_group.ingress_rule.cidr_blocks
    security_groups = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = var.rds_security_group.egress_rule.from_port
    to_port     = var.rds_security_group.egress_rule.to_port
    protocol    = var.rds_security_group.egress_rule.protocol
    cidr_blocks = var.rds_security_group.egress_rule.cidr_blocks
  }

  tags = {
    Name = "bia-eks-db"
  }
}
