# =============================================================================
# network.tf — VPC network and firewall configuration
# =============================================================================
# We create a dedicated VPC (Virtual Private Cloud) for the pipeline.
# This isolates our resources from other GCP projects and gives us
# full control over network topology and firewall rules.
# =============================================================================

resource "google_compute_network" "cdc_vpc" {
  name                    = "cdc-pipeline-vpc-${var.environment}"
  auto_create_subnetworks = false
  # auto_create_subnetworks = false: we define subnets explicitly
  # Auto-mode creates one subnet per region which is too broad for production

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "cdc_subnet" {
  name          = "cdc-pipeline-subnet-${var.environment}"
  ip_cidr_range = "10.0.0.0/24"
  # 10.0.0.0/24 gives us 254 usable IP addresses — enough for our services
  region        = var.region
  network       = google_compute_network.cdc_vpc.id

  private_ip_google_access = true
  # Allows VMs without public IPs to reach Google APIs (GCS, BigQuery, etc.)
  # This is a security best practice — internal services don't need public IPs
}

# =============================================================================
# FIREWALL RULES
# GCP denies all ingress by default — we explicitly allow what we need.
# =============================================================================

# Allow internal traffic between all pipeline components
resource "google_compute_firewall" "allow_internal" {
  name    = "cdc-allow-internal-${var.environment}"
  network = google_compute_network.cdc_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/24"]
  # Only allow traffic from within our own subnet
  description = "Allow all internal traffic between CDC pipeline components"
}

# Allow SSH access for debugging (restrict to your IP in production)
resource "google_compute_firewall" "allow_ssh" {
  name    = "cdc-allow-ssh-${var.environment}"
  network = google_compute_network.cdc_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  # WARNING: In production, replace 0.0.0.0/0 with your specific IP range
  # Example: ["203.0.113.0/32"] for a single IP
  target_tags = ["cdc-ssh-access"]
  description = "Allow SSH access — restrict source_ranges in production"
}
