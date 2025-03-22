# PDF Processor

A simple tool to extract text from PDF files.

## Description

PDF Processor is a Python service that extracts text content from PDF files. It provides a REST API endpoint that allows users to upload PDF files and receive the extracted text in response.

## Installation

### Using make

```bash
# Install dependencies using uv
make install

# Run the application
make run

# Run tests
make test
```

### Using Docker

```bash
# Build the Docker image
make docker-compose-build
# or
docker-compose -f docker/docker-compose.yml build

# Run using Docker
make docker-compose-up
# or
docker-compose -f docker/docker-compose.yml up -d

# Stop Docker containers
make docker-compose-down
```

### Build and Deploy

For production deployment with multi-architecture support:

```bash
# Build Docker image for current architecture
make build

# Optimize image size with docker-slim
make slim-images

# Run the optimized slim image
make run-slim

# Deploy to AWS ECR (requires AWS credentials)
export AWS_ACCOUNT_ID=your_account_id
export AWS_REGION=your_region
make deploy
```

## API Usage

Once the service is running, you can access the API endpoint:

```
POST /extract-pdf
```

### Example Request

Using curl:

```bash
curl -X POST \
  -F "file=@path/to/file.pdf" \
  http://localhost:8000/extract-pdf
```

Using Python with requests:

```python
import requests

url = "http://localhost:8000/extract-pdf"
files = {"file": open("path/to/file.pdf", "rb")}

response = requests.post(url, files=files)
print(response.text)
```

### Response

```text
Extracted text content from the PDF...
```

## Development

1. Clone the repository
2. Install dependencies:
   ```bash
   make install
   ```
3. Setup pre-commit hooks:
   ```bash
   pre-commit install
   ```
4. Run tests:
   ```bash
   make test
   ```
5. Run the application locally:
   ```bash
   make run
   ```

## License

See the [LICENSE](LICENSE) file for details.
