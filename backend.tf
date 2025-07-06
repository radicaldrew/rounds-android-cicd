# Terraform Backend Configuration
# This file configures remote state storage in Google Cloud Storage
# Uncomment and configure after creating the state bucket

terraform {
  required_version = ">= 1.0"
  
  # Configure remote state backend
  backend "gcs" {
    bucket = "rounds-android-cicd-terraform-state"
    prefix = "rounds/android-cicd"
  }
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}