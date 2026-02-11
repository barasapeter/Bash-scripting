# FastAPI Deployment - Quick Reference Cheat Sheet

## 🚀 Initial Deployment

```bash
# 1. Upload your app code to /home/ubuntu/cardlabsv3.0
# 2. Upload deployment scripts
# 3. Configure
nano deploy.config

# 4. Deploy
chmod +x deploy_advanced.sh
./deploy_advanced.sh
```

## 📝 Essential Commands

### Service Management
```bash
# Start service
sudo systemctl start fastapi

# Stop service
sudo systemctl stop fastapi

# Restart service
sudo systemctl restart fastapi

# Check status
sudo systemctl status fastapi

# Enable auto-start on boot
sudo systemctl enable fastapi
```

### View Logs
```bash
# Live logs (Ctrl+C to exit)
sudo journalctl -u fastapi -f

# Last 50 lines
sudo journalctl -u fastapi -n 50

# Only errors
sudo journalctl -u fastapi -p err -n 50

# Logs from today
sudo journalctl -u fastapi --since today

# Logs with timestamps
sudo journalctl -u fastapi -o short-iso
```

### Update Code
```bash
# Quick update
cd /home/ubuntu/cardlabsv3.0
git pull
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart fastapi

# Or use the script
./redeploy.sh
```

### Database Operations
```bash
# Connect to PostgreSQL
sudo -u postgres psql

# Connect to specific database
sudo -u postgres psql -d cardlabs

# Backup database
sudo -u postgres pg_dump cardlabs > backup.sql

# Restore database
sudo -u postgres psql cardlabs < backup.sql

# PostgreSQL commands (inside psql):
\l                  # List databases
\c dbname           # Connect to database
\dt                 # List tables
\d tablename        # Describe table
\q                  # Quit
```

### Nginx
```bash
# Test configuration
sudo nginx -t

# Reload configuration
sudo systemctl reload nginx

# Restart nginx
sudo systemctl restart nginx

# Check status
sudo systemctl status nginx

# View access logs
sudo tail -f /var/log/nginx/access.log

# View error logs
sudo tail -f /var/log/nginx/error.log
```

### SSL/HTTPS
```bash
# View certificate info
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Check auto-renewal timer
sudo systemctl status certbot.timer
```

## 🔧 Common Tasks

### Edit Environment Variables
```bash
nano /home/ubuntu/cardlabsv3.0/.env
sudo systemctl restart fastapi
```

### Update Python Dependencies
```bash
cd /home/ubuntu/cardlabsv3.0
source venv/bin/activate
pip install package-name
pip freeze > requirements.txt
sudo systemctl restart fastapi
```

### Change Number of Workers
```bash
sudo nano /etc/systemd/system/fastapi.service
# Change -w 4 to desired number
sudo systemctl daemon-reload
sudo systemctl restart fastapi
```

### View System Resources
```bash
# Memory
free -h

# Disk
df -h

# CPU
top
htop  # if installed

# Running processes
ps aux | grep gunicorn
```

## 🐛 Troubleshooting

### Service Won't Start
```bash
# Check logs for errors
sudo journalctl -u fastapi -n 100 --no-pager

# Test manually
cd /home/ubuntu/cardlabsv3.0
source venv/bin/activate
python main.py

# Or test with gunicorn
gunicorn -w 1 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000
```

### Database Connection Issues
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Test connection
sudo -u postgres psql -c "SELECT 1"

# Check .env file
cat /home/ubuntu/cardlabsv3.0/.env
```

### 502 Bad Gateway
```bash
# Check if app is running
sudo systemctl status fastapi

# Check nginx is running
sudo systemctl status nginx

# Test app directly
curl http://localhost:8000

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### High Memory Usage
```bash
# Check processes
ps aux --sort=-%mem | head -10

# Reduce workers in systemd service
sudo nano /etc/systemd/system/fastapi.service
# Change -w 4 to -w 2
sudo systemctl daemon-reload
sudo systemctl restart fastapi
```

## 📊 Monitoring

### Check if App is Responding
```bash
# Local test
curl http://localhost:8000

# Full test with headers
curl -I https://your-domain.com

# Response time
curl -w "@-" -o /dev/null -s https://your-domain.com <<'EOF'
     time_total:  %{time_total}s\n
EOF
```

### Active Connections
```bash
# See active connections
sudo netstat -tulpn | grep :8000

# Count connections
sudo netstat -an | grep :8000 | wc -l
```

## 🔐 Security

### Firewall Setup
```bash
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
sudo ufw status
```

### Change Database Password
```bash
sudo -u postgres psql
ALTER USER postgres PASSWORD 'new-password';
\q

# Update .env file
nano /home/ubuntu/cardlabsv3.0/.env
# Change DATABASE_URL password
sudo systemctl restart fastapi
```

### View Failed Login Attempts
```bash
sudo grep "Failed password" /var/log/auth.log | tail -20
```

## 📁 Important File Locations

```
/home/ubuntu/cardlabsv3.0/          # Application directory
/home/ubuntu/cardlabsv3.0/.env      # Environment variables
/home/ubuntu/cardlabsv3.0/venv/     # Virtual environment

/etc/systemd/system/fastapi.service # Systemd service file
/etc/nginx/sites-available/fastapi  # Nginx configuration

/var/log/nginx/access.log           # Nginx access logs
/var/log/nginx/error.log            # Nginx error logs

/etc/letsencrypt/live/              # SSL certificates
```

## 🔄 Backup & Restore

### Full Backup
```bash
# Backup database
sudo -u postgres pg_dump cardlabs > ~/backup_db_$(date +%Y%m%d).sql

# Backup application
tar -czf ~/backup_app_$(date +%Y%m%d).tar.gz /home/ubuntu/cardlabsv3.0

# Backup configs
sudo tar -czf ~/backup_configs_$(date +%Y%m%d).tar.gz \
  /etc/systemd/system/fastapi.service \
  /etc/nginx/sites-available/fastapi
```

### Restore
```bash
# Restore database
sudo -u postgres psql cardlabs < ~/backup_db_20240101.sql

# Restore application
tar -xzf ~/backup_app_20240101.tar.gz -C /
```

## 💡 Tips

1. **Always check logs first** when troubleshooting
2. **Test changes** before restarting in production
3. **Backup before updates** - use `./redeploy.sh` which does this automatically
4. **Monitor disk space** - logs can fill up quickly
5. **Keep dependencies updated** but test in staging first
6. **Use environment variables** for sensitive data
7. **Set up monitoring** with tools like Datadog, New Relic, or simple cron jobs

## 🆘 Emergency Recovery

### App is Down - Quick Fix
```bash
sudo systemctl restart fastapi
sudo systemctl restart nginx
```

### Complete Reset
```bash
# Stop everything
sudo systemctl stop fastapi nginx

# Check for stuck processes
ps aux | grep gunicorn
sudo killall gunicorn

# Start fresh
sudo systemctl start fastapi
sudo systemctl start nginx
```

### Rollback to Previous Version
```bash
cd /home/ubuntu/cardlabsv3.0
git log  # Find commit hash
git checkout <commit-hash>
./redeploy.sh
```
