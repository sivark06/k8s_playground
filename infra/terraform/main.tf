# Enable required APIs
resource "google_project_service" "services" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Network
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  depends_on              = [google_project_service.services]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_ip_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_ip_range
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_ip_range
  }
}

# GKE Cluster (single-zone, public nodes)
resource "google_container_cluster" "cluster" {
  provider = google-beta

  name                     = var.cluster_name
  location                 = var.zone
  network                  = google_compute_network.vpc.self_link
  subnetwork               = google_compute_subnetwork.subnet.self_link
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Public nodes (cheaper/simpler than private + NAT for a Playground)
  # Private cluster config omitted

  master_authorized_networks_config {
    # To allow access from any IP, you must define a cidr_blocks block.
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Allow all"
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
    managed_prometheus { enabled = true }
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  enable_shielded_nodes = true
  datapath_provider     = "ADVANCED_DATAPATH" # good for Istio

  lifecycle {
    ignore_changes = [node_config] # avoid surprises if defaults change
  }

  depends_on = [
    google_project_service.services
  ]
}

# System node pool (can scale to zero)
resource "google_container_node_pool" "system_pool" {
  provider = google-beta

  name     = "system-pool"
  location = var.zone
  cluster  = google_container_cluster.cluster.name

  node_config {
    machine_type = var.system_node_machine_type
    image_type   = "COS_CONTAINERD"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { pool = "system" }
    taint {
      key    = "node-role.kubernetes.io/system"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
    metadata = { disable-legacy-endpoints = "true" }
    workload_metadata_config { mode = "GKE_METADATA" }
  }

  autoscaling {
    min_node_count = var.system_node_min
    max_node_count = var.system_node_max
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  initial_node_count = var.system_node_min

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Workload pool (beefy; scale from 0)
resource "google_container_node_pool" "workload_pool" {
  provider = google-beta

  name     = "workload-pool"
  location = var.zone
  cluster  = google_container_cluster.cluster.name

  node_config {
    machine_type = var.workload_node_machine_type
    image_type   = "COS_CONTAINERD"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { pool = "workload" }
    metadata     = { disable-legacy-endpoints = "true" }
    workload_metadata_config { mode = "GKE_METADATA" }
  }

  autoscaling {
    min_node_count = var.workload_node_min
    max_node_count = var.workload_node_max
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  initial_node_count = var.workload_node_min

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Artifact Registry (optional)
resource "google_artifact_registry_repository" "repo" {
  provider      = google-beta
  location      = var.region
  repository_id = var.artifact_registry_repo
  description   = "Container images for Playground"
  format        = "DOCKER"
}

output "cluster_name" { value = google_container_cluster.cluster.name }
output "cluster_location" { value = google_container_cluster.cluster.location }

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.cluster.name} --zone ${var.zone} --project ${var.project_id}"
}
