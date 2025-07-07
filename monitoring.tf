# Notification channel for alerts
resource "google_monitoring_notification_channel" "email_channel" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Android CI/CD Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for build failures (fixed filter)
resource "google_monitoring_alert_policy" "build_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Android Build Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "Build failure condition"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/android_build_failures\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  # Add notification channels if email is provided
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email_channel[0].id] : []
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Alert policy for build success (for testing)
resource "google_monitoring_alert_policy" "build_success_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Android Build Success Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Build success monitoring"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/android_build_success\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  # Add notification channels if email is provided
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email_channel[0].id] : []
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Fixed dashboard for Android CI/CD metrics
resource "google_monitoring_dashboard" "android_cicd_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Android CI/CD Pipeline Dashboard"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Build Success Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/android_build_success\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos  = 6
          widget = {
            title = "Build Failures"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/android_build_failures\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Budget alert for cost monitoring (only if billing account ID is provided)
resource "google_billing_budget" "android_cicd_budget" {
  count = var.enable_monitoring && var.billing_account_id != "" ? 1 : 0
  
  billing_account = var.billing_account_id
  display_name    = "Android CI/CD Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/24E6-581D-38E5", # Cloud Build
      "services/95FF-2EF5-5EA1", # Cloud Storage
      "services/F25A-78F8-0F1C"  # Cloud Pub/Sub
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = "100"
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for exporting build logs
resource "google_logging_project_sink" "build_logs_sink" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "android-build-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.build_artifacts.name}"
  
  filter = <<-EOT
    resource.type="cloud_build"
    logName="projects/${var.project_id}/logs/cloudbuild"
    jsonPayload.substitutions._PIPELINE_TYPE="android"
  EOT
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant write access to the log sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.build_artifacts.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.build_logs_sink[0].writer_identity
}

# Custom service for SLO
resource "google_monitoring_custom_service" "android_cicd_service" {
  count = var.enable_monitoring ? 1 : 0
  
  service_id   = "android-cicd-pipeline"
  display_name = "Android CI/CD Pipeline"
  
  depends_on = [google_project_service.required_apis]
}
