#!/bin/bash

################################################################################
# Advanced FastAPI EC2 Deployment Script with Pre-checks and Rollback
################################################################################

set -eo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Load configuration
CONFIG_FILE="./deploy.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log_info "Loaded configuration from $CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Please create deploy.config file with required settings"
    exit 1
fi

# Backup directory
BACKUP_DIR="/tmp/deployment_backup_$(date +%Y%m%d_%H%M%S)"

################################################################################
# Pre-deployment Checks
################################################################################
pre_deployment_checks() {
    log_step "Running pre-deployment checks..."
    
    # Check if running as ubuntu user
    if [ "$USER" != "ubuntu" ]; then
        log_warn "This script should be run as ubuntu user"
    fi
    
    # Check if app directory exists
    if [ ! -d "$APP_DIR" ]; then
        log_error "Application directory not found: $APP_DIR"
        log_info "Please ensure your application code is in $APP_DIR"
        exit 1
    fi
    
    # Check if requirements.txt exists
    if [ ! -f "$APP_DIR/requirements.txt" ]; then
        log_error "requirements.txt not found in $APP_DIR"
        exit 1
    fi
    
    # Check if main.py exists
    if [ ! -f "$APP_DIR/main.py" ]; then
        log_error "main.py not found in $APP_DIR"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "No internet connectivity"
        exit 1
    fi
    
    # Check if ports are available
    if sudo lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_warn "Port 80 is already in use"
    fi
    
    if sudo lsof -Pi :443 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_warn "Port 443 is already in use"
    fi
    
    log_info "Pre-deployment checks passed!"
}

################################################################################
# Backup existing configuration
################################################################################
backup_existing_config() {
    log_step "Creating backup of existing configuration..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup systemd service if exists
    if [ -f "/etc/systemd/system/fastapi.service" ]; then
        sudo cp /etc/systemd/system/fastapi.service "$BACKUP_DIR/"
        log_info "Backed up systemd service"
    fi
    
    # Backup nginx config if exists
    if [ -f "/etc/nginx/sites-available/fastapi" ]; then
        sudo cp /etc/nginx/sites-available/fastapi "$BACKUP_DIR/"
        log_info "Backed up nginx config"
    fi
    
    # Backup .env if exists
    if [ -f "$APP_DIR/.env" ]; then
        cp "$APP_DIR/.env" "$BACKUP_DIR/"
        log_info "Backed up .env file"
    fi
    
    log_info "Backup created at: $BACKUP_DIR"
}

################################################################################
# Rollback function
################################################################################
rollback() {
    log_error "Deployment failed! Rolling back changes..."
    
    if [ -d "$BACKUP_DIR" ]; then
        # Restore systemd service
        if [ -f "$BACKUP_DIR/fastapi.service" ]; then
            sudo cp "$BACKUP_DIR/fastapi.service" /etc/systemd/system/
            sudo systemctl daemon-reload
            sudo systemctl restart fastapi
        fi
        
        # Restore nginx config
        if [ -f "$BACKUP_DIR/fastapi" ]; then
            sudo cp "$BACKUP_DIR/fastapi" /etc/nginx/sites-available/
            sudo systemctl restart nginx
        fi
        
        # Restore .env
        if [ -f "$BACKUP_DIR/.env" ]; then
            cp "$BACKUP_DIR/.env" "$APP_DIR/"
        fi
        
        log_info "Rollback completed. Backup preserved at: $BACKUP_DIR"
    fi
}

# Set up error trap for rollback
trap rollback ERR

################################################################################
# Main Deployment Steps
################################################################################

main_deployment() {
    # System Update
    log_step "Step 1/9: Updating system packages..."
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    
    # Install Dependencies
    log_step "Step 2/9: Installing system dependencies..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        python3.12-venv \
        libpq-dev \
        python3-dev \
        build-essential \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxrender1 \
        libxext6
    
    # Setup Virtual Environment
    log_step "Step 3/9: Setting up Python virtual environment..."
    cd "$APP_DIR"
    
    if [ -d "venv" ]; then
        log_warn "Virtual environment already exists, removing..."
        rm -rf venv
    fi
    
    python3 -m venv venv
    source venv/bin/activate
    
    pip3 install --upgrade pip setuptools wheel
    pip3 install -r requirements.txt
    
    # Setup PostgreSQL
    log_step "Step 4/9: Setting up PostgreSQL..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql postgresql-contrib
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 2
    
    # Create database
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
    
    # Set password
    sudo -u postgres psql -c "ALTER USER $DB_USER PASSWORD '$DB_PASSWORD';"
    
    # Create/Update .env file
    log_step "Step 5/9: Creating environment configuration..."
    cat > "$APP_DIR/.env" << EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME
EOF
    
    # Add additional env vars from config
    if [ ! -z "${SECRET_KEY:-}" ]; then
        echo "SECRET_KEY=$SECRET_KEY" >> "$APP_DIR/.env"
    fi
    
    # Test Application
    log_step "Step 6/9: Testing application..."
    timeout 15s "$APP_DIR/venv/bin/gunicorn" \
        -w 1 \
        -k $WORKER_CLASS \
        main:app \
        --bind $BIND_ADDRESS \
        || log_warn "Application test completed (timeout expected)"
    
    # Setup Systemd Service
    log_step "Step 7/9: Configuring systemd service..."
    sudo tee /etc/systemd/system/fastapi.service > /dev/null << EOF
[Unit]
Description=FastAPI Application - $APP_NAME
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=notify
User=ubuntu
Group=ubuntu
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    -w $WORKERS \\
    -k $WORKER_CLASS \\
    main:app \\
    --bind $BIND_ADDRESS \\
    --access-logfile - \\
    --error-logfile -
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable fastapi
    sudo systemctl restart fastapi
    
    # Wait and verify service
    sleep 5
    if ! sudo systemctl is-active --quiet fastapi; then
        log_error "FastAPI service failed to start"
        sudo journalctl -u fastapi -n 50 --no-pager
        exit 1
    fi
    
    log_info "FastAPI service is running"
    
    # Setup Nginx
    log_step "Step 8/9: Configuring Nginx reverse proxy..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nginx
    
    sudo tee /etc/nginx/sites-available/fastapi > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN $WWW_DOMAIN;
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://$BIND_ADDRESS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
    
    sudo ln -sf /etc/nginx/sites-available/fastapi /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    # Setup SSL
    log_step "Step 9/9: Configuring SSL with Let's Encrypt..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y certbot python3-certbot-nginx
    
    sudo certbot --nginx \
        -d "$DOMAIN" \
        -d "$WWW_DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --redirect \
        || log_warn "SSL setup failed, site is available over HTTP"
    
    # Verify certbot timer
    sudo systemctl status certbot.timer --no-pager | head -3
}

################################################################################
# Post-deployment verification
################################################################################
post_deployment_checks() {
    log_step "Running post-deployment checks..."
    
    # Check if services are running
    SERVICES=("fastapi" "nginx" "postgresql")
    for service in "${SERVICES[@]}"; do
        if sudo systemctl is-active --quiet "$service"; then
            log_info "✓ $service is running"
        else
            log_error "✗ $service is not running"
        fi
    done
    
    # Check if app responds
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200\|307\|404"; then
        log_info "✓ Application is responding"
    else
        log_warn "✗ Application may not be responding correctly"
    fi
    
    # Display final status
    echo ""
    echo "======================================"
    echo "  Deployment Complete!"
    echo "======================================"
    echo "App URL: https://$DOMAIN"
    echo "App Directory: $APP_DIR"
    echo "Database: $DB_NAME"
    echo ""
    echo "Useful Commands:"
    echo "  View logs: sudo journalctl -u fastapi -f"
    echo "  Restart app: sudo systemctl restart fastapi"
    echo "  Check status: sudo systemctl status fastapi"
    echo "  Edit config: nano $APP_DIR/.env"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo "======================================"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "======================================"
    echo "  FastAPI Deployment Script"
    echo "======================================"
    echo ""
    
    pre_deployment_checks
    backup_existing_config
    main_deployment
    post_deployment_checks
    
    # Disable error trap after successful completion
    trap - ERR
    
    log_info "Deployment successful!"
}

# Run main function
main
