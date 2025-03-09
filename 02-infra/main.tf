
#
# Bucket to store the Cloud Function code: "function_source_bucket"
#
resource "google_storage_bucket" "function_source_bucket" {
  name                        = "${var.bucket_name}-function-code"
  location                    = var.region
  uniform_bucket_level_access = true
}

#
# Archive the function source code
#
data "archive_file" "default" {
  type        = "zip"
  source_dir  = "${path.module}/../01-app"
  output_path = "${path.module}/function_source.zip"
}

#
# Upload the zipped code to the function source bucket
#
resource "google_storage_bucket_object" "default" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.default.output_path
}

#
# Bucket that triggers the function: "pdf_bucket"
#
resource "google_storage_bucket" "pdf_bucket" {
  name                        = var.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
}

#
# Get the GCS service account for Pub/Sub publishing
#
data "google_storage_project_service_account" "default" {
}

#
# Identify the project so we can apply roles
#
data "google_project" "project" {
}

#
# Grant Pub/Sub Publisher so GCS can publish events
#
resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.default.email_address}"
}

#
# Service account used by the function & trigger
#
resource "google_service_account" "account" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account - used for both the cloud function and eventarc trigger in the test"
}

#
# IAM bindings for invocation/event receiving, etc.
#
resource "google_project_iam_member" "invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.account.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "event_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.account.email}"
  depends_on = [google_project_iam_member.invoking]
}

resource "google_project_iam_member" "artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.account.email}"
  depends_on = [google_project_iam_member.event_receiving]
}

#
# Cloud Function (2nd Gen), renamed to "handle_pdf" using names from Code 1
#
resource "google_cloudfunctions2_function" "handle_pdf" {
  depends_on = [
    google_project_iam_member.event_receiving,
    google_project_iam_member.artifactregistry_reader,
  ]
  name        = var.function_name
  location    = var.region

  build_config {
    runtime     = "python39"
    entry_point = "handle_pdf"
    environment_variables = {
      ENVIRONMENT       = var.environment
      GEMINI_MODEL_NAME = var.gemini_model_name
    }

    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.default.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    available_memory   = "2048M"
    timeout_seconds    = 60
    environment_variables = {
      SERVICE_CONFIG_TEST = "config_test"
    }
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.account.email
  }

  # Using an event_trigger block for GCS finalize (instead of Eventarc resource)
  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.account.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.pdf_bucket.name
    }
  }
}

resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_cloudfunctions2_function.handle_pdf.service_config[0].service_account_email}"

  depends_on = [
    google_cloudfunctions2_function.handle_pdf
  ]
}

resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_cloudfunctions2_function.handle_pdf.service_config[0].service_account_email}"

  depends_on = [
    google_cloudfunctions2_function.handle_pdf
  ]
}
