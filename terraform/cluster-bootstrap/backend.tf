terraform {
  backend "local" {
    path = "/home/nof/.terraform/cluster-bootstrap/terraform.tfstate"
  }
}
