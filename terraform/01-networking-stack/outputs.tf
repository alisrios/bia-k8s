output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "vpc_id" {
  value = aws_vpc.this.id  
}

output "public_subnet_arns" {
  value = aws_subnet.public[*].arn
}

output "private_subnet_arns" {
  value = aws_subnet.private[*].arn
}

output "elastic_ip" {
  value = aws_eip.this.public_ip
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id  
}