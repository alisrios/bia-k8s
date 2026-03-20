resource "aws_security_group" "bia_eks_db" {
  name        = "bia-eks-db"
  description = "Acesso ao bia-eks-db"
  vpc_id      = data.aws_vpc.this.id

  #ingress {
  #description     = "acesso do bia-dev-tf"
  #from_port       = 5432
  #to_port         = 5432
  #protocol        = "tcp"
  #cidr_blocks     = []
  #security_groups = [aws_security_group.bia_dev_tf.id]
  #}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bia-eks-db"
  }

}