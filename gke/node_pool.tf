resource "google_container_node_pool" "custom_nodepool" {
  for_each = var.node_pools

  name               = each.key
  project            = var.project
  location           = var.location
  cluster            = var.cluster_name
  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count = lookup(each.value, "min_node_count", 1)
    max_node_count = lookup(each.value, "max_node_count", 2)
  }

  management {
    auto_repair  = lookup(each.value, "auto_repair", true)
    auto_upgrade = lookup(each.value, "auto_upgrade", true)
  }

  node_config {
    machine_type    = lookup(each.value, "machine_type", "f1-micro")
    disk_size_gb    = lookup(each.value, "disk_size_gb", 10)
    disk_type       = lookup(each.value, "disk_type", "pd-standard")
    image_type      = lookup(each.value, "image_type", "COS")
    preemptible     = lookup(each.value, "preemptible", false)
    service_account = lookup(each.value, "service_account", "")
    oauth_scopes    = var.node_pools_oauth_scopes["custom-node-pool"]

    tags = var.node_pools_tags[each.key]

    dynamic "taint" {
      for_each = {
        for obj in var.node_pools_taints[each.key] : "${obj.key}_${obj.value}_${obj.effect}" => obj
      }
      content {
        effect = taint.value.effect
        key    = taint.value.key
        value  = taint.value.value
      }
    }

  }
}
