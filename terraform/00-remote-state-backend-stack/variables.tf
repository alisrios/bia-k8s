variable "auth" {
  type = object({
    region          = string
    assume_role_arn = string
  })

  default = {
    assume_role_arn = "arn:aws:iam::976808777516:role/assume-role-terraform"
    region          = "us-east-1"
  }
}

variable "remote_backend" {
  type = object({
    s3_bucket                   = string
    dynamodb_table_name         = string
    dynamodb_table_billing_mode = string
    dynamodb_table_hash_key     = string
    dynamodb_atribute_name      = string
  })

  default = {
    s3_bucket                   = "bia-eks-s3-remote-backend-bucket"
    dynamodb_table_name         = "bia-eks-s3-state-locking-table"
    dynamodb_table_billing_mode = "PAY_PER_REQUEST"
    dynamodb_table_hash_key     = "LockID"
    dynamodb_atribute_name      = "S"
  }
}

variable "tags" {
  type = map(string)

  default = {
    Environment = "production"
    Project     = "bia-eks"
  }

}