import base64
import os
import json

# Conditionally load dotenv for local development
if os.getenv("ENVIRONMENT") != "production":
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass

import vertexai
from vertexai.generative_models import GenerativeModel, Part
from google.cloud import storage, firestore

PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT")
MODEL_NAME = os.getenv("GEMINI_MODEL_NAME")

# Initialize clients outside the function for performance
storage_client = storage.Client()
db = firestore.Client()
vertexai.init(project=PROJECT_ID)
model = GenerativeModel(MODEL_NAME)

def handle_pdf(event, context):
    # Parse the Pub/Sub message

    attributes = event.get('attributes', {})

    bucket_id = attributes.get('bucketId')
    object_id = attributes.get('objectId')

    print(f"New file: {object_id} in bucket: {bucket_id}")

    # Create GCS URI for the PDF
    gcs_uri = f"gs://{bucket_id}/{object_id}"

    # Create prompt and PDF part
    prompt = "OCR this document and output JSON with relevant fields"
    
    pdf_part = Part.from_uri(
        uri=gcs_uri,
        mime_type='application/pdf'
    )
    contents = [pdf_part, prompt]
    
    response = model.generate_content(contents)
    gemini_response = response.text
    gemini_response_stripped = gemini_response.replace("```json", "").replace("```", "").strip()
    
    parsed_data = json.loads(gemini_response_stripped)
    
    print(f"Parsed Gemini response: {parsed_data}")

    # Store result in Firestore using the parsed dictionary directly
    doc_ref = db.collection('pdfs').document(object_id)
    doc_ref.set(parsed_data)
    
    print(f"Processed and stored data for {object_id}")
