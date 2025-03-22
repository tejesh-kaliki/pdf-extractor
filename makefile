# Environment variables
DOCKER_IMAGE_NAME ?= pdf-processor
PLATFORMS ?= $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')

.PHONY: all build slim-images login-ecr push-ecr create-manifest validate-creds deploy install test help docker-compose-build docker-compose-up docker-compose-down run run-slim

# Help target
help:
	@echo "Available targets:"
	@echo "  help        - Show this help message"
	@echo "  install     - Install dependencies using uv"
	@echo "  test        - Run tests using pytest"
	@echo "  run         - Run application"
	@echo "  build       - Build Docker image for current architecture"
	@echo "  slim-images - Apply docker-slim to reduce image size"
	@echo "  run-slim    - Run the slimmed Docker image"
	@echo "  deploy      - Full deployment workflow (build, slim, login, push, manifest)"
	@echo ""
	@echo "Docker Compose targets:"
	@echo "  docker-compose-build - Build services defined in docker-compose.yml"
	@echo "  docker-compose-up    - Start services defined in docker-compose.yml"
	@echo "  docker-compose-down  - Stop services defined in docker-compose.yml"
	@echo ""
	@echo "AWS ECR deployment targets:"
	@echo "  login-ecr        - Login to Amazon ECR"
	@echo "  push-ecr         - Tag and push images to ECR"
	@echo "  create-manifest  - Create and push manifest for multi-platform support"
	@echo "  validate-creds   - Validate AWS credentials are properly set"
	@echo ""
	@echo "Environment variables:"
	@echo "  DOCKER_IMAGE_NAME - Docker image name (default: pdf-processor)"
	@echo "  AWS_ACCOUNT_ID    - AWS Account ID (required for ECR operations)"
	@echo "  AWS_REGION        - AWS Region (required for ECR operations)"
	@echo "  PLATFORMS         - Target platform(s) for build (default: current architecture)"

install:
	@echo "Installing dependencies..."
	uv sync --frozen --group test

test:
	@echo "Running tests..."
	uv run pytest

run:
	@echo "Running application..."
	uv run uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

deploy: build slim-images login-ecr push-ecr create-manifest

# Build image based on the current architecture
build:
	@echo "Building image for current architecture..."
	docker buildx bake -f docker/docker-bake.hcl $(PLATFORMS)

# Apply docker-slim to reduce image size
slim-images:
	@for platform in $(PLATFORMS); do \
		arch=$$(echo $$platform | sed 's/linux\///'); \
		echo "Applying docker-slim to $$arch image..."; \
		slim build --target $(DOCKER_IMAGE_NAME):$$arch \
			--tag $(DOCKER_IMAGE_NAME):$$arch-slim \
			--expose 8000 --http-probe-cmd GET:/docs \
			--include-path /app; \
	done

# Run the slimmed Docker image
run-slim:
	@echo "Running slimmed docker image..."
	@docker run \
		--rm \
		-p 8000:8000 \
		--health-interval=30s \
		--health-retries=2 \
		--health-timeout=5s \
		--health-start-period=10s \
		--health-cmd="curl -f http://localhost:8000/health || exit 1" \
		$(DOCKER_IMAGE_NAME):$(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')-slim

docker-compose-build:
	docker-compose -f docker/docker-compose.yml build

docker-compose-up:
	docker-compose -f docker/docker-compose.yml up -d

docker-compose-down:
	docker-compose -f docker/docker-compose.yml down

AWS_ACCOUNT_ID ?= none
AWS_REGION ?= none

ECR_BASE_URI = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

# Validate AWS credentials
validate-creds:
	@if [ "$(AWS_ACCOUNT_ID)" = "none" ]; then \
		echo "Error: AWS_ACCOUNT_ID is not set"; \
		exit 1; \
	fi
	@if [ "$(AWS_REGION)" = "none" ]; then \
		echo "Error: AWS_REGION is not set"; \
		exit 1; \
	fi
	@echo "AWS credentials validated."

# Login to Amazon ECR
login-ecr: validate-creds
	@echo "Logging in to Amazon ECR..."
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin "$(ECR_BASE_URI)"

# Tag and push images to ECR
push-ecr: validate-creds
	@echo "Tagging and pushing images to ECR..."
	docker tag $(DOCKER_IMAGE_NAME):arm64-slim $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):arm64-slim
	docker tag $(DOCKER_IMAGE_NAME):amd64-slim $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):amd64-slim
	docker push $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):arm64-slim
	docker push $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):amd64-slim

# Create and push manifest for multi-platform support
create-manifest: validate-creds
	@echo "Creating and pushing manifest..."
	docker manifest create -a $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):latest \
		$(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):arm64-slim \
		$(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):amd64-slim
	docker manifest push $(ECR_BASE_URI)/$(DOCKER_IMAGE_NAME):latest
