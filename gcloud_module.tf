# Build and push Android builder Docker image
module "android_builder_image" {
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    set -e
    
    # Create temporary directory for build context
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # Create Dockerfile for Android builder
    cat > Dockerfile << 'EOF'
FROM ubuntu:22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    wget \
    openjdk-${var.java_version}-jdk \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set Java environment
ENV JAVA_HOME=/usr/lib/jvm/java-${var.java_version}-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin

# Install Android SDK
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

RUN mkdir -p $ANDROID_HOME && \
    cd $ANDROID_HOME && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip && \
    unzip commandlinetools-linux-7583922_latest.zip && \
    rm commandlinetools-linux-7583922_latest.zip && \
    mv cmdline-tools latest && \
    mkdir cmdline-tools && \
    mv latest cmdline-tools/

# Accept licenses and install packages
RUN yes | sdkmanager --licenses && \
    sdkmanager --update && \
    sdkmanager \
        "platform-tools" \
        "build-tools;${var.android_compile_sdk}.0.0" \
        "platforms;android-${var.android_compile_sdk}" \
        "platforms;android-${var.android_min_sdk}"

# Install Gradle
RUN wget -q https://services.gradle.org/distributions/gradle-${var.gradle_version}-bin.zip && \
    unzip gradle-${var.gradle_version}-bin.zip && \
    mv gradle-${var.gradle_version} /opt/gradle && \
    rm gradle-${var.gradle_version}-bin.zip

ENV PATH=$PATH:/opt/gradle/bin
WORKDIR /workspace
EOF

    # Build and push the image
    gcloud builds submit --tag gcr.io/${var.project_id}/android-builder:latest .
    
    # Clean up
    cd /
    rm -rf $TEMP_DIR
  EOT
  
  depends_on = [google_project_service.required_apis]
}

# Upload Cloud Build configuration files
module "upload_build_configs" {
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    set -e
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # Create complete cloudbuild.yaml
    cat > cloudbuild.yaml << 'EOF'
steps:
  # Download source code from Cloud Storage
  - name: 'gcr.io/cloud-builders/gsutil'
    id: 'download_source'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Downloading source from: gs://${google_storage_bucket.source_uploads.name}/$${_FILE_NAME}"
        gsutil cp gs://${google_storage_bucket.source_uploads.name}/$${_FILE_NAME} /workspace/source.zip
        unzip /workspace/source.zip -d /workspace/
        ls -la /workspace/

  # Extract build cache
  - name: 'gcr.io/cloud-builders/gsutil'
    id: 'extract_cache'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        if gsutil cp gs://${google_storage_bucket.build_cache.name}/cache.tgz /workspace/cache.tgz; then
          echo "Cache found, extracting..."
          tar -xzf /workspace/cache.tgz -C /workspace/
        else
          echo "No cache found, starting fresh"
          mkdir -p /workspace/.gradle
        fi
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'

  # Get signing secrets
  - name: 'gcr.io/cloud-builders/gcloud'
    id: 'get_secrets'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        if gcloud secrets versions access latest --secret="android-keystore" > /workspace/keystore.jks 2>/dev/null; then
          echo "Keystore retrieved successfully"
          gcloud secrets versions access latest --secret="keystore-properties" > /workspace/keystore.properties
        else
          echo "No keystore found, will build debug version only"
        fi
    waitFor: ['download_source']

  # Run unit tests
  - name: 'gcr.io/$PROJECT_ID/android-builder:latest'
    id: 'unit_tests'
    args: ['./gradlew', 'testDebugUnitTest', '--stacktrace']
    env:
      - 'GRADLE_USER_HOME=/workspace/.gradle'
      - 'GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}'
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'
    waitFor: ['extract_cache']

  # Run lint checks
  - name: 'gcr.io/$PROJECT_ID/android-builder:latest'
    id: 'lint_checks'
    args: ['./gradlew', 'lintDebug', '--stacktrace']
    env:
      - 'GRADLE_USER_HOME=/workspace/.gradle'
      - 'GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}'
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'
    waitFor: ['extract_cache']

  # Build debug APK
  - name: 'gcr.io/$PROJECT_ID/android-builder:latest'
    id: 'build_debug'
    args: ['./gradlew', 'assembleDebug', '--stacktrace']
    env:
      - 'GRADLE_USER_HOME=/workspace/.gradle'
      - 'GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}'
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'
    waitFor: ['unit_tests', 'lint_checks']

  # Build release APK
  - name: 'gcr.io/$PROJECT_ID/android-builder:latest'
    id: 'build_release'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        if [[ -f /workspace/keystore.jks ]]; then
          echo "Building release APK with signing"
          ./gradlew assembleRelease --stacktrace
        else
          echo "No keystore found, skipping release build"
        fi
    env:
      - 'GRADLE_USER_HOME=/workspace/.gradle'
      - 'GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=${var.gradle_max_workers} -Xmx${var.gradle_memory}'
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'
    waitFor: ['get_secrets', 'unit_tests', 'lint_checks']

  # Upload artifacts
  - name: 'gcr.io/cloud-builders/gsutil'
    id: 'upload_artifacts'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        # Create build info
        echo "Build ID: $$BUILD_ID" > /workspace/build_info.txt
        echo "Build Time: $$(date)" >> /workspace/build_info.txt
        echo "Source File: $${_FILE_NAME}" >> /workspace/build_info.txt
        
        # Upload APKs and artifacts
        gsutil -m cp -r app/build/outputs gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
        gsutil cp /workspace/build_info.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
        
        # Get build logs URL
        echo "https://console.cloud.google.com/cloud-build/builds/$$BUILD_ID?project=$$PROJECT_ID" > /workspace/build_logs_url.txt
        gsutil cp /workspace/build_logs_url.txt gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/
    waitFor: ['build_debug', 'build_release']

  # Send webhook notification
  - name: 'gcr.io/cloud-builders/curl'
    id: 'send_webhook'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        BUILD_STATUS="SUCCESS"
        APK_PATHS=""
        
        if [[ -f app/build/outputs/apk/debug/app-debug.apk ]]; then
          APK_PATHS="Debug APK: gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/outputs/apk/debug/app-debug.apk"
        fi
        
        if [[ -f app/build/outputs/apk/release/app-release.apk ]]; then
          APK_PATHS="$$APK_PATHS\nRelease APK: gs://${google_storage_bucket.build_artifacts.name}/$$BUILD_ID/outputs/apk/release/app-release.apk"
        fi
        
        curl -X POST $${_WEBHOOK_URL} \
          -H "Content-Type: application/json" \
          -d '{
            "build_id": "'$$BUILD_ID'",
            "status": "'$$BUILD_STATUS'",
            "source_file": "'$${_FILE_NAME}'",
            "build_logs_url": "https://console.cloud.google.com/cloud-build/builds/'$$BUILD_ID'?project='$$PROJECT_ID'",
            "artifacts_url": "gs://${google_storage_bucket.build_artifacts.name}/'$$BUILD_ID'/",
            "apk_paths": "'$$APK_PATHS'",
            "timestamp": "'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
          }'
    waitFor: ['upload_artifacts']

  # Save cache
  - name: 'gcr.io/cloud-builders/gsutil'
    id: 'save_cache'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Compressing cache..."
        tar -czf /workspace/cache.tgz -C /workspace .gradle
        echo "Uploading cache..."
        gsutil cp /workspace/cache.tgz gs://${google_storage_bucket.build_cache.name}/cache.tgz
    volumes:
      - name: 'gradle_cache'
        path: '/workspace/.gradle'
    waitFor: ['send_webhook']

substitutions:
  _FILE_NAME: 'app.zip'
  _WEBHOOK_URL: '${var.webhook_url}'
  _PIPELINE_TYPE: 'android'

options:
  machineType: '${var.machine_type}'
  diskSizeGb: ${var.disk_size_gb}
  logging: CLOUD_LOGGING_ONLY

timeout: ${var.build_timeout}
EOF

    # Upload the build configuration to Cloud Storage
    gsutil cp cloudbuild.yaml gs://${google_storage_bucket.source_uploads.name}/configs/
    
    # Clean up
    cd /
    rm -rf $TEMP_DIR
    
    echo "Build configuration uploaded successfully"
  EOT
  
  depends_on = [
    google_storage_bucket.source_uploads,
    module.android_builder_image
  ]
}

# Set up keystore properties if signing is enabled
module "setup_keystore_properties" {
  count = var.enable_signing && var.keystore_password != "" ? 1 : 0
  
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    set -e
    
    # Create keystore properties file
    cat > /tmp/keystore.properties << EOF
storePassword=${var.keystore_password}
keyPassword=${var.key_password}
keyAlias=${var.key_alias}
storeFile=/workspace/keystore.jks
EOF
    
    # Store in Secret Manager
    gcloud secrets versions add keystore-properties --data-file=/tmp/keystore.properties
    
    # Clean up
    rm /tmp/keystore.properties
    
    echo "Keystore properties configured successfully"
  EOT
  
  depends_on = [
    google_secret_manager_secret.keystore_properties,
    google_project_service.required_apis
  ]
}

# Create monitoring dashboard
module "create_monitoring_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    set -e
    
    # Create dashboard configuration
    cat > /tmp/dashboard.json << 'EOF'
{
  "displayName": "Android CI/CD Pipeline Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Build Success Rate",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/android_build_success\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Build Failures",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/android_build_failures\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            }
          }
        }
      },
      {
        "width": 12,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Build Duration",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"logging.googleapis.com/user/android_build_duration\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }],
            "yAxis": {
              "label": "Duration (seconds)",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the dashboard
    gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json
    
    # Clean up
    rm /tmp/dashboard.json
    
    echo "Monitoring dashboard created successfully"
  EOT
  
  depends_on = [
    google_logging_metric.android_build_success,
    google_logging_metric.android_build_failures,
    google_logging_metric.android_build_duration
  ]
}

# Set up alerting policies
module "setup_alerting" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    set -e
    
    # Create notification channel for email
    CHANNEL_ID=$(gcloud alpha monitoring channels create \
      --display-name="Android CI/CD Email Notifications" \
      --type=email \
      --channel-labels=email_address=${var.notification_email} \
      --format="value(name)" | sed 's|.*/||')
    
    # Create alerting policy for build failures
    cat > /tmp/alert_policy.json << EOF
{
  "displayName": "Android Build Failures",
  "conditions": [
    {
      "displayName": "Build failure condition",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/android_build_failures\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "60s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "86400s"
  },
  "notificationChannels": [
    "projects/${var.project_id}/notificationChannels/$$CHANNEL_ID"
  ]
}
EOF
    
    # Create the alerting policy
    gcloud alpha monitoring policies create --policy-from-file=/tmp/alert_policy.json
    
    # Clean up
    rm /tmp/alert_policy.json
    
    echo "Alerting policies configured successfully"
  EOT
  
  depends_on = [
    google_logging_metric.android_build_failures,
    google_project_service.required_apis
  ]
}

# Clean up old builds and artifacts
module "cleanup_old_artifacts" {
  source = "terraform-google-modules/gcloud/google"
  version = "~> 3.4"
  
  platform = "linux"
  
  create_cmd_entrypoint = "bash"
  create_cmd_body = <<-EOT
    # This will be executed during terraform apply
    # Set up lifecycle policies have already been configured in main.tf
    # This module can be used for additional cleanup logic if needed
    
    echo "Cleanup policies configured via bucket lifecycle rules"
  EOT
  
  depends_on = [
    google_storage_bucket.source_uploads,
    google_storage_bucket.build_artifacts,
    google_storage_bucket.build_cache
  ]
}