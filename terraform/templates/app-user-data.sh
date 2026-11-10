#!/bin/bash
# App instance bootstrap. Runs once at first boot.
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

APP_PORT="${app_port}"
PACKAGE_URL="${package_url}"
DB_HOST="${db_host}"
DB_PASSWORD="${db_password}"

# 1. Mandatory package from example.com.
#    Leaves the VPC through the Network Firewall, which allows example.com.
#    If this fails the application must not start, so the script exits
#    non-zero and the ALB health check never goes green.
curl -fsSL --retry 5 --retry-delay 10 "$PACKAGE_URL" -o /tmp/app-package.rpm
dnf install -y /tmp/app-package.rpm

# 2. Reachability check of MySQL on 3306 through the SG chain. A plain TCP
#    connect, so no client package is needed from any repository.
DB_STATUS="unreachable"
for i in $(seq 1 20); do
  if (exec 3<>"/dev/tcp/$DB_HOST/3306") 2>/dev/null; then
    DB_STATUS="port 3306 open"
    break
  fi
  sleep 15
done

# 3. Placeholder application: a static page on the app port behind the ALB.
mkdir -p /var/www/app
cat > /var/www/app/index.html <<HTML
<html><body style="font-family:sans-serif">
<h1>CDE POC app</h1>
<p>host: $(hostname)</p>
<p>mysql $DB_HOST: $DB_STATUS</p>
</body></html>
HTML

cat > /etc/systemd/system/cde-app.service <<UNIT
[Unit]
Description=CDE POC placeholder application
After=network-online.target

[Service]
WorkingDirectory=/var/www/app
ExecStart=/usr/bin/python3 -m http.server $APP_PORT
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now cde-app
