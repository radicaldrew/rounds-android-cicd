output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

output "source_bucket_name" {
  description = "Name of the source uploads bucket"
  value       = google_storage_bucket.source_uploads.name
}

output "artifacts_bucket_name" {
  description = "Name of the build artifacts bucket"
  value       = google_storage_bucket.build_artifacts.name
}

output "cache_bucket_name" {
  description = "Name of the build cache bucket"
  value       = google_storage_bucket.build_cache.name
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for build triggers"
  value       = google_pubsub_topic.android_app_uploads.name
}

output "build_trigger_id" {
  description = "ID of the main Cloud Build trigger"
  value       = google_cloudbuild_trigger.android_build_trigger.trigger_id
}

output "manual_trigger_id" {
  description = "ID of the manual Cloud Build trigger"
  value       = google_cloudbuild_trigger.android_manual_trigger.trigger_id
}

output "cloud_build_service_account" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloud_build_sa.email
}

output "worker_pool_id" {
  description = "ID of the Cloud Build worker pool"
  value       = google_cloudbuild_worker_pool.cost_optimized_pool.id
}

output "android_keystore_secret_name" {
  description = "Name of the Android keystore secret"
  value       = google_secret_manager_secret.android_keystore.secret_id
}

output "keystore_properties_secret_name" {
  description = "Name of the keystore properties secret"
  value       = google_secret_manager_secret.keystore_properties.secret_id
}

output "source_bucket_url" {
  description = "URL of the source uploads bucket"
  value       = "gs://${google_storage_bucket.source_uploads.name}"
}

output "artifacts_bucket_url" {
  description = "URL of the build artifacts bucket"
  value       = "gs://${google_storage_bucket.build_artifacts.name}"
}

output "cache_bucket_url" {
  description = "URL of the build cache bucket"
  value       = "gs://${google_storage_bucket.build_cache.name}"
}

output "console_build_triggers_url" {
  description = "URL to view Cloud Build triggers in the console"
  value       = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
}

output "console_build_history_url" {
  description = "URL to view Cloud Build history in the console"
  value       = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
}

output "console_storage_url" {
  description = "URL to view Cloud Storage buckets in the console"
  value       = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
}

output "console_monitoring_url" {
  description = "URL to view monitoring dashboard in the console"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.android_cicd_dashboard[0].id}?project=${var.project_id}" : "Monitoring not enabled"
}

output "webhook_url" {
  description = "Configured webhook URL for build notifications"
  value       = var.webhook_url
}

output "build_configuration" {
  description = "Summary of build configuration"
  value = {
    machine_type       = var.machine_type
    disk_size_gb       = var.disk_size_gb
    build_timeout      = var.build_timeout
    enable_signing     = var.enable_signing
    enable_unit_tests  = var.enable_unit_tests
    enable_lint        = var.enable_lint
    enable_monitoring  = var.enable_monitoring
    cost_optimization  = var.enable_cost_optimization
    parallel_builds    = var.enable_parallel_builds
    gradle_max_workers = var.gradle_max_workers
    gradle_memory      = var.gradle_memory
  }
}

output "android_configuration" {
  description = "Android build configuration"
  value = {
    compile_sdk    = var.android_compile_sdk
    min_sdk        = var.android_min_sdk
    target_sdk     = var.android_target_sdk
    gradle_version = var.gradle_version
    java_version   = var.java_version
  }
}

output "retention_policies" {
  description = "Configured retention policies"
  value = {
    source_retention_days   = var.source_retention_days
    artifact_retention_days = var.artifact_retention_days
    cache_retention_days    = var.cache_retention_days
  }
}

output "monitoring_resources" {
  description = "Monitoring resources created"
  value = {
    enabled              = var.enable_monitoring
    dashboard_id         = var.enable_monitoring && length(google_monitoring_dashboard.android_cicd_dashboard) > 0 ? google_monitoring_dashboard.android_cicd_dashboard[0].id : "Not created"
    notification_channel = var.enable_monitoring && var.notification_email != "" && length(google_monitoring_notification_channel.email_channel) > 0 ? google_monitoring_notification_channel.email_channel[0].name : "Not configured"
    alert_policies = {
      build_failures = var.enable_monitoring && length(google_monitoring_alert_policy.build_failure_alert) > 0 ? google_monitoring_alert_policy.build_failure_alert[0].name : "Not created"
      build_success  = var.enable_monitoring && length(google_monitoring_alert_policy.build_success_alert) > 0 ? google_monitoring_alert_policy.build_success_alert[0].name : "Not created"
    }
    log_metrics = {
      success_metric  = var.enable_monitoring ? "android_build_success" : "Not created"
      failure_metric  = var.enable_monitoring ? "android_build_failures" : "Not created"
      duration_metric = var.enable_monitoring ? "android_build_duration" : "Not created"
    }
  }
}

output "setup_instructions" {
  description = "Instructions for setting up the pipeline"
  value       = <<-EOT
# Android CI/CD Pipeline Setup Instructions

## 1. Build Android Builder Image
First, build the Android builder Docker image manually:
```bash
# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl git unzip wget openjdk-${var.java_version}-jdk build-essential && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-${var.java_version}-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
RUN mkdir -p $ANDROID_HOME && cd $ANDROID_HOME && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip && \
    unzip commandlinetools-linux-7583922_latest.zip && rm commandlinetools-linux-7583922_latest.zip && \
    mv cmdline-tools latest && mkdir cmdline-tools && mv latest cmdline-tools/
RUN yes | sdkmanager --licenses && sdkmanager --update && \
    sdkmanager "platform-tools" "build-tools;${var.android_compile_sdk}.0.0" "platforms;android-${var.android_compile_sdk}" "platforms;android-${var.android_min_sdk}"
RUN wget -q https://services.gradle.org/distributions/gradle-${var.gradle_version}-bin.zip && \
    unzip gradle-${var.gradle_version}-bin.zip && mv gradle-${var.gradle_version} /opt/gradle && rm gradle-${var.gradle_version}-bin.zip
ENV PATH=$PATH:/opt/gradle/bin
WORKDIR /workspace
EOF

# Build and push
gcloud builds submit --tag gcr.io/${var.project_id}/android-builder:latest .
```

## 2. Upload Android Source Code
Upload your Android project as a ZIP file to the source bucket:
```bash
gsutil cp your-android-project.zip gs://${google_storage_bucket.source_uploads.name}/
```

## 3. Configure Android Signing (Optional)
If you want to build signed APKs, upload your keystore:
```bash
# Upload keystore to Secret Manager
gcloud secrets versions add android-keystore --data-file=path/to/your/keystore.jks
```

## 4. Test the Pipeline
The pipeline will automatically trigger when files are uploaded to the source bucket.
Monitor builds at:
```bash
gcloud builds list
```

## 5. Monitor Builds
- View build history: https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}
- View build artifacts: https://console.cloud.google.com/storage/browser?project=${var.project_id}
${var.enable_monitoring ? "- View monitoring dashboard: https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}" : ""}

## 6. Download Build Artifacts
```bash
# List available builds
gsutil ls gs://${google_storage_bucket.build_artifacts.name}/

# Download specific build artifacts
gsutil -m cp -r gs://${google_storage_bucket.build_artifacts.name}/BUILD_ID/ ./
```

## Bucket URLs:
- Source uploads: gs://${google_storage_bucket.source_uploads.name}
- Build artifacts: gs://${google_storage_bucket.build_artifacts.name}
- Build cache: gs://${google_storage_bucket.build_cache.name}
  EOT
}

output "cost_optimization_info" {
  description = "Cost optimization features enabled"
  value = {
    enabled            = var.enable_cost_optimization
    worker_pool        = var.enable_cost_optimization ? "Using cost-optimized worker pool" : "Standard workers"
    cache_enabled      = "Build cache enabled for faster builds"
    lifecycle_policies = "Automatic cleanup of old artifacts"
    recommendations    = var.enable_cost_optimization ? "Already optimized" : "Consider enabling cost optimization"
  }
}

output "security_info" {
  description = "Security configuration"
  value = {
    service_account = "Dedicated service account: ${google_service_account.cloud_build_sa.email}"
    secret_manager  = "Keystore secrets managed via Secret Manager"
    iam_roles       = "Principle of least privilege applied"
    bucket_security = "Uniform bucket-level access enabled"
    build_isolation = "Isolated build environment per execution"
  }
}

# Additional helpful outputs
output "webhook_secret_name" {
  description = "Name of the webhook secret for manual triggers"
  value       = google_secret_manager_secret.webhook_trigger_secret.secret_id
}

output "next_steps" {
  description = "What to do after deployment"
  value       = <<-EOT
🎉 Infrastructure deployed successfully!

Next steps:
1. Build the Android builder image (see setup_instructions output)
2. Upload your Android project as a ZIP file to: gs://${google_storage_bucket.source_uploads.name}/
3. Monitor builds at: https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}

The pipeline will automatically trigger when you upload files to the source bucket.
  EOT
}