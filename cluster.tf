locals {
  project = "gke-tutorial-xxxxxx"
}

module "cluster" {

  project                             = local.project
  source                              = "./gke"
  region                              = "europe-north1"
  location                            = "europe-north1-a"
  cluster_name                        = "kluster"
  cluster_range_name                  = "gke-pods"
  services_range_name                 = "gke-services"
  daily_maintenance_window_start_time = "03:00"
  subnet_cidr_range                   = "10.0.0.0/16" # 10.0.0.0 -> 10.0.255.255
  master_ipv4_cidr_block              = "10.1.0.0/28" # 10.1.0.0 -> 10.1.0.15
  cluster_range_cidr                  = "10.2.0.0/16" # 10.2.0.0 -> 10.2.255.255
  services_range_cidr                 = "10.3.0.0/16" # 10.3.0.0 -> 10.3.255.255
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  source_ip_ranges_to_nat             = ["ALL_IP_RANGES"]
  nat_log_filter                      = "ERRORS_ONLY"
  logging_service                     = "none" # $$$
  monitoring_service                  = "none" # $$$

  node_pools = {
    ingress-pool = {
      machine_type       = "f1-micro" # $$$
      initial_node_count = 1
      min_node_count     = 1
      max_node_count     = 1
      preemptible        = false
      auto_repair        = true
      auto_upgrade       = false
      disk_size_gb       = 10
      disk_type          = "pd-standard"
      image_type         = "COS"
      service_account    = "kluster-serviceaccount@${local.project}.iam.gserviceaccount.com"
    }
    web-pool = {
      machine_type       = "f1-micro" # $$$
      initial_node_count = 1
      min_node_count     = 1
      max_node_count     = 1
      preemptible        = true
      auto_repair        = true
      auto_upgrade       = true
      disk_size_gb       = 10
      disk_type          = "pd-standard"
      image_type         = "COS"
      service_account    = "kluster-serviceaccount@${local.project}.iam.gserviceaccount.com"

    }
  }

  node_pools_taints = {
    ingress-pool = [
      {
        key    = "ingress-pool"
        value  = true
        effect = "NO_EXECUTE"
      }
    ]
    web-pool = []
  }

  node_pools_tags = {
    ingress-pool = [
      "ingress-pool"
    ]
    web-pool = [
      "web-pool"
    ]
  }

  node_pools_oauth_scopes = {
    custom-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/service.management",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}
