#!/bin/bash
# OpenVPN Setup Script
# This script handles the initialization and startup of the OpenVPN server

# Error handling
set -e
trap "echo \"Error occurred! Exiting...\"; exit 1" ERR

# Environment file creation
if [ ! -f /etc/openvpn/ovpn_env.sh ]; then
  echo "Creating environment file..."
  echo "export OVPN_AUTH=" > /etc/openvpn/ovpn_env.sh
  echo "export OVPN_CIPHER=AES-256-GCM" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_CLIENT_TO_CLIENT=1" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_CN=${HOSTNAME}" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_COMP_LZO=0" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DEFROUTE=1" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DEVICE=tun" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DEVICEN=0" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DISABLE_PUSH_BLOCK_DNS=0" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DNS=1" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DNS_SERVERS=(\"8.8.8.8\" \"8.8.4.4\")" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_ENV=/etc/openvpn/ovpn_env.sh" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_EXTRA_CLIENT_CONFIG=()" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_EXTRA_SERVER_CONFIG=()" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_FRAGMENT=" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_MTU=" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_NAT=1" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_OTP_AUTH=" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_PORT=1194" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_PROTO=both" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_PUSH=()" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_ROUTES=([0]=\"10.20.0.0/24\")" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_SERVER=10.20.0.0/24" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_SERVER_URL=udp://${HOSTNAME}:1194" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_SERVER_URL_TCP=tcp://${HOSTNAME}:1195" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_TLS_CIPHER=TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_TLS_VERSION_MIN=1.2" >> /etc/openvpn/ovpn_env.sh
  echo "export OVPN_DUPLICATE_CN=1" >> /etc/openvpn/ovpn_env.sh
  chmod 644 /etc/openvpn/ovpn_env.sh
  echo "Environment file created successfully"
else
  echo "Using existing environment file"
fi

# Create required directories
mkdir -p /etc/openvpn/ccd

# Start OpenVPN
echo "Starting OpenVPN server..."
exec openvpn --config /etc/openvpn/openvpn.conf --client-config-dir /etc/openvpn/ccd 