group "default" {
  targets = ["arm64", "amd64"]
}

variable "DOCKER_IMAGE_NAME" {
  default = "pdf-processor"
}

target "base" {
  context = "."
  dockerfile = "docker/Dockerfile"
  output = ["type=docker"]
}

target "arm64" {
  inherits = ["base"]
  platforms = ["linux/arm64"]
  tags = ["${DOCKER_IMAGE_NAME}:arm64"]
}

target "amd64" {
  inherits = ["base"]
  platforms = ["linux/amd64"]
  tags = ["${DOCKER_IMAGE_NAME}:amd64"]
}
