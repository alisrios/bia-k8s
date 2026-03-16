resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = data.aws_subnets.private.ids
  node_group_name = var.eks_cluster.node_group_name
  instance_types  = var.eks_cluster.node_group_instance_types
  capacity_type   = var.eks_cluster.node_group_capacity_type

  scaling_config {
    desired_size = var.eks_cluster.node_group_scaling_config.desired_size
    max_size     = var.eks_cluster.node_group_scaling_config.max_size
    min_size     = var.eks_cluster.node_group_scaling_config.min_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}