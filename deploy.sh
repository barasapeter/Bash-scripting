#!/bin/bash

################################################################################
# FastAPI EC2 Deployment Automation Script
# This script automates the entire deployment process for a FastAPI application
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables (customize these)
APP_NAME="cardlabsv3.0"
APP_DIR="/home/ubuntu/$APP_NAME"
DOMAIN="cardlabs-sandbox.duckdns.org"
DB_NAME="cardlabs"
DB_USER="postgres"
DB_PASSWORD="1988"  # Consider using a more secure password in production
ADMIN_EMAIL="your-email@example.com"  # For Let's Encrypt

################################################################################
# Step 1: System Update
################################################################################
log_info "Updating system packages..."
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

################################################################################
# Step 2: Install Python and Dependencies
################################################################################
log_info "Installing Python venv..."
sudo apt install -y python3.12-venv

log_info "Installing PostgreSQL development libraries..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y libpq-dev python3-dev build-essential

log_info "Installing OpenCV dependencies..."
sudo apt install -y libgl1 libglib2.0-0 libsm6 libxrender1 libxext6

################################################################################
# Step 3: Setup Virtual Environment
################################################################################
log_info "Creating virtual environment..."
cd "$APP_DIR"
python3 -m venv venv

log_info "Activating virtual environment..."
source venv/bin/activate

log_info "Installing Python requirements..."
pip3 install --upgrade pip
pip3 install -r requirements.txt

################################################################################
# Step 4: Setup PostgreSQL
################################################################################
log_info "Installing PostgreSQL..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql postgresql-contrib

log_info "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

log_info "Configuring PostgreSQL database..."
# Create database
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || log_warn "Database $DB_NAME already exists"

# Set postgres user password
sudo -u postgres psql -c "ALTER USER $DB_USER PASSWORD '$DB_PASSWORD';"

log_info "Database setup complete"

################################################################################
# Step 5: Create .env file (if it doesn't exist)
################################################################################
if [ ! -f "$APP_DIR/.env" ]; then
    log_info "Creating .env file..."
    cat > "$APP_DIR/.env" << EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME
# Add other environment variables here
EOF
else
    log_warn ".env file already exists, skipping creation"
fi

################################################################################
# Step 6: Test Gunicorn
################################################################################
log_info "Testing Gunicorn configuration..."
timeout 10s "$APP_DIR/venv/bin/gunicorn" -w 1 -k uvicorn.workers.UvicornWorker main:app --bind 127.0.0.1:8000 || log_warn "Gunicorn test completed"

################################################################################
# Step 7: Setup Systemd Service
################################################################################
log_info "Creating systemd service..."
sudo tee /etc/systemd/system/fastapi.service > /dev/null << EOF
[Unit]
Description=FastAPI app
After=network.target

[Service]
User=ubuntu
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app --bind 127.0.0.1:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

log_info "Starting and enabling FastAPI service..."
sudo systemctl daemon-reload
sudo systemctl enable fastapi
sudo systemctl restart fastapi

# Wait for service to start
sleep 3

# Check service status
if sudo systemctl is-active --quiet fastapi; then
    log_info "FastAPI service is running successfully"
else
    log_error "FastAPI service failed to start"
    sudo systemctl status fastapi
    exit 1
fi

################################################################################
# Step 8: Setup Nginx
################################################################################
log_info "Installing Nginx..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y nginx

log_info "Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/fastapi > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

log_info "Enabling Nginx site..."
sudo ln -sf /etc/nginx/sites-available/fastapi /etc/nginx/sites-enabled/

log_info "Testing Nginx configuration..."
sudo nginx -t

log_info "Restarting Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

################################################################################
# Step 9: Setup SSL with Let's Encrypt
################################################################################
log_info "Installing Certbot..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y certbot python3-certbot-nginx

log_info "Obtaining SSL certificate..."
# Use non-interactive mode with automatic agreement to ToS
sudo certbot --nginx \
    -d "$DOMAIN" \
    -d "www.$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$ADMIN_EMAIL" \
    --redirect

log_info "Verifying certbot auto-renewal timer..."
sudo systemctl status certbot.timer --no-pager

################################################################################
# Final Steps
################################################################################
log_info "Deployment complete!"
echo ""
echo "======================================"
echo "Deployment Summary"
echo "======================================"
echo "App Directory: $APP_DIR"
echo "Domain: https://$DOMAIN"
echo "Database: $DB_NAME"
echo ""
echo "Service Status:"
sudo systemctl status fastapi --no-pager | grep Active
sudo systemctl status nginx --no-pager | grep Active
sudo systemctl status postgresql --no-pager | grep Active
echo ""
echo "Next Steps:"
echo "1. Visit https://$DOMAIN to verify deployment"
echo "2. Check logs: sudo journalctl -u fastapi -f"
echo "3. Update .env file if needed: nano $APP_DIR/.env"
echo "======================================"
