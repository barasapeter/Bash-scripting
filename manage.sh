#!/bin/bash

################################################################################
# FastAPI Management Script
# Common operations for managing your deployed FastAPI application
################################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration
CONFIG_FILE="./deploy.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    APP_DIR="/home/ubuntu/cardlabsv3.0"
fi

show_menu() {
    clear
    echo "======================================"
    echo "  FastAPI Management Menu"
    echo "======================================"
    echo ""
    echo "1.  View service status"
    echo "2.  Start service"
    echo "3.  Stop service"
    echo "4.  Restart service"
    echo "5.  View live logs"
    echo "6.  View recent errors"
    echo "7.  Test application"
    echo "8.  View configuration"
    echo "9.  Edit .env file"
    echo "10. Database console"
    echo "11. Backup database"
    echo "12. System resources"
    echo "13. SSL certificate info"
    echo "14. Renew SSL certificate"
    echo "15. Nginx status"
    echo "16. Clear logs"
    echo "0.  Exit"
    echo ""
    echo "======================================"
}

view_status() {
    echo ""
    log_info "Service Status:"
    echo "======================================"
    sudo systemctl status fastapi --no-pager | head -15
    echo ""
    sudo systemctl status nginx --no-pager | head -10
    echo ""
    sudo systemctl status postgresql --no-pager | head -10
    echo "======================================"
    read -p "Press enter to continue..."
}

start_service() {
    log_info "Starting FastAPI service..."
    sudo systemctl start fastapi
    sleep 2
    if sudo systemctl is-active --quiet fastapi; then
        log_info "✓ Service started successfully"
    else
        log_error "✗ Failed to start service"
    fi
    read -p "Press enter to continue..."
}

stop_service() {
    log_warn "Stopping FastAPI service..."
    sudo systemctl stop fastapi
    log_info "✓ Service stopped"
    read -p "Press enter to continue..."
}

restart_service() {
    log_info "Restarting FastAPI service..."
    sudo systemctl restart fastapi
    sleep 2
    if sudo systemctl is-active --quiet fastapi; then
        log_info "✓ Service restarted successfully"
    else
        log_error "✗ Failed to restart service"
    fi
    read -p "Press enter to continue..."
}

view_logs() {
    log_info "Showing live logs (Ctrl+C to exit)..."
    sleep 1
    sudo journalctl -u fastapi -f
}

view_errors() {
    log_info "Recent errors:"
    echo "======================================"
    sudo journalctl -u fastapi -p err -n 50 --no-pager
    echo "======================================"
    read -p "Press enter to continue..."
}

test_app() {
    log_info "Testing application..."
    echo "======================================"
    
    # Test local endpoint
    echo "Testing http://localhost:8000..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 || echo "000")
    
    if [[ "$HTTP_CODE" =~ ^(200|307|404)$ ]]; then
        log_info "✓ Application responding (HTTP $HTTP_CODE)"
    else
        log_error "✗ Application not responding properly (HTTP $HTTP_CODE)"
    fi
    
    # Test external domain if configured
    if [ ! -z "${DOMAIN:-}" ]; then
        echo ""
        echo "Testing https://$DOMAIN..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN || echo "000")
        
        if [[ "$HTTP_CODE" =~ ^(200|307|404)$ ]]; then
            log_info "✓ Domain responding (HTTP $HTTP_CODE)"
        else
            log_error "✗ Domain not responding properly (HTTP $HTTP_CODE)"
        fi
    fi
    
    echo "======================================"
    read -p "Press enter to continue..."
}

view_config() {
    echo ""
    log_info "Current Configuration:"
    echo "======================================"
    cat deploy.config 2>/dev/null || echo "deploy.config not found"
    echo "======================================"
    read -p "Press enter to continue..."
}

edit_env() {
    if [ -f "$APP_DIR/.env" ]; then
        nano "$APP_DIR/.env"
        log_warn "Remember to restart the service for changes to take effect"
        read -p "Restart now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restart_service
        fi
    else
        log_error ".env file not found at $APP_DIR/.env"
        read -p "Press enter to continue..."
    fi
}

database_console() {
    log_info "Opening PostgreSQL console..."
    log_info "Use \\q to exit, \\l to list databases, \\dt to list tables"
    sleep 1
    sudo -u postgres psql
}

backup_database() {
    BACKUP_FILE="$HOME/db_backup_$(date +%Y%m%d_%H%M%S).sql"
    DB_NAME="${DB_NAME:-cardlabs}"
    
    log_info "Backing up database to $BACKUP_FILE..."
    sudo -u postgres pg_dump "$DB_NAME" > "$BACKUP_FILE"
    
    if [ -f "$BACKUP_FILE" ]; then
        log_info "✓ Database backed up successfully"
        log_info "File: $BACKUP_FILE"
        log_info "Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    else
        log_error "✗ Backup failed"
    fi
    read -p "Press enter to continue..."
}

system_resources() {
    log_info "System Resources:"
    echo "======================================"
    echo ""
    echo "Memory Usage:"
    free -h
    echo ""
    echo "Disk Usage:"
    df -h | grep -E '^Filesystem|/$'
    echo ""
    echo "CPU Load:"
    uptime
    echo ""
    echo "Top Processes:"
    ps aux --sort=-%mem | head -6
    echo "======================================"
    read -p "Press enter to continue..."
}

ssl_info() {
    DOMAIN="${DOMAIN:-cardlabs-sandbox.duckdns.org}"
    
    log_info "SSL Certificate Information:"
    echo "======================================"
    
    if sudo certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
        sudo certbot certificates | grep -A 5 "$DOMAIN"
    else
        log_warn "No certificate found for $DOMAIN"
    fi
    
    echo ""
    log_info "Auto-renewal timer status:"
    sudo systemctl status certbot.timer --no-pager | head -5
    
    echo "======================================"
    read -p "Press enter to continue..."
}

renew_ssl() {
    log_info "Testing SSL certificate renewal..."
    sudo certbot renew --dry-run
    
    read -p "Force renewal now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo certbot renew --force-renewal
        log_info "✓ Certificate renewed"
    fi
    read -p "Press enter to continue..."
}

nginx_status() {
    log_info "Nginx Status:"
    echo "======================================"
    sudo systemctl status nginx --no-pager | head -15
    echo ""
    log_info "Testing Nginx configuration:"
    sudo nginx -t
    echo "======================================"
    read -p "Press enter to continue..."
}

clear_logs() {
    read -p "This will clear systemd logs for fastapi. Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1s -u fastapi
        log_info "✓ Logs cleared"
    else
        log_info "Cancelled"
    fi
    read -p "Press enter to continue..."
}

# Main loop
while true; do
    show_menu
    read -p "Select an option: " choice
    
    case $choice in
        1) view_status ;;
        2) start_service ;;
        3) stop_service ;;
        4) restart_service ;;
        5) view_logs ;;
        6) view_errors ;;
        7) test_app ;;
        8) view_config ;;
        9) edit_env ;;
        10) database_console ;;
        11) backup_database ;;
        12) system_resources ;;
        13) ssl_info ;;
        14) renew_ssl ;;
        15) nginx_status ;;
        16) clear_logs ;;
        0) 
            echo "Goodbye!"
            exit 0
            ;;
        *)
            log_error "Invalid option"
            sleep 1
            ;;
    esac
done
