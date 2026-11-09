#!/bin/bash

# Deploy SIGECA API service
source /home/ssm-user/deployment-scripts/deploy-common.sh

SERVICE="referencedata"
SERVICE_IMAGE="referencedata"
NEW_VERSION=$1

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
update_image_version "SIGECA_OPENLMIS_REFERENCEDATA" "$NEW_VERSION"
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