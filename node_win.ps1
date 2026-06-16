# ─────────────────────────────────────────────────────────────
#  NODE WINDOWS SETUP SCRIPT
#  Student: paabinye-brown | Y = 53
#  Ethernet (Adapter 1) = Bridged -> DHCP from Relay
#  Run in PowerShell as Administrator
# ─────────────────────────────────────────────────────────────

$IFACE = "Ethernet"

Write-Host "============================================"
Write-Host "  NODE SETUP - paabinye-brown / Y=53"
Write-Host "============================================"

# ── [1/3] Ensure DHCP on Ethernet ────────────────────────────
Write-Host "[1/3] Setting $IFACE to DHCP and renewing..."
Set-NetIPInterface -InterfaceAlias $IFACE -Dhcp Enabled -ErrorAction SilentlyContinue
Set-DnsClientServerAddress -InterfaceAlias $IFACE -ResetServerAddresses -ErrorAction SilentlyContinue
ipconfig /release $IFACE 2>$null
ipconfig /renew   $IFACE 2>$null
Write-Host "      Waiting 10s for DHCP lease from Relay..."
Start-Sleep 10
ipconfig

# ── [2/3] Firewall ───────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Firewall: block all inbound except SSH (22)..."
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
New-NetFirewallRule -DisplayName "Allow SSH" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
Write-Host "      Done."

# ── [3/3] Verify ─────────────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Final state:"
ipconfig
Write-Host ""
Write-Host "  Run these to verify the full chain:"
Write-Host "    ping 192.168.53.81    # Relay"
Write-Host "    ping 192.168.53.1     # Gateway"
Write-Host "    ping 1.1.1.1           # Internet"
Write-Host "    ping google.com        # DNS"
Write-Host ""
Write-Host "============================================"
Write-Host "  NODE SETUP COMPLETE"
Write-Host "  Expected IP : 192.168.53.82/28"
Write-Host "  Expected GW : 192.168.53.81"
Write-Host "============================================"
