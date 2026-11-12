#!/bin/bash
set -e

# Common deployment functions for SIGECA services
ECR_REGISTRY="823413233235.dkr.ecr.us-east-1.amazonaws.com"
COMPOSE_PATH="/home/ssm-user/git_code/sigeca-deploy/siglofa/app"
ENV_FILE="$COMPOSE_PATH/settings.dev.env"
DOCKER_COMPOSE_FILE="$COMPOSE_PATH/docker-compose.dev.yml"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEPLOY] $1"
}

update_image_version() {
    local service=$1
    local new_version=$2
    
    log "Updating ${service} to version ${new_version}"
    
    # Update environment file with new version
    sed -i "s/OL_${service}_VERSION=.*/OL_${service}_VERSION=${new_version}/" $ENV_FILE
    
    # Also update .env file if it exists
    if [ -f "$COMPOSE_PATH/.env" ]; then
        sed -i "s/OL_${service}_VERSION=.*/OL_${service}_VERSION=${new_version}/" $COMPOSE_PATH/.env
    fi
    
    log "Updated ${service} version to ${new_version}"
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