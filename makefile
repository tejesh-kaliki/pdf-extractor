# Environment variables
DOCKER_IMAGE_NAME ?= pdf-processor
PLATFORMS ?= $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')

.PHONY: all build slim-images login-ecr push-ecr create-manifest

all: build slim-images login-ecr push-ecr create-manifest

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
