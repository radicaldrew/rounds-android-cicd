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

# Alert policy for build failures
resource "google_monitoring_alert_policy" "build_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Android Build Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "Build failure condition"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/android_build_failures\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
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
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email_channel[0].id]
    }
  }
  
  depends_on = [
    google_logging_metric.android_build_failures,
    google_project_service.required_apis
  ]
}

# Alert policy for long build times
resource "google_monitoring_alert_policy" "long_build_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Android Build Duration Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Long build duration condition"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/android_build_duration\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 1800 # 30 minutes
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email_channel[0].id]
    }
  }
  
  depends_on = [
    google_logging_metric.android_build_duration,
    google_project_service.required_apis
  ]
}

# Custom dashboard for Android CI/CD metrics
resource "google_monitoring_dashboard" "android_cicd_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Android CI/CD Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Build Success Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"logging.googleapis.com/user/android_build_success\""
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
                  filter = "metric.type=\"logging.googleapis.com/user/android_build_failures\""
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
          width = 12
          height = 4
          yPos  = 4
          widget = {
            title = "Build Duration Over Time"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/android_build_duration\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Duration (seconds)"
                scale = "LINEAR"
              }
              xAxis = {
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos  = 8
          widget = {
            title = "Storage Usage - Build Artifacts"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"storage.googleapis.com/storage/total_bytes\" AND resource.labels.bucket_name=\"${google_storage_bucket.build_artifacts.name}\""
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Bytes"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos  = 6
          yPos  = 8
          widget = {
            title = "Cloud Build Quota Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"serviceruntime.googleapis.com/quota/used\" AND resource.labels.service=\"cloudbuild.googleapis.com\""
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Usage"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [
    google_logging_metric.android_build_success,
    google_logging_metric.android_build_failures,
    google_logging_metric.android_build_duration,
    google_project_service.required_apis
  ]
}

# Budget alert for cost monitoring
resource "google_billing_budget" "android_cicd_budget" {
  count = var.enable_monitoring ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
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

# Get billing account info
data "google_billing_account" "account" {
  billing_account = var.billing_account_id
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

# SLO for build success rate
resource "google_monitoring_slo" "build_success_slo" {
  count = var.enable_monitoring ? 1 : 0
  
  service      = google_monitoring_custom_service.android_cicd_service[0].service_id
  display_name = "Build Success Rate SLO"
  
  request_based_sli {
    good_total_ratio {
      total_service_filter = "metric.type=\"logging.googleapis.com/user/android_build_success\" OR metric.type=\"logging.googleapis.com/user/android_build_failures\""
      good_service_filter  = "metric.type=\"logging.googleapis.com/user/android_build_success\""
    }
  }
  
  goal = 0.95 # 95% success rate
  
  rolling_period_days = 30
  
  depends_on = [
    google_logging_metric.android_build_success,
    google_logging_metric.android_build_failures
  ]
}

# Custom service for SLO
resource "google_monitoring_custom_service" "android_cicd_service" {
  count = var.enable_monitoring ? 1 : 0
  
  service_id   = "android-cicd-pipeline"
  display_name = "Android CI/CD Pipeline"
  
  depends_on = [google_project_service.required_apis]
}