import json
import vertexai
import functions_framework
from google.cloud import firestore
from vertexai.generative_models import GenerativeModel, Part

db = firestore.Client()
vertexai.init()

model = GenerativeModel("gemini-2.0-pro-exp-02-05")


@functions_framework.cloud_event
def handle_pdf(cloud_event):
    print(f"Event: {cloud_event.data}")
    
    bucket_name = cloud_event.data.get("bucket")
    file_name = cloud_event.data.get("name")

    print(f"New file: {file_name} in bucket: {bucket_name}")

    gcs_uri = f"gs://{bucket_name}/{file_name}"
    prompt = "OCR this document and output JSON with relevant fields"

    pdf_part = Part.from_uri(uri=gcs_uri, mime_type="application/pdf")
    contents = [pdf_part, prompt]

    response = model.generate_content(contents)
    gemini_response = response.text
    gemini_response_stripped = (
        gemini_response.replace("```json", "").replace("```", "").strip()
    )

    parsed_data = json.loads(gemini_response_stripped)

    print(f"Parsed Gemini response: {parsed_data}")

    doc_ref = db.collection("pdfs").document(file_name)
    doc_ref.set(parsed_data)

    print(f"Processed and stored data for {file_name}")
    
    
    
    

