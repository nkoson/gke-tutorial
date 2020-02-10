terraform {
  required_version = "~> 0.12"
  backend "remote" {
    organization = "my-organization"

    workspaces {
      name = "gke-tutorial"
    }
  }
}
