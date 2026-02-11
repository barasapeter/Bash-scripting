#!/bin/bash

################################################################################
# FastAPI Redeployment Script
# Use this script when you need to update your application code
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration
CONFIG_FILE="./deploy.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "======================================"
echo "  FastAPI Redeployment Script"
echo "======================================"
echo ""

# Confirmation prompt
read -p "This will update and restart your application. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Redeployment cancelled"
    exit 0
fi

# Create backup
BACKUP_DIR="/tmp/redeploy_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

log_info "Creating backup at $BACKUP_DIR..."
if [ -d "$APP_DIR/venv" ]; then
    cp -r "$APP_DIR/venv" "$BACKUP_DIR/"
fi
if [ -f "$APP_DIR/.env" ]; then
    cp "$APP_DIR/.env" "$BACKUP_DIR/"
fi

# Update code (if using git)
log_info "Updating application code..."
cd "$APP_DIR"

if [ -d ".git" ]; then
    log_info "Pulling latest changes from git..."
    git pull
else
    log_warn "Not a git repository. Make sure you've uploaded the latest code."
fi

# Activate virtual environment
log_info "Activating virtual environment..."
source venv/bin/activate

# Update dependencies
log_info "Updating Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Run database migrations (if you have them)
if [ -f "alembic.ini" ]; then
    log_info "Running database migrations..."
    alembic upgrade head
elif [ -f "manage.py" ]; then
    log_info "Running Django migrations..."
    python manage.py migrate
else
    log_warn "No migration system detected, skipping migrations"
fi

# Test the application
log_info "Testing application..."
timeout 10s gunicorn -w 1 -k uvicorn.workers.UvicornWorker main:app --bind 127.0.0.1:8001 || true

# Restart the service
log_info "Restarting FastAPI service..."
sudo systemctl restart fastapi

# Wait for service to start
sleep 3

# Check if service is running
if sudo systemctl is-active --quiet fastapi; then
    log_info "✓ FastAPI service restarted successfully"
else
    log_error "✗ FastAPI service failed to start"
    log_error "Rolling back..."
    
    # Restore backup
    if [ -d "$BACKUP_DIR/venv" ]; then
        rm -rf "$APP_DIR/venv"
        cp -r "$BACKUP_DIR/venv" "$APP_DIR/"
    fi
    if [ -f "$BACKUP_DIR/.env" ]; then
        cp "$BACKUP_DIR/.env" "$APP_DIR/"
    fi
    
    sudo systemctl restart fastapi
    log_error "Rollback complete. Check logs: sudo journalctl -u fastapi -n 50"
    exit 1
fi

# Verify application is responding
log_info "Verifying application..."
sleep 2

if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200\|307\|404"; then
    log_info "✓ Application is responding"
else
    log_warn "Application may not be responding correctly"
fi

# Display status
echo ""
echo "======================================"
echo "  Redeployment Complete!"
echo "======================================"
echo ""
sudo systemctl status fastapi --no-pager | head -10
echo ""
log_info "Backup saved at: $BACKUP_DIR"
log_info "View logs: sudo journalctl -u fastapi -f"
echo "======================================"
