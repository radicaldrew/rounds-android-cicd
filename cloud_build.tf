# Cloud Build trigger for Pub/Sub events
resource "google_cloudbuild_trigger" "android_build_trigger" {
  name        = "android-build-trigger"
  description = "Trigger for Android CI/CD builds"
  
  pubsub_config {
    topic = google_pubsub_topic.android_app_uploads.id
  }
  
  source_to_build {
    uri       = "gs://${google_storage_bucket.source_uploads.name}"
    ref       = "main"
    repo_type = "UNKNOWN"
  }
  
  build {
    timeout = var.build_timeout
    
    options {
      machine_type = var.machine_type
      disk_size_gb = var.disk_size_gb
      logging      = "CLOUD_LOGGING_ONLY"
      
      dynamic "pool" {
        for_each = var.enable_cost_optimization ? [1] : []
        content {
          name = google_cloudbuild_worker_pool.cost_optimized_pool.id
        }
      }
    }
    
    # Download source from Cloud Storage
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "download_source"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Downloading source from: gs://${google_storage_bucket.source_uploads.name}/$$FILE_NAME"
          gsutil cp gs://${google_storage_bucket.source_uploads.name}/$$FILE_NAME /workspace/source.zip
          unzip /workspace/source.zip -d /workspace/
          ls -la /workspace/
        EOT
      ]
    }
    
    # Extract build cache
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "extract_cache"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          if gsutil cp gs://${google_storage_bucket.build_cache.name}/cache.tgz /workspace/cache.tgz; then
            echo "Cache found, extracting..."
            tar -xzf /workspace/cache.tgz -C /workspace/
          else
            echo "No cache found, starting fresh"
            mkdir -p /workspace/.gradle
          fi
        EOT
      ]
    }
    
    # Get signing secrets (conditional)
    dynamic "step" {
      for_each = var.enable_signing ? [1] : []
      content {
        name = "gcr.io/cloud-builders/gcloud"
        id   = "get_secrets"
        entrypoint = "bash"
        args = [
          "-c",
          <<-EOT
            if gcloud secrets versions access latest --secret="android-keystore" > /workspace/keystore.jks 2>/dev/null; then
              echo "Keystore retrieved successfully"
              gcloud secrets versions access latest --secret="keystore-properties" > /workspace/keystore.properties
            else
              echo "No keystore found, will build debug version only"
            fi
          EOT
        ]
        wait_for = ["download_source"]
      }
    }
    
    # Run unit tests (conditional)
    dynamic "step" {
      for_each = var.enable_unit_tests ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/android-builder:latest"
        id   = "unit_tests"
        args = ["./gradlew", "testDebugUnitTest", "--stacktrace"]
        env = [
          "GRADLE_USER_HOME=/workspace/.gradle",
          "GRADLE_OPTS=-Dorg.gradle.daemon=false ${var.enable_parallel_builds ? "-Dorg.gradle.parallel=true" : ""} -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}"
        ]
        wait_for = ["extract_cache"]
      }
    }
    
    # Run lint checks (conditional)
    dynamic "step" {
      for_each = var.enable_lint ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/android-builder:latest"
        id   = "lint_checks"
        args = ["./gradlew", "lintDebug", "--stacktrace"]
        env = [
          "GRADLE_USER_HOME=/workspace/.gradle",
          "GRADLE_OPTS=-Dorg.gradle.daemon=false ${var.enable_parallel_builds ? "-Dorg.gradle.parallel=true" : ""} -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}"
        ]
        wait_for = ["extract_cache"]
      }
    }
    
    # Build debug APK
    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "build_debug"
      args = ["./gradlew", "assembleDebug", "--stacktrace"]
      env = [
        "GRADLE_USER_HOME=/workspace/.gradle",
        "GRADLE_OPTS=-Dorg.gradle.daemon=false ${var.enable_parallel_builds ? "-Dorg.gradle.parallel=true" : ""} -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}"
      ]
      wait_for = var.enable_unit_tests || var.enable_lint ? 
        compact(["unit_tests", "lint_checks"]) : 
        ["extract_cache"]
    }
    
    # Build release APK (conditional)
    dynamic "step" {
      for_each = var.enable_signing ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/android-builder:latest"
        id   = "build_release"
        entrypoint = "bash"
        args = [
          "-c",
          <<-EOT
            if [[ -f /workspace/keystore.jks ]]; then
              echo "Building release APK with signing"
              ./gradlew assembleRelease --stacktrace
            else
              echo "No keystore found, skipping release build"
            fi
          EOT
        ]
        env = [
          "GRADLE_USER_HOME=/workspace/.gradle",
          "GRADLE_OPTS=-Dorg.gradle.daemon=false ${var.enable_parallel_builds ? "-Dorg.gradle.parallel=true" : ""} -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}"
        ]
        wait_for = compact(["get_secrets", "build_debug"])
      }
    }
    
    # Upload artifacts
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "upload_artifacts"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Create build info
          echo "Build ID: $$BUILD_ID" > /workspace/build_info.txt
          echo "Build Time: $$(date)" >> /workspace/build_info.txt
          echo "Source File: $$FILE_NAME" >> /workspace/build_info.txt
          echo "Project ID: $PROJECT_ID" >> /workspace/build_info.txt
          
          # Upload APKs and artifacts
          gsutil -m cp -r app/build/outputs gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
          gsutil cp /workspace/build_info.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
          
          # Get build logs URL
          echo "https://console.cloud.google.com/cloud-build/builds/$$BUILD_ID?project=$PROJECT_ID" > /workspace/build_logs_url.txt
          gsutil cp /workspace/build_logs_url.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
        EOT
      ]
      wait_for = var.enable_signing ? 
        ["build_debug", "build_release"] : 
        ["build_debug"]
    }
    
    # Send webhook notification
    step {
      name = "gcr.io/cloud-builders/curl"
      id   = "send_webhook"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Determine build status
          BUILD_STATUS="SUCCESS"
          APK_PATHS=""
          
          # Check if APKs were built
          if [[ -f app/build/outputs/apk/debug/app-debug.apk ]]; then
            APK_PATHS="Debug APK: gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/outputs/apk/debug/app-debug.apk"
          fi
          
          if [[ -f app/build/outputs/apk/release/app-release.apk ]]; then
            APK_PATHS="$$APK_PATHS\nRelease APK: gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/outputs/apk/release/app-release.apk"
          fi
          
          # Send webhook
          curl -X POST ${var.webhook_url} \
            -H "Content-Type: application/json" \
            -d '{
              "build_id": "'$$BUILD_ID'",
              "status": "'$$BUILD_STATUS'",
              "source_file": "'$$FILE_NAME'",
              "build_logs_url": "https://console.cloud.google.com/cloud-build/builds/'$$BUILD_ID'?project='$PROJECT_ID'",
              "artifacts_url": "gs://${google_storage_bucket.build_artifacts.name}/'$$BUILD_ID'/",
              "apk_paths": "'$$APK_PATHS'",
              "timestamp": "'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            }'
        EOT
      ]
      wait_for = ["upload_artifacts"]
    }
    
    # Save cache
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "save_cache"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Compressing cache..."
          tar -czf /workspace/cache.tgz -C /workspace .gradle
          echo "Uploading cache..."
          gsutil cp /workspace/cache.tgz gs://${google_storage_bucket.build_cache.name}/cache.tgz
        EOT
      ]
      wait_for = ["send_webhook"]
    }
    
    substitutions = merge({
      _FILE_NAME      = "app.zip"
      _WEBHOOK_URL    = var.webhook_url
      _PIPELINE_TYPE  = "android"
      _COMPILE_SDK    = var.android_compile_sdk
      _MIN_SDK        = var.android_min_sdk
      _TARGET_SDK     = var.android_target_sdk
      _GRADLE_VERSION = var.gradle_version
      _JAVA_VERSION   = var.java_version
    }, var.labels)
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloud_build_sa_roles
  ]
}

# Cloud Build trigger for manual builds (optional)
resource "google_cloudbuild_trigger" "android_manual_trigger" {
  name        = "android-manual-trigger"
  description = "Manual trigger for Android CI/CD builds"
  
  manual_trigger {}
  
  source_to_build {
    uri       = "gs://${google_storage_bucket.source_uploads.name}"
    ref       = "main"
    repo_type = "UNKNOWN"
  }
  
  build {
    timeout = var.build_timeout
    
    options {
      machine_type = var.machine_type
      disk_size_gb = var.disk_size_gb
      logging      = "CLOUD_LOGGING_ONLY"
      
      dynamic "pool" {
        for_each = var.enable_cost_optimization ? [1] : []
        content {
          name = google_cloudbuild_worker_pool.cost_optimized_pool.id
        }
      }
    }
    
    # Use the same build steps as the automated trigger
    # (Steps would be identical to above - omitted for brevity)
    
    substitutions = merge({
      _FILE_NAME      = "app.zip"
      _WEBHOOK_URL    = var.webhook_url
      _PIPELINE_TYPE  = "android"
      _COMPILE_SDK    = var.android_compile_sdk
      _MIN_SDK        = var.android_min_sdk
      _TARGET_SDK     = var.android_target_sdk
      _GRADLE_VERSION = var.gradle_version
      _JAVA_VERSION   = var.java_version
    }, var.labels)
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloud_build_sa_roles
  ]
}