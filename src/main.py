import io
from fastapi import FastAPI, UploadFile
from fastapi.responses import PlainTextResponse

from src.extract_pdf import extract_text_from_pdf

app = FastAPI(
    title="PDF Text Extraction API",
    description="API for extracting text content from PDF files",
    version="1.0.0",
)


@app.get(
    "/health",
    summary="Health Check Endpoint",
    description="Returns the status of the service to verify it's running properly",
    response_description="Returns a JSON object with 'status' field set to 'ok'",
)
async def health_check():
    """
    Simple health check endpoint to verify the service is running.

    Returns:
        dict: A dictionary with a status indicator
    """
    return {"status": "ok"}


@app.post(
    "/extract-pdf",
    response_class=PlainTextResponse,
    summary="Extract Text from PDF",
    description="Extracts all text content from an uploaded PDF file",
    response_description="Returns the extracted text content as plain text",
)
async def extract_pdf(file: UploadFile):
    """
    Extracts text content from an uploaded PDF file.

    This endpoint processes the uploaded PDF file and extracts all readable text
    content, returning it as a plain text response.

    Args:
        file (UploadFile): The PDF file to extract text from

    Returns:
        str: The extracted text content from the PDF

    Raises:
        HTTPException: If the file format is invalid or text extraction fails
    """
    contents = await file.read()
    with io.BytesIO(contents) as file_stream:
        content = extract_text_from_pdf(file_stream)

    print("Extracted content:", content.decode("utf-8"))
    return content.decode("utf-8")
