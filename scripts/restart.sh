#!/bin/bash
# Usage: ./restart <service-name>
# Example: ./restart api

if [ -z "$1" ]; then
  echo "Usage: $0 <service-name>"
  exit 1
fi


# Map common aliases to actual service names
SERVICE="logzai-$1"

# Stop the service
if ! docker compose stop $SERVICE; then
  echo "Failed to stop $SERVICE or service not running."
fi

# Remove the service's container
if ! docker compose rm -f $SERVICE; then
  echo "Failed to remove container for $SERVICE."
fi

# Start the service again
docker compose up -d $SERVICE

if [ $? -eq 0 ]; then
  echo "$SERVICE restarted successfully."
else
  echo "Failed to restart $SERVICE."
fi
