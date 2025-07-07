# Cloud Build trigger for Pub/Sub events
resource "google_cloudbuild_trigger" "android_build_trigger" {
  name        = "android-build-trigger"
  location    = "global"
  description = "Trigger for Android CI/CD builds"
  service_account = google_service_account.cloud_build_sa.id
  
  pubsub_config {
    topic = google_pubsub_topic.android_app_uploads.id
  }
 
  build {
    timeout = var.build_timeout
    
    options {
      machine_type = var.enable_cost_optimization ? null : var.machine_type
      logging      = "CLOUD_LOGGING_ONLY"
      substitution_option = "ALLOW_LOOSE"
      disk_size_gb = var.enable_cost_optimization ? null : var.disk_size_gb
      worker_pool = var.enable_cost_optimization ? google_cloudbuild_worker_pool.cost_optimized_pool.id : null
    }
    
    # Download source from Cloud Storage
    step {
      name       = "gcr.io/cloud-builders/gsutil"
      id         = "download_source"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Processing Pub/Sub event..."
          echo "Using file: $_FILE_NAME"
          
          echo "Downloading file: $_FILE_NAME"
          gsutil cp gs://${google_storage_bucket.source_uploads.name}/$_FILE_NAME /workspace/source.zip
          
          echo "Extracting source..."
          unzip /workspace/source.zip -d /workspace/
          ls -la /workspace/
        EOT
      ]
    }

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

    # Initialize Gradle environment - CRITICAL: Do this once at the start
    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "init_gradle_environment"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Initializing Gradle environment..."
          
          # Set unique Gradle home for this build
          export GRADLE_USER_HOME="/workspace/.gradle-$$BUILD_ID"
          echo "GRADLE_USER_HOME=/workspace/.gradle-$$BUILD_ID" > /workspace/gradle_env.sh
          
          # Create directory structure
          mkdir -p "$$GRADLE_USER_HOME"
          chmod -R 755 "$$GRADLE_USER_HOME"
          
          # Kill any existing processes and clean locks
          pkill -f gradle || true
          sleep 3
          
          # Remove any existing daemon and lock files
          rm -rf "$$GRADLE_USER_HOME"/daemon/ || true
          rm -rf "$$GRADLE_USER_HOME"/caches/journal-1/ || true
          find "$$GRADLE_USER_HOME"/ -name "*.lock" -delete || true
          find /workspace/.gradle/ -name "*.lock" -delete || true
          
          # Ensure Gradle wrapper is executable
          chmod +x ./gradlew || true
          
          echo "Gradle environment initialized with home: $$GRADLE_USER_HOME"
        EOT
      ]
      wait_for = ["download_source", "extract_cache"]
    }

    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "setup_repositories"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Source the Gradle environment
          source /workspace/gradle_env.sh
          
          echo "Setting up repositories..."
          
          # Check if project uses JitPack (common for GitHub dependencies)
          if grep -q "jitpack.io" build.gradle* */build.gradle* 2>/dev/null; then
            echo "JitPack repository found"
          else
            echo "Adding JitPack repository support..."
            # Add JitPack to all build.gradle files that have repositories blocks
            find . -name "build.gradle*" -exec sed -i '/repositories\s*{/a\        maven { url "https://jitpack.io" }' {} \;
          fi
          
          find . -name "build.gradle*" -type f -exec sed -i '/repositories\s*{/a\        maven { url "https://jitpack.io" }' {} \;
          echo "Repository setup completed"
        EOT
      ]
      wait_for = ["init_gradle_environment"]
    }

    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "resolve_dependencies"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Source the Gradle environment
          source /workspace/gradle_env.sh
          
          echo "Resolving dependencies with Gradle home: $$GRADLE_USER_HOME"
          
          # Clean any existing daemon first
          ./gradlew --stop --no-daemon || true
          sleep 2
          
          # Try to resolve dependencies
          if ! ./gradlew dependencies --configuration debugCompileClasspath --no-daemon --no-configuration-cache; then
            echo "Some dependencies failed to resolve, attempting fixes..."
            
            # Common fixes for dependency issues
            echo "Clearing dependency cache..."
            rm -rf "$$GRADLE_USER_HOME"/caches/modules-2/files-2.1/ || true
            
            # Try with --refresh-dependencies
            ./gradlew clean --refresh-dependencies --no-daemon --no-configuration-cache || true
          fi
          
          echo "Dependency resolution completed"
        EOT
      ]
      env = [
        "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Xmx${var.gradle_memory} -Dorg.gradle.jvmargs=-Xmx${var.gradle_memory}"
      ]
      wait_for = ["setup_repositories"]
    }
    
    dynamic "step" {
      for_each = var.enable_signing ? [1] : []
      content {
        name = "gcr.io/cloud-builders/gcloud"
        id   = "get_secrets"
        entrypoint = "bash"
        args = [
          "-c",
          <<-EOT
            if gcloud secrets versions access latest --secret="android-keystore" > /workspace/release.keystore 2>/dev/null; then
              echo "Keystore retrieved successfully"
              gcloud secrets versions access latest --secret="keystore-properties" > /workspace/keystore.properties
              
              # Update the keystore path in the properties file
              sed -i 's|storeFile=.*|storeFile=/workspace/release.keystore|g' /workspace/keystore.properties
            else
              echo "No keystore found, will build debug version only"
            fi
          EOT
        ]
        wait_for = ["download_source"]
      }
    }
      
    dynamic "step" {
      for_each = var.enable_unit_tests ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/android-builder:latest"
        id   = "unit_tests"
        entrypoint = "bash"
        args = [
          "-c",
          <<-EOT
            # Source the Gradle environment
            source /workspace/gradle_env.sh
            
            echo "Running unit tests with Gradle home: $$GRADLE_USER_HOME"
            ./gradlew test --stacktrace --no-daemon --no-configuration-cache
          EOT
        ]
        env = [
          "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Xmx${var.gradle_memory} -Dorg.gradle.jvmargs=-Xmx${var.gradle_memory}"
        ]
        wait_for = ["resolve_dependencies"]
      }
    }

    dynamic "step" {
      for_each = var.enable_lint ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/android-builder:latest"
        id   = "lint_checks"
        entrypoint = "bash"
        args = [
          "-c",
          <<-EOT
            # Source the Gradle environment
            source /workspace/gradle_env.sh
            
            echo "Running lint checks with Gradle home: $$GRADLE_USER_HOME"
            ./gradlew lintDebug --stacktrace --no-daemon --no-configuration-cache
          EOT
        ]
        env = [
          "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Xmx${var.gradle_memory} -Dorg.gradle.jvmargs=-Xmx${var.gradle_memory}"
        ]
        wait_for = concat(
          ["resolve_dependencies"],
          var.enable_unit_tests ? ["unit_tests"] : []
        )
      }
    }

    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "build_debug"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Source the Gradle environment
          source /workspace/gradle_env.sh
          
          echo "Building debug APK with Gradle home: $$GRADLE_USER_HOME"
          ./gradlew assembleDebug --stacktrace --no-daemon --no-configuration-cache
        EOT
      ]
      env = [
        "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Xmx${var.gradle_memory} -Dorg.gradle.jvmargs=-Xmx${var.gradle_memory}"
      ]
      wait_for = concat(
        ["resolve_dependencies"],
        var.enable_unit_tests ? ["unit_tests"] : [],
        var.enable_lint ? ["lint_checks"] : []
      )
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
            # Source the Gradle environment
            source /workspace/gradle_env.sh
            echo "Building release APK with Gradle home: $$GRADLE_USER_HOME"
            if [[ -f /workspace/release.keystore ]]; then
              echo "Building release APK with signing"
              ./gradlew assembleRelease --stacktrace --no-daemon --no-configuration-cache
            else
              echo "No keystore found, skipping release build"
            fi
          EOT
        ]
        env = [
          "GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Xmx${var.gradle_memory} -Dorg.gradle.jvmargs=-Xmx${var.gradle_memory}"
        ]
        wait_for = concat(
          ["build_debug"],
          var.enable_signing ? ["get_secrets"] : []
        )
      }
    }
    
    # Clean up Gradle daemon BEFORE other operations
    step {
      name = "gcr.io/$PROJECT_ID/android-builder:latest"
      id   = "cleanup_gradle_daemon"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          # Source the Gradle environment
          source /workspace/gradle_env.sh
          
          echo "Cleaning up Gradle daemon..."
          ./gradlew --stop --no-daemon || true
          
          # Kill any remaining gradle processes
          pkill -f gradle || true
          sleep 2
          
          # Remove daemon directories
          rm -rf "$$GRADLE_USER_HOME"/daemon/ || true
          
          echo "Gradle daemon cleanup completed"
        EOT
      ]
      wait_for = concat(
        ["build_debug"],
        var.enable_signing ? ["build_release"] : []
      )
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
          echo "Source File: $_FILE_NAME" >> /workspace/build_info.txt
          echo "Project ID: $PROJECT_ID" >> /workspace/build_info.txt
          
          # Upload APKs and artifacts
          gsutil -m cp -r app/build/outputs gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
          gsutil cp /workspace/build_info.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
          
          # Get build logs URL
          echo "https://console.cloud.google.com/cloud-build/builds/$$BUILD_ID?project=$PROJECT_ID" > /workspace/build_logs_url.txt
          gsutil cp /workspace/build_logs_url.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
        EOT
      ]
      wait_for = ["cleanup_gradle_daemon"]
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


          TIMESTAMP=$$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
          # Use jq to properly construct JSON
          jq -n \
            --arg build_id "$$BUILD_ID" \
            --arg status "$$BUILD_STATUS" \
            --arg source_file "$$SOURCE_FILE" \
            --arg logs_url "https://console.cloud.google.com/cloud-build/builds/$$BUILD_ID?project=$$PROJECT_ID" \
            --arg artifacts_url "gs://$$BUCKET_NAME/$$BUILD_ID/" \
            --arg apk_paths "$$APK_PATHS" \
            --arg timestamp "$$TIMESTAMP" \
            '{
              build_id: $$build_id,
              status: $$status,
              source_file: $$source_file,
              build_logs_url: $$logs_url,
              artifacts_url: $$artifacts_url,
              apk_paths: $$apk_paths,
              timestamp: $$timestamp
            }' > /workspace/webhook_payload.json
          
          # Send webhook
          curl -X POST ${var.webhook_url} \
            -H "Content-Type: application/json" \
            -d @/workspace/webhook_payload.json \
            -w "HTTP Status: %%{http_code}\n" \
            -v
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
          # Source the Gradle environment
          source /workspace/gradle_env.sh
          
          echo "Compressing cache from: $$GRADLE_USER_HOME"
          if [[ -d "$$GRADLE_USER_HOME" ]]; then
            tar -czf /workspace/cache.tgz -C "$$GRADLE_USER_HOME" .
            echo "Uploading cache..."
            gsutil cp /workspace/cache.tgz gs://${google_storage_bucket.build_cache.name}/cache.tgz
          else
            echo "No Gradle cache directory found to save"
          fi
        EOT
      ]
      wait_for = ["send_webhook"]
    }
    
    substitutions = merge({
      _FILE_NAME      = "app.zip"  # Default value
      _WEBHOOK_URL    = var.webhook_url
      _PIPELINE_TYPE  = "android"
      _COMPILE_SDK    = var.android_compile_sdk
      _MIN_SDK        = var.android_min_sdk
      _TARGET_SDK     = var.android_target_sdk
      _GRADLE_VERSION = var.gradle_version
      _JAVA_VERSION   = var.java_version
    }, {
      # Convert labels to valid substitution format
      for k, v in var.labels : "_${upper(replace(k, "-", "_"))}" => v
    })
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloud_build_sa_roles
  ]
}

# Cloud Build trigger for manual builds
resource "google_cloudbuild_trigger" "android_manual_trigger" {
  name        = "android-manual-trigger"
  description = "Manual trigger for Android CI/CD builds"
  service_account = google_service_account.cloud_build_sa.id
  
  # Manual trigger configuration
  trigger_template {
    tag_name = "manual-trigger"
    project_id = var.project_id
    repo_name  = "manual-trigger"
  }
  
  build {
    timeout = var.build_timeout
    
    options {
      machine_type = var.enable_cost_optimization ? null : var.machine_type
      logging      = "CLOUD_LOGGING_ONLY"
      substitution_option = "ALLOW_LOOSE"
      disk_size_gb = var.enable_cost_optimization ? null : var.disk_size_gb
      worker_pool = var.enable_cost_optimization ? google_cloudbuild_worker_pool.cost_optimized_pool.id : null
    }
    
    # Simple build step for manual trigger
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "download_source"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Processing manual trigger..."
          echo "Using file: $_FILE_NAME"
          
          echo "Downloading file: $_FILE_NAME"
          gsutil cp gs://${google_storage_bucket.source_uploads.name}/$_FILE_NAME /workspace/source.zip
          
          echo "Extracting source..."
          unzip /workspace/source.zip -d /workspace/
          ls -la /workspace/
        EOT
      ]
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