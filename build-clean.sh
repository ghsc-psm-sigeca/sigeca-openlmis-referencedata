#!/bin/sh

# Step 1. Pre-build Cleanup

# stop unused Gradle daemons to free up resources
./gradlew --stop

# Remove node_modules, build and .gradle folder to ensure a clean build
rm -rf node_modules build .gradle

# Stop containers
docker ps -q | xargs -r docker stop

# Step 2. Build the project

DOCKER_IMAGE="amazoncorretto:8u342-alpine3.16"
DOCKER_CMD="apk add npm freetype ttf-dejavu fontconfig && ./gradlew clean build -x checkstyleMain -x checkstyleTest -x pmdMain -x pmdTest -x jacocoTestCoverageVerification --no-build-cache"

## Run the Docker container with the specified image and command
## Mount the current directory to `/app` inside the container, set the working directory to `/app`,
## and use the host network. The `--platform=linux/amd64` ensures compatibility with the target platform.
#docker run --rm --platform=linux/amd64 -v "$(pwd)":/app -w /app --network=host $DOCKER_IMAGE sh -c "$DOCKER_CMD"
docker-compose -f docker-compose.builder.yml run --rm builder ./gradlew build

# Step 3. Post-build cleanup
./gradlew --stop