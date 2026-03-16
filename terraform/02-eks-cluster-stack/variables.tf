variable "tags" {
  type = map(string)
  default = {
    Project     = "bia-eks"
    Environment = "production"
  }
}

variable "auth" {
  type = object({
    assume_role_arn = string
    region          = string
  })

  default = {
    assume_role_arn = "arn:aws:iam::976808777516:role/assume-role-terraform"
    region          = "us-east-1"
  }
}

variable "eks_cluster" {
  type = object({
    name                              = string
    version                           = string
    enabled_cluster_log_types         = list(string)
    access_config_authentication_mode = string
    node_group_name                   = string
    node_group_instance_types         = list(string)
    node_group_capacity_type          = string
    node_group_scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
  })

  default = {
    name    = "bia-eks-cluster"
    version = "1.35"
    enabled_cluster_log_types = [
      "api",
      "audit",
      "authenticator",
      "controllerManager",
      "scheduler",
    ]
    principal_arn                     = "arn:aws:iam::976808777516:user/alisrios"
    access_config_authentication_mode = "API_AND_CONFIG_MAP"
    node_group_name                   = "bia-eks-node-group"
    node_group_instance_types         = ["t3.small"]
    node_group_capacity_type          = "ON_DEMAND"
    node_group_scaling_config = {
      desired_size = 2
      max_size     = 2
      min_size     = 2
    }
  }
}

variable "ecr_repositories" {
  type = list(object({
    name                 = string
    image_tag_mutability = string
  }))

  default = [
    {
      name                 = "bia"
      image_tag_mutability = "MUTABLE"
    }
  ]
}

variable "eks_access_entrys" {
  type = map(string)
  default = {
    principal_arn = "arn:aws:iam::976808777516:user/alisrios"
    type          = "STANDARD"
  }

}