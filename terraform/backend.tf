terraform {
  backend "local" {
    # State file will be stored in terraform/terraform.tfstate (relative to this file)
    path = "terraform.tfstate"
  }
}
