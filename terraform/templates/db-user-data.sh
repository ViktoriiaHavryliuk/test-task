#!/bin/bash
# MySQL instance bootstrap on the pre-baked AMI. Runs once at first boot.
# Assumes the server package is installed; nothing is downloaded here
# because the data tier has no route out of the VPC.
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

DB_PASSWORD="${db_password}"

systemctl enable --now mariadb 2>/dev/null || systemctl enable --now mysqld

# Network reachability is controlled by the security group (3306 from the
# app SG only), so the account itself can use a wildcard host.
mysql <<SQL
CREATE DATABASE IF NOT EXISTS app;
CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON app.* TO 'app'@'%';
FLUSH PRIVILEGES;
SQL
