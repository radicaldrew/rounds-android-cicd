# Terraform configuration moved to backend.tf
# This keeps the main infrastructure separate from backend config

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "compute.googleapis.com"
  ])

  service = each.value

  disable_dependent_services = true
}

# Data sources
data "google_project" "project" {
  project_id = var.project_id
}

data "google_compute_default_service_account" "default" {
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage buckets for the pipeline
resource "google_storage_bucket" "source_uploads" {
  name          = "${var.project_id}-source-uploads"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.source_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "build_artifacts" {
  name          = "${var.project_id}-build-artifacts"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.artifact_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "build_cache" {
  name          = "${var.project_id}-build-cache"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.cache_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for build triggers
resource "google_pubsub_topic" "android_app_uploads" {
  name = "android-app-uploads"

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for monitoring
resource "google_pubsub_subscription" "android_app_uploads_monitoring" {
  name  = "android-app-uploads-monitoring"
  topic = google_pubsub_topic.android_app_uploads.name

  message_retention_duration = "600s"
  retain_acked_messages      = false

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage notification to Pub/Sub
resource "google_storage_notification" "source_upload_notification" {
  bucket         = google_storage_bucket.source_uploads.name
  topic          = google_pubsub_topic.android_app_uploads.id
  payload_format = "JSON_API_V1"

  event_types = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# IAM for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  topic  = google_pubsub_topic.android_app_uploads.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

data "google_storage_project_service_account" "gcs_account" {
  depends_on = [google_project_service.required_apis]
}

# Cloud Build service account
resource "google_service_account" "cloud_build_sa" {
  account_id   = "android-cicd-build-sa"
  display_name = "Android CI/CD Cloud Build Service Account"
  description  = "Service account for Android CI/CD Cloud Build operations"

  depends_on = [google_project_service.required_apis]
}

# IAM roles for Cloud Build service account
resource "google_project_iam_member" "cloud_build_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/storage.admin",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"

  depends_on = [google_service_account.cloud_build_sa]
}

# Cloud Build Worker Pool for cost optimization
resource "google_cloudbuild_worker_pool" "cost_optimized_pool" {
  name     = "cost-optimized-pool"
  location = var.region

  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-highmem-2"
    no_external_ip = false
  }

  depends_on = [google_project_service.required_apis]
}
