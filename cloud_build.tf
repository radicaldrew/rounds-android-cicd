resource "google_cloudbuild_trigger" "android_build_trigger" {
  name        = "android-build-trigger"
  location = "global"
  description = "Trigger for Android CI/CD builds"
  service_account = google_service_account.cloud_build_sa.id


  pubsub_config {
    topic = "projects/${var.project_id}/topics/${google_pubsub_topic.android_app_uploads.name}"
  }

  filename = "cloudbuild.yaml"

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloud_build_sa_roles
  ]
}

resource "google_cloudbuild_trigger" "android_manual_trigger" {
  name        = "android-manual-trigger"  
  description = "Manual trigger for Android builds"
  service_account = google_service_account.cloud_build_sa.id

  
  # Use source repositories instead of GitHub
  trigger_template {
    project_id  = var.project_id
    repo_name   = "android-cicd-manual"
    branch_name = "main"
  }
  
  # Start disabled
  disabled = true
  
  build {
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "version"
      ]
    }
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}