# FastAPI EC2 Deployment Automation

Automated deployment scripts for deploying FastAPI applications on AWS EC2 with PostgreSQL, Nginx, and SSL.

## 📋 Prerequisites

- AWS EC2 instance (Ubuntu 22.04 or 24.04)
- Domain name pointed to your EC2 instance
- Your FastAPI application code with `main.py` and `requirements.txt`

## 🚀 Quick Start

### 1. Prepare Your EC2 Instance

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@your-ec2-ip

# Upload your application code to /home/ubuntu/cardlabsv3.0
# You can use scp, git clone, or rsync
```

### 2. Upload Deployment Scripts

```bash
# From your local machine, upload the scripts
scp -i your-key.pem deploy.sh deploy.config deploy_advanced.sh ubuntu@your-ec2-ip:~/
```

### 3. Configure Deployment Settings

```bash
# Edit the configuration file
nano deploy.config
```

Update these important values:
- `DOMAIN`: Your domain name
- `ADMIN_EMAIL`: Your email for Let's Encrypt
- `DB_PASSWORD`: A secure database password
- `APP_DIR`: Path to your application code

### 4. Run Deployment

**Option A: Simple Deployment**
```bash
chmod +x deploy.sh
./deploy.sh
```

**Option B: Advanced Deployment (with pre-checks and rollback)**
```bash
chmod +x deploy_advanced.sh
./deploy_advanced.sh
```

The advanced script includes:
- Pre-deployment validation checks
- Automatic backup of existing configuration
- Rollback on failure
- Post-deployment verification

## 📁 File Structure

```
/home/ubuntu/
├── cardlabsv3.0/           # Your FastAPI application
│   ├── main.py
│   ├── requirements.txt
│   ├── .env               # Created by script
│   └── venv/              # Created by script
├── deploy.sh              # Simple deployment script
├── deploy_advanced.sh     # Advanced deployment with checks
└── deploy.config          # Configuration file
```

## 🔧 Configuration File Options

```bash
# Application settings
APP_NAME="cardlabsv3.0"
APP_DIR="/home/ubuntu/cardlabsv3.0"

# Domain settings
DOMAIN="your-domain.com"
WWW_DOMAIN="www.your-domain.com"

# Database settings
DB_NAME="cardlabs"
DB_USER="postgres"
DB_PASSWORD="secure-password-here"

# Let's Encrypt settings
ADMIN_EMAIL="admin@your-domain.com"

# Gunicorn settings
WORKERS=4
WORKER_CLASS="uvicorn.workers.UvicornWorker"
```

## 🔄 Redeploying / Updating Your App

When you need to update your application code:

```bash
# Pull latest code
cd /home/ubuntu/cardlabsv3.0
git pull  # or upload new code

# Install any new dependencies
source venv/bin/activate
pip install -r requirements.txt

# Restart the service
sudo systemctl restart fastapi

# Check status
sudo systemctl status fastapi
```

Or use the automated redeploy script (see redeploy.sh).

## 🐛 Troubleshooting

### Check Service Status
```bash
sudo systemctl status fastapi
sudo systemctl status nginx
sudo systemctl status postgresql
```

### View Logs
```bash
# FastAPI application logs
sudo journalctl -u fastapi -f

# Nginx logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### Test Application Directly
```bash
cd /home/ubuntu/cardlabsv3.0
source venv/bin/activate
gunicorn -w 1 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000
```

### Database Issues
```bash
# Connect to PostgreSQL
sudo -u postgres psql

# Check databases
\l

# Connect to your database
\c cardlabs

# Check tables
\dt
```

### SSL Certificate Issues
```bash
# Test certificate renewal
sudo certbot renew --dry-run

# Force certificate renewal
sudo certbot renew --force-renewal
```

## 🛡️ Security Checklist

After deployment, consider these security improvements:

1. **Change default passwords**
   ```bash
   # Change PostgreSQL password
   sudo -u postgres psql
   ALTER USER postgres PASSWORD 'new-secure-password';
   ```

2. **Configure firewall**
   ```bash
   sudo ufw allow 22    # SSH
   sudo ufw allow 80    # HTTP
   sudo ufw allow 443   # HTTPS
   sudo ufw enable
   ```

3. **Update .env with secure values**
   ```bash
   nano /home/ubuntu/cardlabsv3.0/.env
   # Add SECRET_KEY, API_KEYS, etc.
   ```

4. **Regular updates**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

## 📊 Monitoring

### Check Resource Usage
```bash
# Memory usage
free -h

# Disk usage
df -h

# CPU usage
top
```

### Monitor Application
```bash
# Real-time logs
sudo journalctl -u fastapi -f

# Recent errors
sudo journalctl -u fastapi -p err -n 50
```

## 🔄 Backup & Recovery

Backups are automatically created in `/tmp/deployment_backup_*` when using the advanced script.

### Manual Backup
```bash
# Backup database
sudo -u postgres pg_dump cardlabs > backup_$(date +%Y%m%d).sql

# Backup application
tar -czf app_backup_$(date +%Y%m%d).tar.gz /home/ubuntu/cardlabsv3.0
```

### Restore from Backup
```bash
# Restore database
sudo -u postgres psql cardlabs < backup_20240101.sql
```

## 📝 Common Issues and Solutions

### Issue: FastAPI service won't start
**Solution:**
```bash
# Check for Python errors
sudo journalctl -u fastapi -n 100

# Verify virtual environment
cd /home/ubuntu/cardlabsv3.0
source venv/bin/activate
python main.py  # Run directly to see errors
```

### Issue: Database connection failed
**Solution:**
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Verify credentials in .env
cat /home/ubuntu/cardlabsv3.0/.env

# Test connection
sudo -u postgres psql -c "SELECT 1"
```

### Issue: SSL certificate not working
**Solution:**
```bash
# Check domain DNS
nslookup your-domain.com

# Verify nginx configuration
sudo nginx -t

# Check certbot logs
sudo journalctl -u certbot -n 50
```

## 🎯 Performance Tuning

### Adjust Gunicorn Workers
```bash
# Edit systemd service
sudo nano /etc/systemd/system/fastapi.service

# Change -w value (recommended: 2-4 x CPU cores)
ExecStart=... -w 8 ...

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart fastapi
```

### Database Connection Pooling
Add to your `.env`:
```
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=10
```

## 📚 Additional Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Gunicorn Documentation](https://docs.gunicorn.org/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## 🆘 Support

If you encounter issues:
1. Check the logs: `sudo journalctl -u fastapi -f`
2. Verify all services are running: `sudo systemctl status fastapi nginx postgresql`
3. Review the configuration: `nano deploy.config`
4. Test connectivity: `curl http://localhost:8000`
"# Bash-scripting" 
