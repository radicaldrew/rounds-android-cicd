# Simplified log-based metrics (correct configuration)
resource "google_logging_metric" "android_build_success" {
  name   = "android_build_success"
  filter = <<-EOT
    resource.type="cloud_build"
    logName="projects/${var.project_id}/logs/cloudbuild"
    jsonPayload.status="SUCCESS"
    jsonPayload.substitutions._PIPELINE_TYPE="android"
  EOT
  
  depends_on = [google_project_service.required_apis]
}

resource "google_logging_metric" "android_build_failures" {
  name   = "android_build_failures"
  filter = <<-EOT
    resource.type="cloud_build"
    logName="projects/${var.project_id}/logs/cloudbuild"
    jsonPayload.status="FAILURE"
    jsonPayload.substitutions._PIPELINE_TYPE="android"
  EOT
  
  depends_on = [google_project_service.required_apis]
}

# Simple duration metric without value extractor
resource "google_logging_metric" "android_build_duration" {
  name   = "android_build_duration"
  filter = <<-EOT
    resource.type="cloud_build"
    logName="projects/${var.project_id}/logs/cloudbuild"
    jsonPayload.status="SUCCESS"
    jsonPayload.substitutions._PIPELINE_TYPE="android"
  EOT
  
  depends_on = [google_project_service.required_apis]
}