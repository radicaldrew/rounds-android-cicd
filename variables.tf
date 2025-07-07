variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "rounds-android-cicd"
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "webhook_url" {
  type        = string
  description = "Webhook URL for the build"
  default     = "https://webhook.site/ad776bd7-89c9-4ba2-83d7-8cf9f5975dc7"
  validation {
    condition     = can(regex("^https?://", var.webhook_url))
    error_message = "The webhook_url must be a valid HTTP or HTTPS URL."
  }
}

variable "build_timeout" {
  description = "Build timeout in seconds"
  type        = string
  default     = "1800s"
}

variable "machine_type" {
  description = "Machine type for Cloud Build"
  type        = string
  default     = "E2_MEDIUM"
}

variable "disk_size_gb" {
  description = "Disk size in GB for Cloud Build"
  type        = number
  default     = 100
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "cache_retention_days" {
  description = "Number of days to retain build cache"
  type        = number
  default     = 7
}

variable "artifact_retention_days" {
  description = "Number of days to retain build artifacts"
  type        = number
  default     = 90
}

variable "source_retention_days" {
  description = "Number of days to retain source uploads"
  type        = number
  default     = 30
}

variable "notification_email" {
  description = "Email address for build notifications"
  type        = string
  default     = ""
}

variable "android_compile_sdk" {
  description = "Android compile SDK version"
  type        = string
  default     = "34"
}

variable "android_min_sdk" {
  description = "Android minimum SDK version"
  type        = string
  default     = "21"
}

variable "android_target_sdk" {
  description = "Android target SDK version"
  type        = string
  default     = "34"
}

variable "gradle_version" {
  description = "Gradle version to use"
  type        = string
  default     = "8.2"
}

variable "java_version" {
  description = "Java version to use"
  type        = string
  default     = "17"
}

variable "enable_signing" {
  description = "Enable APK signing with keystore"
  type        = bool
  default     = false
}

variable "keystore_password" {
  description = "Keystore password (will be stored in Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "key_password" {
  description = "Key password (will be stored in Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "key_alias" {
  description = "Key alias (will be stored in Secret Manager)"
  type        = string
  default     = ""
}

variable "enable_parallel_builds" {
  description = "Enable parallel Gradle builds"
  type        = bool
  default     = true
}

variable "gradle_max_workers" {
  description = "Maximum number of Gradle workers"
  type        = number
  default     = 4
}

variable "gradle_memory" {
  description = "Gradle JVM memory allocation"
  type        = string
  default     = "3g"
}

variable "enable_lint" {
  description = "Enable Android lint checks"
  type        = bool
  default     = false
}

variable "enable_unit_tests" {
  description = "Enable unit tests"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    project     = "rounds-android-cicd"
    environment = "production"
    team        = "mobile"
  }
}

variable "billing_account_id" {
  description = "GCP billing account ID for budget alerts"
  type        = string
  default     = ""
}
