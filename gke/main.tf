provider "google" {
  version     = "3.4.0"
  credentials = file("keys/gke-tutorial.json")
}

provider "google-beta" {
  version     = "3.5.0"
  credentials = file("keys/gke-tutorial.json")
}

resource "google_project_service" "service" {
  for_each = var.enable_service_apis

  project            = var.project
  service            = each.value
  disable_on_destroy = false
}

resource "google_container_cluster" "k8s" {
  provider           = google
  name               = var.cluster_name
  project            = var.project
  depends_on         = [google_project_service.service]
  location           = var.location
  logging_service    = var.logging_service
  monitoring_service = var.monitoring_service

  # need to create a default node pool
  # delete this immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.gke-network.self_link
  subnetwork = google_compute_subnetwork.gke-subnet.self_link

  private_cluster_config {
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_range_name
    services_secondary_range_name = var.services_range_name
  }
}
