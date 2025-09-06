variable "project_id" { type = string }
variable "project_number" { type = string }

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "network_name" {
  type    = string
  default = "gke-vpc"
}

variable "subnet_name" {
  type    = string
  default = "gke-subnet"
}

variable "subnet_ip_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "pods_ip_range" {
  type    = string
  default = "10.20.0.0/14"
}

variable "services_ip_range" {
  type    = string
  default = "10.24.0.0/20"
}

variable "cluster_name" {
  type    = string
  default = "ml-gke"
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "credentials_file" {
  type        = string
  description = "Path to the service account JSON key"
}

# Node pools
variable "system_node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "system_node_min" {
  type    = number
  default = 0
}

variable "system_node_max" {
  type    = number
  default = 1
}

# Big/bursty pool
variable "workload_node_machine_type" {
  type    = string
  default = "e2-standard-16"
} # consider n2-standard-16 if credits allow

variable "workload_node_min" {
  type    = number
  default = 0
}

variable "workload_node_max" {
  type    = number
  default = 2
}

variable "artifact_registry_repo" {
  type    = string
  default = "ml-images"
}