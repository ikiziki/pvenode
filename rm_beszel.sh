#!/usr/bin/env bash

set -e

SERVICE_NAME="beszel-agent"
INSTALL_DIR="/opt/beszel-agent"
CONFIG_DIR="/etc/beszel"
LOG_DIR="/var/log/beszel"

echo "Stopping Beszel agent service..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl stop "$SERVICE_NAME"
fi

echo "Disabling service..."
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    sudo systemctl disable "$SERVICE_NAME"
fi

echo "Removing systemd service file..."
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
fi

echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Removing installation directory..."
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"
fi

echo "Removing config directory..."
if [ -d "$CONFIG_DIR" ]; then
    sudo rm -rf "$CONFIG_DIR"
fi

echo "Removing logs..."
if [ -d "$LOG_DIR" ]; then
    sudo rm -rf "$LOG_DIR"
fi

echo "Removing leftover binaries..."
sudo rm -f /usr/local/bin/beszel-agent || true
sudo rm -f /usr/bin/beszel-agent || true

echo "Beszel agent removal complete."
