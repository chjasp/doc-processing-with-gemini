variable "project_id" {
  type        = string
  description = "The ID of the GCP project where resources will be created."
}

variable "region" {
  type        = string
  description = "Region in which resources will be created."
  default     = "us-central1"
}

variable "bucket_name" {
  type        = string
  description = "Name of the GCS bucket that will store PDFs."
}

variable "function_name" {
  type        = string
  description = "Name of the Cloud Function."
  default     = "handle_pdf"
}

variable "environment" {
  description = "The environment (e.g., dev, staging, prod)"
  type        = string
}

variable "gemini_model_name" {
  description = "The name of the Gemini model to use"
  type        = string
}
