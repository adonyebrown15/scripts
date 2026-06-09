#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  GATEWAY SETUP SCRIPT
#  Student: paabinye-brown | Y = 59
#  Networks: 192.168.59.0/29 (Gateway-Relay)
#            192.168.59.80/28 (Relay-Node)
#  Run as: any sudo user
# ─────────────────────────────────────────────────────────────

set -e

# ── VARIABLES (change these if prof changes Y or interface names) ──
MYSENECA_USER="paabinye-brown"
IFACE_NAT="enp0s3"           # NAT adapter — internet facing
IFACE_INTERNAL="enp0s8"      # Internal Network adapter — faces Relay

GW_IP="192.168.59.1/29"
RELAY_IP="192.168.59.2"
NODE_NET="192.168.59.80/28"
SUBNET="192.168.59.0/29"
POOL="192.168.59.2 - 192.168.59.2"
ROUTER="192.168.59.1"
# ──────────────────────────────────────────────────────────────────

echo "============================================"
echo "  GATEWAY SETUP — paabinye-brown / Y=59"
echo "============================================"

# ── STEP 0: Create MySeneca user ──────────────────────────────
echo ""
echo "[1/6] Creating MySeneca user: $MYSENECA_USER"
if id "$MYSENECA_USER" &>/dev/null; then
    echo "      User already exists — skipping."
else
    sudo adduser --gecos "" "$MYSENECA_USER"
    sudo usermod -aG sudo "$MYSENECA_USER"
    echo "$MYSENECA_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$MYSENECA_USER" > /dev/null
    echo "      User created with full sudo access."
fi

# ── STEP 1: IP Forwarding ─────────────────────────────────────
echo ""
echo "[2/6] Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf > /dev/null
sudo sysctl --system > /dev/null 2>&1
echo "      ip_forward = $(cat /proc/sys/net/ipv4/ip_forward)"

# ── STEP 2: Netplan ───────────────────────────────────────────
echo ""
echo "[3/6] Writing netplan config..."
sudo tee /etc/netplan/99_config.yaml > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE_INTERNAL}:
      addresses:
        - ${GW_IP}
      optional: true
      routes:
        - to: ${NODE_NET}
          via: ${RELAY_IP}
EOF

sudo chmod 600 /etc/netplan/99_config.yaml
sudo netplan apply
echo "      Interfaces after netplan apply:"
ip --brief address

# ── STEP 3: Install Kea ───────────────────────────────────────
echo ""
echo "[4/6] Installing Kea DHCP..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kea > /dev/null 2>&1
echo "      Kea installed."

# ── STEP 4: Configure Kea ────────────────────────────────────
echo ""
echo "[5/6] Configuring Kea..."
sudo truncate -s 0 /etc/kea/kea-dhcp4.conf
sudo tee /etc/kea/kea-dhcp4.conf > /dev/null << EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": ["${IFACE_INTERNAL}"]
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv"
    },
    "subnet4": [
      {
        "id": 1,
        "subnet": "${SUBNET}",
        "pools": [
          { "pool": "${POOL}" }
        ],
        "option-data": [
          {
            "name": "routers",
            "data": "${ROUTER}"
          },
          {
            "name": "domain-name-servers",
            "data": "8.8.8.8, 1.1.1.1"
          }
        ]
      }
    ]
  }
}
EOF

echo "      Testing Kea config..."
if sudo -u _kea kea-dhcp4 -t /etc/kea/kea-dhcp4.conf 2>&1; then
    echo "      Config OK — no errors."
else
    echo "      ERROR: Kea config failed! Check /etc/kea/kea-dhcp4.conf"
    exit 1
fi

# Clear any stale leases
sudo truncate -s 0 /var/lib/kea/kea-leases4.csv

sudo systemctl restart kea-dhcp4-server
sudo systemctl enable kea-dhcp4-server > /dev/null 2>&1
echo "      Kea status: $(sudo systemctl is-active kea-dhcp4-server)"

# ── STEP 5: NAT with nftables ─────────────────────────────────
echo ""
echo "[6/6] Setting up NAT..."
sudo nft flush ruleset
sudo nft add table ip nat
sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; }'
sudo nft add rule ip nat POSTROUTING oifname "${IFACE_NAT}" counter masquerade

# Save rules for reboot persistence
sudo nft list ruleset | sudo tee /etc/nftables.ruleset > /dev/null

# networkd-dispatcher boot hook
sudo mkdir -p /etc/networkd-dispatcher/routable.d
sudo tee /etc/networkd-dispatcher/routable.d/50-ifup.hooks > /dev/null << 'HOOKEOF'
#!/bin/sh
/usr/sbin/nft --file /etc/nftables.ruleset
exit 0
HOOKEOF
sudo chmod a+x /etc/networkd-dispatcher/routable.d/50-ifup.hooks

echo "      NAT rules:"
sudo nft list ruleset

# ── DONE ──────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  GATEWAY SETUP COMPLETE"
echo "============================================"
echo "  enp0s8 IP   : 192.168.59.1/29"
echo "  Return route: 192.168.59.80/28 via 192.168.59.2"
echo "  Kea subnet  : 192.168.59.0/29"
echo "  Kea pool    : 192.168.59.2 (Relay only)"
echo "  NAT         : masquerade on ${IFACE_NAT}"
echo "============================================"
ip --brief address
ip route show
