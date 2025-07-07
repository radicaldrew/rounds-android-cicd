# Simplified approach - create Android builder image manually
# This avoids complex Cloud Build trigger issues

# Secret for future webhook triggers
resource "google_secret_manager_secret" "webhook_trigger_secret" {
  secret_id = "webhook-trigger-secret"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "webhook_secret" {
  secret      = google_secret_manager_secret.webhook_trigger_secret.id
  secret_data = "webhook-secret-${random_id.webhook_secret.hex}"
}

resource "random_id" "webhook_secret" {
  byte_length = 16
}

# Output instructions for manual image building
output "build_android_image_instructions" {
  description = "Instructions to build the Android builder image"
  value       = <<-EOT
# To build the Android builder image manually:

## Step 1: Create Dockerfile
cat > Dockerfile << 'EOF'
FROM ubuntu:22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl git unzip wget openjdk-${var.java_version}-jdk build-essential \
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

## Step 2: Build and push the image
gcloud builds submit --tag gcr.io/${var.project_id}/android-builder:latest .

## Step 3: Verify the image
gcloud container images list --repository=gcr.io/${var.project_id}
  EOT
}