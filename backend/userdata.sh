#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install WireGuard
apt-get install -y wireguard qrencode

# Generate server keys
cd /etc/wireguard
umask 077
wg genkey | tee privatekey | wg pubkey > publickey

# Configure WireGuard
cat > /etc/wireguard/wg0.conf << 'WGCONF'
[Interface]
PrivateKey = $(cat privatekey)
Address = 10.10.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
WGCONF

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Signal completion
touch /var/lib/cloud/instance/wg-setup-complete
