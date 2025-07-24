provider "google" {
  project = var.project
  region  = var.region
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

locals {
  resource_name_prefix = "${var.name}-${var.environment}"
}

resource "google_service_account" "service_account" {
  account_id   = "${local.resource_name_prefix}-api"
  display_name = "Git LFS function service account"
}

resource "google_project_iam_binding" "role_binding" {
  project = var.project
  role    = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
}

resource "google_service_account_key" "key" {
  service_account_id = google_service_account.service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "local_file" "credentials" {
  content  = base64decode(google_service_account_key.key.private_key)
  filename = "${path.module}/credentials.json"

  provisioner "local-exec" {
    command = "zip -r ${path.module}/function_source.zip credentials.json && rm -rf credentials.json"
  }
}

resource "google_storage_bucket_object" "source_archive" {
  name   = "src/${uuid()}.zip"
  bucket = var.bucket_name
  source = "${path.module}/function_source.zip"

  depends_on = [
    local_file.credentials
  ]
}

resource "google_cloudfunctions2_function" "function" {
  name        = "${local.resource_name_prefix}-api"
  location    = var.region
  description = "This function coordinate fetching and storing Git LFS objects"

  build_config {
    runtime     = "python311"  # Updated to Python 3.11
    entry_point = "function_handler"
    source {
      storage_source {
        bucket = var.bucket_name
        object = google_storage_bucket_object.source_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory     = "128Mi"
    timeout_seconds      = 30
    service_account_email = google_service_account.service_account.email
    environment_variables = {
      LOG_LEVEL                      = "INFO"
      BUCKET_NAME                    = var.bucket_name
      GOOGLE_APPLICATION_CREDENTIALS = "credentials.json"
    }
  }
}

resource "google_cloud_run_service_iam_member" "member" {
  location = google_cloudfunctions2_function.function.location
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "function_uri" {
  value = google_cloudfunctions2_function.function.service_config[0].uri
}
