resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]
}