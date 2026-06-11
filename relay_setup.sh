#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  RELAY SETUP SCRIPT
#  Student: paabinye-brown | Y = 99
#  NOTE: Prof provides this VM — check interface names first!
#        Run: ip --brief address
#        Then update IFACE_INTERNAL and IFACE_BRIDGE below if different.
#  Run as: any sudo user
# ─────────────────────────────────────────────────────────────

set -e

# ── VARIABLES (update if prof's VM has different interface names) ──
MYSENECA_USER="paabinye-brown"
IFACE_INTERNAL="enp0s8"      # Internal Network — gets IP from Gateway via DHCP
IFACE_BRIDGE="enp0s9"        # Bridged adapter — static IP, faces Node

RELAY_STATIC_IP="192.168.99.81/28"
SUBNET="192.168.99.80/28"
POOL="192.168.99.82 - 192.168.99.82"
ROUTER="192.168.99.81"
# ──────────────────────────────────────────────────────────────────

echo "============================================"
echo "  RELAY SETUP — paabinye-brown / Y=99"
echo "============================================"
echo ""
echo "  Current interfaces on this VM:"
ip --brief address
echo ""
echo "  IMPORTANT: Script expects:"
echo "    ${IFACE_INTERNAL} = Internal Network (DHCP from Gateway)"
echo "    ${IFACE_BRIDGE}   = Bridged adapter (static, faces Node)"
echo "  If your interfaces look different, press Ctrl+C now"
echo "  and update IFACE_INTERNAL / IFACE_BRIDGE at the top."
echo ""
sleep 5

# ── STEP 0: Create MySeneca user ──────────────────────────────
echo "[1/5] Creating MySeneca user: $MYSENECA_USER"
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
echo "[2/5] Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf > /dev/null
sudo sysctl --system > /dev/null 2>&1
echo "      ip_forward = $(cat /proc/sys/net/ipv4/ip_forward)"

# ── STEP 2: Netplan ───────────────────────────────────────────
echo ""
echo "[3/5] Writing netplan config..."
sudo tee /etc/netplan/99_config.yaml > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE_INTERNAL}:
      dhcp4: true
      optional: true
    ${IFACE_BRIDGE}:
      addresses: [${RELAY_STATIC_IP}]
      optional: true
      link-local: []
EOF

sudo chmod 600 /etc/netplan/99_config.yaml
sudo netplan apply
sleep 8
echo "      Interfaces after netplan apply:"
ip --brief address

# ── STEP 3: Remove old relay agent if present ─────────────────
echo ""
echo "[4/5] Checking for conflicting isc-dhcp-relay..."
sudo systemctl stop isc-dhcp-relay 2>/dev/null && echo "      Stopped isc-dhcp-relay" || echo "      isc-dhcp-relay not running (good)"
sudo systemctl disable isc-dhcp-relay 2>/dev/null || true

# ── STEP 4: Install and Configure Kea ────────────────────────
echo ""
echo "[5/5] Installing and configuring Kea..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kea > /dev/null 2>&1
echo "      Kea installed."

sudo truncate -s 0 /etc/kea/kea-dhcp4.conf
sudo tee /etc/kea/kea-dhcp4.conf > /dev/null << EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": ["${IFACE_BRIDGE}"]
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

# Clear stale leases
sudo truncate -s 0 /var/lib/kea/kea-leases4.csv

sudo systemctl restart kea-dhcp4-server
sudo systemctl enable kea-dhcp4-server > /dev/null 2>&1
echo "      Kea status: $(sudo systemctl is-active kea-dhcp4-server)"

# ── STEP 5: Enable SSH server ─────────────────────────────────
echo ""
echo "Enabling SSH server..."
sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable openssh-server 2>/dev/null || true
sudo systemctl start ssh 2>/dev/null || sudo systemctl start openssh-server 2>/dev/null || true
echo "      SSH status: $(sudo systemctl is-active ssh 2>/dev/null || echo inactive)"

# ── DONE ──────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  RELAY SETUP COMPLETE"
echo "============================================"
echo "  ${IFACE_INTERNAL} IP  : 192.168.99.2/29 (from Gateway Kea)"
echo "  ${IFACE_BRIDGE}   IP  : 192.168.99.81/28 (static)"
echo "  Kea subnet   : 192.168.99.80/28"
echo "  Kea pool     : 192.168.99.82 (Node only)"
echo "============================================"
echo ""
echo "  Final interface state:"
ip --brief address
echo ""
echo "  Verify Gateway gave us 192.168.99.2 on ${IFACE_INTERNAL}."
echo "  If not, run: sudo systemctl restart systemd-networkd"
echo "  Then wait 10s and check again."
