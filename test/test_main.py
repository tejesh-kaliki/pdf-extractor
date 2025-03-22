import io
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from src.main import app
import difflib

client = TestClient(app)


def test_upload_file(test_dir: Path):
    """
    Test uploading a PDF file and comparing the extracted text with the expected content.

    This test validates the PDF extraction functionality through the API endpoint by comparing
    the extracted text against a pre-defined reference file (golden snapshot). The comparison
    uses a similarity ratio to account for minor formatting differences while still ensuring
    the extraction is accurate.

    Args:
        test_dir (Path): Directory containing test files and reference data

    Test Steps:
        1. Load the test PDF file from the test directory
        2. Send a POST request to the /uploadfile/ endpoint with the PDF
        3. Verify the response status code is 200 (OK)
        4. Compare the extracted text against the expected content
        5. Assert that the similarity is above 99%

    The reference file (test-file-1.txt) contains the expected extracted text from
    the PDF and is used as the golden snapshot for comparison.
    """
    pdf_path = test_dir / "test-file-1.pdf"
    expected_content_path = test_dir / "test-file-1.txt"

    file = io.BytesIO(pdf_path.read_bytes())

    response: httpx.Response = client.post(
        "/extract-pdf", files={"file": ("test-file-1.pdf", file, "application/pdf")}
    )

    assert response.status_code == 200

    expected_content = expected_content_path.read_text()
    similarity = difflib.SequenceMatcher(None, response.text, expected_content).ratio()
    assert similarity > 0.99, f"Expected similarity > 0.99, got {similarity}"
