data "aws_subnets" "public" {
  filter {
    name   = "tag:Project"
    values = ["bia-eks"]
  }

  filter {
    name   = "tag:Environment"
    values = ["production"]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = [true]
  }
}