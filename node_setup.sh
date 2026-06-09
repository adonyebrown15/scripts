#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  NODE SETUP SCRIPT
#  Student: paabinye-brown | Y = 59
#  Run as: any sudo user (from VirtualBox window directly)
# ─────────────────────────────────────────────────────────────

set -e

# ── VARIABLES ─────────────────────────────────────────────────
MYSENECA_USER="paabinye-brown"
IFACE_BRIDGE="enp0s9"   # Bridged adapter — gets IP from Relay via DHCP
# ──────────────────────────────────────────────────────────────

echo "============================================"
echo "  NODE SETUP — paabinye-brown / Y=59"
echo "============================================"

# ── STEP 0: Create MySeneca user ──────────────────────────────
echo ""
echo "[1/3] Creating MySeneca user: $MYSENECA_USER"
if id "$MYSENECA_USER" &>/dev/null; then
    echo "      User already exists — skipping."
else
    sudo adduser --gecos "" "$MYSENECA_USER"
    sudo usermod -aG sudo "$MYSENECA_USER"
    echo "$MYSENECA_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$MYSENECA_USER" > /dev/null
    echo "      User created with full sudo access."
fi

# ── STEP 1: Netplan ───────────────────────────────────────────
echo ""
echo "[2/3] Writing netplan config..."
sudo tee /etc/netplan/99_config.yaml > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE_BRIDGE}:
      dhcp4: true
      optional: true
EOF

sudo chmod 600 /etc/netplan/99_config.yaml
sudo netplan apply
echo "      Waiting for DHCP lease from Relay..."
sleep 10
echo "      Interfaces:"
ip --brief address
echo "      Routes:"
ip route show

# ── STEP 2: Enable SSH ────────────────────────────────────────
echo ""
echo "[3/3] Enabling SSH..."
sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable openssh-server 2>/dev/null || true
sudo systemctl start ssh 2>/dev/null || sudo systemctl start openssh-server 2>/dev/null || true
echo "      SSH status: $(sudo systemctl is-active ssh 2>/dev/null || sudo systemctl is-active openssh-server 2>/dev/null)"

# ── DONE ──────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  NODE SETUP COMPLETE"
echo "============================================"
echo "  Expected: ${IFACE_BRIDGE} = 192.168.59.82/28"
echo "  Expected: default gateway = 192.168.59.81"
echo "============================================"
echo ""
echo "  Run these tests to verify the full chain:"
echo "    ping -c 4 192.168.59.81   # Relay"
echo "    ping -c 4 192.168.59.1    # Gateway"
echo "    ping -c 4 1.1.1.1          # Internet"
echo "    ping -c 4 google.com       # DNS"
echo ""
echo "  If enp0s9 has no IP, check Relay's Kea is running:"
echo "    sudo systemctl status kea-dhcp4-server (on Relay)"
echo "  Then force renewal here:"
echo "    sudo systemctl restart systemd-networkd"
