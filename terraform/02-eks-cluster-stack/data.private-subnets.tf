data "aws_subnets" "private" {
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
    values = [false]
  }
}