#!/bin/bash

################################################################################
# One-Line Installer for FastAPI Deployment Scripts
# Usage: curl -sSL https://your-url/install.sh | bash
################################################################################

set -e

REPO_URL="https://github.com/yourusername/fastapi-deployment"  # Update this
INSTALL_DIR="$HOME/fastapi-deploy"

echo "======================================"
echo "  FastAPI Deployment Installer"
echo "======================================"
echo ""

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download deployment scripts
echo "Downloading deployment scripts..."

# If using GitHub or similar
if command -v git &> /dev/null; then
    git clone "$REPO_URL" . 2>/dev/null || echo "Using existing directory"
else
    # Alternative: download individual files
    # Update these URLs to match your setup
    echo "Git not found, downloading files individually..."
    
    cat > deploy.sh << 'EOFSCRIPT'
# Paste the deploy.sh content here
EOFSCRIPT

    cat > deploy.config << 'EOFCONFIG'
# Paste the deploy.config content here
EOFCONFIG

    cat > deploy_advanced.sh << 'EOFADVANCED'
# Paste the deploy_advanced.sh content here
EOFADVANCED

    cat > redeploy.sh << 'EOFREDEPLOY'
# Paste the redeploy.sh content here
EOFREDEPLOY
fi

# Make scripts executable
chmod +x deploy.sh deploy_advanced.sh redeploy.sh 2>/dev/null || true

echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit configuration: nano $INSTALL_DIR/deploy.config"
echo "2. Update your app details, domain, and email"
echo "3. Run deployment: cd $INSTALL_DIR && ./deploy_advanced.sh"
echo ""
echo "======================================"
