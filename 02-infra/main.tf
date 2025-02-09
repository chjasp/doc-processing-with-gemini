###########################
# Enable Required Services
###########################
resource "google_project_service" "enable_storage" {
  project = var.project_id
  service = "storage.googleapis.com"
}

resource "google_project_service" "enable_pubsub" {
  project = var.project_id
  service = "pubsub.googleapis.com"
}

resource "google_project_service" "enable_cloudfunctions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
}

resource "google_project_service" "enable_firestore" {
  project = var.project_id
  service = "firestore.googleapis.com"
}

# Required for Firestore
resource "google_project_service" "enable_appengine" {
  project = var.project_id
  service = "appengine.googleapis.com"
}

########################
# Create Storage Bucket
########################
resource "google_storage_bucket" "pdf_bucket" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
  
  depends_on = [
    google_project_service.enable_storage
  ]
}

###################################
# Create Pub/Sub Topic for uploads
###################################
resource "google_pubsub_topic" "pdf_topic" {
  name      = "pdf-upload-topic"
  project   = var.project_id
  depends_on = [
    google_project_service.enable_pubsub
  ]
}

####################################################
# Create GCS Notification to trigger Pub/Sub message
####################################################
resource "google_storage_notification" "pdf_notification" {
  bucket         = google_storage_bucket.pdf_bucket.name
  topic          = google_pubsub_topic.pdf_topic.id
  event_types    = ["OBJECT_FINALIZE"]
  payload_format = "JSON_API_V1"

  depends_on = [
    google_storage_bucket.pdf_bucket,
    google_pubsub_topic.pdf_topic
  ]
}

########################################################
# Create a separate bucket to store Cloud Function code
########################################################
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.bucket_name}-function-code"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  depends_on = [
    google_project_service.enable_storage
  ]
}

############################################
# Package the function code as a .zip archive
############################################
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../01-app"
  output_path = "${path.module}/function_source.zip"
}

###################################################
# Upload the zipped code to the function source bucket
###################################################
resource "google_storage_bucket_object" "function_source_object" {
  name   = "function_source.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_zip.output_path
  depends_on = [
    google_storage_bucket.function_source_bucket
  ]
}

########################
# Deploy the Cloud Function
########################
resource "google_cloudfunctions_function" "handle_pdf" {
  name        = var.function_name
  runtime     = "python39"
  region      = var.region
  entry_point = "handle_pdf"
  max_instances = 3

  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.function_source_object.name

  environment_variables = {
    ENVIRONMENT       = var.environment
    GEMINI_MODEL_NAME = var.gemini_model_name
  }

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.pdf_topic.name
  }

  depends_on = [
    google_project_service.enable_cloudfunctions
  ]
}

#######################################
# Grant the Cloud Function required IAM
#######################################
# So it can read from the bucket, subscribe to Pub/Sub, and write to Firestore.
resource "google_project_iam_member" "function_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_cloudfunctions_function.handle_pdf.service_account_email}"

  depends_on = [
    google_cloudfunctions_function.handle_pdf,
    google_project_service.enable_pubsub
  ]
}

resource "google_project_iam_member" "function_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_cloudfunctions_function.handle_pdf.service_account_email}"

  depends_on = [
    google_cloudfunctions_function.handle_pdf,
    google_project_service.enable_storage
  ]
}

resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_cloudfunctions_function.handle_pdf.service_account_email}"

  depends_on = [
    google_cloudfunctions_function.handle_pdf,
    google_project_service.enable_firestore
  ]
}
