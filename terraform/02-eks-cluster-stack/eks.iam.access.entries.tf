resource "aws_eks_access_entry" "this" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.eks_access_entrys.principal_arn
  type          = var.eks_access_entrys.type
}

resource "aws_eks_access_policy_association" "this" {
  cluster_name  = aws_eks_cluster.this.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.this.principal_arn

  access_scope {
    type = "cluster"
  }
}
