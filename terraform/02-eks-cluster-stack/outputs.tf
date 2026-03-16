output "eks_cluster_id" {
  value = aws_eks_cluster.this.id
}

output "private_subnet_ids" {
  value = data.aws_subnets.private.ids
}