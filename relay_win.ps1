# ─────────────────────────────────────────────────────────────
#  RELAY WINDOWS SETUP SCRIPT
#  Student: paabinye-brown | Y = 53
#  Ethernet   (Adapter 1) = Internal Network -> DHCP from Gateway
#  Ethernet 2 (Adapter 2) = Bridged -> Static 192.168.53.81/28
#  Run in PowerShell as Administrator
# ─────────────────────────────────────────────────────────────

$INT_IFACE        = "Ethernet"    # Internal - gets DHCP from Gateway
$BRIDGE_IFACE     = "Ethernet 2"  # Bridged  - static, faces Node

$RELAY_STATIC_IP  = "192.168.53.81"
$PREFIX           = 28
$DHCP_START       = "192.168.53.82"
$DHCP_END         = "192.168.53.82"
$DHCP_SUBNET      = "192.168.53.80"
$DHCP_MASK        = "255.255.255.240"
$ROUTER           = "192.168.53.81"

Write-Host "============================================"
Write-Host "  RELAY SETUP - paabinye-brown / Y=53"
Write-Host "============================================"
Write-Host ""
Write-Host "  Current interfaces:"
Get-NetAdapter | Select-Object Name, Status | Format-Table -AutoSize
Write-Host ""
Write-Host "  Script expects:"
Write-Host "    $INT_IFACE    = Internal Network (DHCP from Gateway)"
Write-Host "    $BRIDGE_IFACE = Bridged (static, faces Node)"
Write-Host ""
Start-Sleep 3

# ── [1/5] Enable IP Routing ──────────────────────────────────
Write-Host "[1/5] Enabling IP routing..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "IPEnableRouter" -Value 1
Write-Host "      Done."

# ── [2/5] Static IP on Bridged adapter ───────────────────────
Write-Host "[2/5] Setting static IP $RELAY_STATIC_IP/$PREFIX on $BRIDGE_IFACE..."
Remove-NetIPAddress -InterfaceAlias $BRIDGE_IFACE -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceAlias $BRIDGE_IFACE -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress    -InterfaceAlias $BRIDGE_IFACE -IPAddress $RELAY_STATIC_IP -PrefixLength $PREFIX
Write-Host "      Done."

# ── [3/5] Install DHCP + Routing roles ───────────────────────
Write-Host "[3/5] Installing DHCP Server and Routing roles (this takes ~1 min)..."
Install-WindowsFeature -Name DHCP    -IncludeManagementTools | Out-Null
Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
Write-Host "      Done."

# ── [4/5] Configure DHCP scope ───────────────────────────────
Write-Host "[4/5] Configuring DHCP scope for 192.168.53.80/28..."
Add-DhcpServerInDC -ErrorAction SilentlyContinue
Add-DhcpServerv4Scope -Name "Relay-Node" `
    -StartRange $DHCP_START `
    -EndRange   $DHCP_END   `
    -SubnetMask $DHCP_MASK  `
    -State Active
Set-DhcpServerv4OptionValue -ScopeId $DHCP_SUBNET -Router $ROUTER -DnsServer 8.8.8.8,1.1.1.1
Set-Service     DHCPServer -StartupType Automatic
Restart-Service DHCPServer
Write-Host "      DHCP active. Pool: $DHCP_START (Node only)."

# ── [5/5] Firewall ───────────────────────────────────────────
Write-Host "[5/5] Firewall: block all inbound except SSH (22)..."
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
New-NetFirewallRule -DisplayName "Allow SSH"  -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "Allow DHCP" -Direction Inbound -Protocol UDP -LocalPort 68 -Action Allow -Profile Any
Write-Host "      Done."

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================"
Write-Host "  RELAY SETUP COMPLETE"
Write-Host "============================================"
Write-Host "  $INT_IFACE   : DHCP (expects 192.168.53.2 from Gateway)"
Write-Host "  $BRIDGE_IFACE: $RELAY_STATIC_IP/$PREFIX (static)"
Write-Host "  DHCP scope   : 192.168.53.80/28 -> pool .82 (Node only)"
Write-Host "  Firewall     : Block all inbound except port 22"
Write-Host "============================================"
Write-Host ""
Write-Host "  Waiting 10s for DHCP lease on $INT_IFACE..."
Start-Sleep 10
ipconfig
Write-Host ""
Write-Host "  Ethernet should now show 192.168.53.2 from Gateway."
Write-Host "  If not: ipconfig /release Ethernet && ipconfig /renew Ethernet"
