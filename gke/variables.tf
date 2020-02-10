variable "project" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "location" {
  type = string
}

variable "daily_maintenance_window_start_time" {
  type = string
}

variable "cluster_range_name" {
  type = string
}

variable "cluster_range_cidr" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "services_range_cidr" {
  type = string
}

variable "subnet_cidr_range" {
  type = string
}

variable "private_ip_google_access" {
  type    = bool
  default = true
}

# internal IP adddresses of masters
variable "master_ipv4_cidr_block" {
  type = string
}

# IAM for storage.objectViewer
# access GCR private images
variable "access_private_images" {
  type    = bool
  default = false
}

# HTTP (L7) load balancer
variable "http_load_balancing_disabled" {
  type    = bool
  default = false
}

variable "master_authorized_networks_cidr_blocks" {
  type = list(map(string))

  default = [
    {
      # external access to k8s master HTTPS
      cidr_block   = "0.0.0.0/0"
      display_name = "default"
    }
  ]
}

variable "enable_service_apis" {
  description = "Which API services to enable in GCP? Eg. cloudresourcemanager.googleapis.com"
  type        = set(string)
  default     = []
}

variable "logging_service" {
  type    = string
  default = "logging.googleapis.com/kubernetes"
}

variable "monitoring_service" {
  type    = string
  default = "monitoring.googleapis.com/kubernetes"
}

variable "enable_private_nodes" {
  type    = bool
  default = true
}

variable "enable_private_endpoint" {
  type    = bool
  default = false
}

variable "node_pools" {
  type    = map(map(string))
  default = {}
}

variable "node_pools_taints" {
  type = map(list(object({ key = string, value = string, effect = string })))
  default = {
    custom-node-pool = []
  }
}

variable "node_pools_tags" {
  type = map(list(string))
  default = {
    custom-node-pool = []
  }
}

variable "node_pools_oauth_scopes" {
  type = map(list(string))
}

variable "nat_ip_allocate_option" {
  type = string
}

# ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES, LIST_OF_SUBNETWORKS
variable "source_subnetwork_ip_ranges_to_nat" {
  type = string
}

# ALL_IP_RANGES, LIST_OF_SECONDARY_IP_RANGES, PRIMARY_IP_RANGE
variable "source_ip_ranges_to_nat" {
  type = list
}

variable "nat_log_filter" {
  type = string
}
