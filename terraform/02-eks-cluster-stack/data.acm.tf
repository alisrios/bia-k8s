data "aws_acm_certificate" "this" {
  domain   = "*.alisriosti.com.br"
  statuses = ["ISSUED"]
}