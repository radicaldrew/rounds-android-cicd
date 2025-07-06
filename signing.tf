resource "google_secret_manager_secret" "android_keystore" {
  secret_id = "android-keystore"
  
  replication {
    auto {}
  }
  
  labels = merge(var.labels, {
    purpose = "android-signing"
    type    = "keystore"
  })
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "keystore_properties" {
  secret_id = "keystore-properties"
  
  replication {
    auto {}
  }
  
  labels = merge(var.labels, {
    purpose = "android-signing"
    type    = "properties"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Secret versions (optional - you can upload manually instead)
resource "google_secret_manager_secret_version" "keystore_properties" {
  count = var.keystore_password != "" && var.key_password != "" && var.key_alias != "" ? 1 : 0
  
  secret = google_secret_manager_secret.keystore_properties.id
  secret_data = <<-EOT
storeFile=release.keystore
storePassword=${var.keystore_password}
keyAlias=${var.key_alias}
keyPassword=${var.key_password}
EOT
}

# IAM for Secret Manager access
resource "google_secret_manager_secret_iam_member" "cloud_build_keystore_access" {
  for_each = toset([
    google_secret_manager_secret.android_keystore.secret_id,
    google_secret_manager_secret.keystore_properties.secret_id
  ])
  
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build_sa.email}"
  
  condition {
    title       = "Android Build Access Only"
    description = "Restrict access to Cloud Build service account for Android builds"
    expression  = "request.time < timestamp('2025-12-31T23:59:59Z')" # Update annually
  }
}

# Audit logging configuration for signing operations
resource "google_logging_project_sink" "android_signing_audit" {
  name        = "android-signing-audit-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.security_audit_logs.name}"
  
  filter = <<-EOT
    resource.type="secret_manager_secret"
    AND resource.labels.secret_id=~"android-.*"
    AND protoPayload.methodName=~".*Access.*"
  EOT
  
  unique_writer_identity = true
}

# Security audit logs bucket
resource "google_storage_bucket" "security_audit_logs" {
  name          = "${var.project_id}-security-audit-logs"
  location      = var.region
  force_destroy = false
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 2555 # 7 years retention for audit logs
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Email Notification"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}

# Output signing configuration for reference
output "signing_secrets_info" {
  description = "Information about signing secrets configuration"
  value = {
    keystore_secret_id = google_secret_manager_secret.android_keystore.secret_id
    properties_secret_id = google_secret_manager_secret.keystore_properties.secret_id
    audit_bucket      = google_storage_bucket.security_audit_logs.name
  }
  sensitive = false
}

output "signing_setup_instructions" {
  description = "Instructions for setting up signing keys"
  value = <<-EOT
    To set up your Android signing keys:
    
    1. Upload your keystore file:
       gcloud secrets versions add android-keystore --data-file=your-keystore.jks
    
    2. Create and upload keystore.properties file:
       Create a file named keystore.properties with the following content:
       
       storeFile=release.keystore
       storePassword=your-keystore-password
       keyAlias=your-key-alias
       keyPassword=your-key-password
       
       Then upload it:
       gcloud secrets versions add keystore-properties --data-file=keystore.properties
    
    3. Verify the setup:
       gcloud secrets versions access latest --secret=android-keystore > test-keystore.jks
       gcloud secrets versions access latest --secret=keystore-properties > test-keystore.properties
       
       # Check keystore
       keytool -list -keystore test-keystore.jks
       
       # Clean up test files
       rm test-keystore.jks test-keystore.properties
    
    Note: The keystore.properties file should follow standard Android conventions.
  EOT
}