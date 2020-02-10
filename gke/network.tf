
resource "google_compute_network" "gke-network" {
  name                    = var.cluster_name
  project                 = var.project
  auto_create_subnetworks = false
}

# https://www.terraform.io/docs/providers/google/r/compute_subnetwork.html
resource "google_compute_subnetwork" "gke-subnet" {
  name          = var.cluster_name
  region        = var.region
  project       = var.project
  network       = google_compute_network.gke-network.id
  ip_cidr_range = var.subnet_cidr_range

  secondary_ip_range {
    range_name    = var.cluster_range_name
    ip_cidr_range = var.cluster_range_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_range_cidr
  }

  # VMs without external IP can access Google APIs through Private Google Access
  private_ip_google_access = var.private_ip_google_access
}

resource "google_compute_router" "gke-router" {
  name    = var.cluster_name
  region  = var.region
  project = var.project
  network = google_compute_network.gke-network.id
  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "gke-nat" {
  name                               = var.cluster_name
  project                            = var.project
  router                             = google_compute_router.gke-router.name
  region                             = var.region
  nat_ip_allocate_option             = var.nat_ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = var.source_subnetwork_ip_ranges_to_nat
  subnetwork {
    name                    = google_compute_subnetwork.gke-subnet.self_link
    source_ip_ranges_to_nat = var.source_ip_ranges_to_nat
  }
  log_config {
    filter = var.nat_log_filter
    enable = true
  }

  # Hard code these values, because every other terraform apply wants to either set them to null, or to these values
  icmp_idle_timeout_sec            = 30
  tcp_established_idle_timeout_sec = 1200
  tcp_transitory_idle_timeout_sec  = 30
  udp_idle_timeout_sec             = 30
}

resource "google_compute_address" "static-ingress" {
  name     = "static-ingress"
  project  = var.project
  region   = var.region
  provider = google-beta

  # address labels are a beta feature
  labels = {
    kubeip = "static-ingress"
  }
}

# By default, firewall rules restrict cluster master to only initiate TCP connections to nodes on ports 443 (HTTPS) and 10250 (kubelet)
resource "google_compute_firewall" "default" {
  name    = "web-ingress"
  network = google_compute_network.gke-network.self_link
  project = var.project

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.node_pools_tags.ingress-pool
}
