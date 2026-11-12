#!/bin/bash

# Deploy SIGECA API service
ECR_REGISTRY="823413233235.dkr.ecr.us-east-1.amazonaws.com"
COMPOSE_PATH="/home/ssm-user/git_code/sigeca-deploy/siglofa/app"
ENV_FILE="$COMPOSE_PATH/settings.dev.env"
DOCKER_COMPOSE_FILE="$COMPOSE_PATH/docker-compose.dev.yml"
SERVICE="referencedata"
SERVICE_IMAGE="sigeca-openlmis-referencedata"
NEW_VERSION=$1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEPLOY] $1"
}

update_image_version() {
    local service=$1
    local new_version=$2
    local key="OL_${service}_VERSION"

    log "Updating ${key} to version ${new_version}"

    for file in "$ENV_FILE" "$COMPOSE_PATH/.env"; do
        [ -f "$file" ] || continue
        if grep -q "^${key}=" "$file"; then
            sed -i "s/^${key}=.*/${key}=${new_version}/" "$file"
            log "Set ${key} in $file"
        else
            log "WARNING: ${key} not found in $file"
        fi
    done

    log "Updated ${service} version to ${new_version}"
}

verify_compose_image() {
    local new_version=$1

    # Compose resolves ${VAR} from .env, so this confirms the restart will use the new tag
    if (cd "$COMPOSE_PATH" && docker-compose -f docker-compose.dev.yml config | grep -qF "$new_version"); then
        log "Compose resolves image to version ${new_version}"
        return 0
    fi

    log "ERROR: Compose does not resolve image to ${new_version}"
    (cd "$COMPOSE_PATH" && docker-compose -f docker-compose.dev.yml config | grep "image:")
    return 1
}

login_to_ecr() {
    log "Logging in to AWS ECR..."
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY
    log "ECR login successful"
}

restart_service() {
    local service=$1

    log "Restarting service: $service"
    cd $COMPOSE_PATH

    # Login to ECR
    login_to_ecr

    # Stop and remove the specific service
    docker-compose -f docker-compose.dev.yml stop $service || true
    docker-compose -f docker-compose.dev.yml rm -f $service || true

    # Start the service with new image
    docker-compose -f docker-compose.dev.yml up -d $service

    log "Service $service restarted successfully"
}

health_check() {
    local service=$1
    local max_attempts=30
    local attempt=1

    log "Performing health check for $service..."

    while [ $attempt -le $max_attempts ]; do
        # Check if container is running
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "${service}.*Up"; then
            log "SUCCESS: $service is healthy (container running)"
            return 0
        fi

        log "WAITING: Health check for $service (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done

    log "FAILED: Health check failed for $service after $max_attempts attempts"

    # Show container logs for debugging
    log "Container logs for $service:"
    docker logs --tail 20 "${service}" 2>/dev/null || log "Could not retrieve logs for $service"

    return 1
}

verify_image_exists() {
    local service=$1
    local version=$2
    local image="${ECR_REGISTRY}/${service}:${version}"

    log "Verifying image exists: $image"

    # Login to ECR first
    login_to_ecr

    # Try to pull the image to verify it exists
    if docker pull --platform linux/x86_64 "$image"; then
        log "Image verified: $image"
        return 0
    else
        log "ERROR: Image not found: $image"
        return 1
    fi
}

cleanup_old_images() {
    log "Cleaning up old/unused Docker images..."
    docker system prune -f --filter "until=72h" || true
    log "Cleanup completed"
}

rollback_service() {
    local service=$1
    local rollback_version=$2

    log "ROLLBACK: Rolling back $service to version $rollback_version"

    if verify_image_exists "$service" "$rollback_version"; then
        update_image_version "$service" "$rollback_version"
        restart_service "$service"
        if health_check "$service"; then
            log "ROLLBACK SUCCESS: $service rolled back to $rollback_version"
            return 0
        else
            log "ROLLBACK FAILED: Health check failed for $service after rollback"
            return 1
        fi
    else
        log "ROLLBACK FAILED: Rollback image not found for $service:$rollback_version"
        return 1
    fi
}

show_deployment_status() {
    log "=== Deployment Status ==="
    log "Current running containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "(sigeca|reference|nginx)" || log "No SIGECA containers found"
    log "=========================="
}

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 20250905-1"
    exit 1
fi

log "=== Starting deployment of $SERVICE_IMAGE version $NEW_VERSION ==="

# Verify the new image exists in ECR
if ! verify_image_exists "$SERVICE_IMAGE" "$NEW_VERSION"; then
    log "DEPLOYMENT FAILED: Image verification failed"
    exit 1
fi

# Update version and restart service
update_image_version "SIGECA_REFERENCEDATA" "$NEW_VERSION"
if ! verify_compose_image "$NEW_VERSION"; then
    log "DEPLOYMENT FAILED: Compose config does not use version $NEW_VERSION (check the OL_*_VERSION key in $COMPOSE_PATH/.env)"
    exit 1
fi
restart_service "$SERVICE"

# Health check
if health_check "$SERVICE"; then
    log "SUCCESS: Deployment of $SERVICE_IMAGE version $NEW_VERSION completed successfully"
    show_deployment_status
    cleanup_old_images
    exit 0
else
    log "DEPLOYMENT FAILED: Health check failed for $SERVICE"
    log "Consider rolling back to previous version"
    exit 1
fi