# ─────────────────────────────────────────────────────────────
#  GATEWAY WINDOWS SETUP SCRIPT
#  Student: paabinye-brown | Y = 53
#  Labs: 2 (Static IP)  3 (DHCP Server)  4 (Firewall) + NAT
#  Run in PowerShell as Administrator
# ─────────────────────────────────────────────────────────────

$GW_IP       = "192.168.53.1"
$PREFIX      = 29
$RELAY_IP    = "192.168.53.2"
$NODE_NET    = "192.168.53.80/28"
$DHCP_START  = "192.168.53.2"
$DHCP_END    = "192.168.53.2"
$DHCP_SUBNET = "192.168.53.0"
$DHCP_MASK   = "255.255.255.248"

Write-Host "============================================"
Write-Host "  GATEWAY SETUP - paabinye-brown / Y=53"
Write-Host "============================================"

# ── Auto-detect adapters ──────────────────────────────────────
# NAT adapter already has 10.0.2.x DHCP from VirtualBox
# Internal adapter has no IP (APIPA 169.254.x or nothing)
$NAT_IFACE = $null
$INT_IFACE = $null

foreach ($a in (Get-NetAdapter | Where-Object Status -eq "Up")) {
    $cfg = Get-NetIPConfiguration -InterfaceAlias $a.Name
    if ($cfg.IPv4DefaultGateway) {
        $NAT_IFACE = $a.Name
    } else {
        $INT_IFACE = $a.Name
    }
}

if (-not $NAT_IFACE -or -not $INT_IFACE) {
    Write-Host "ERROR: Could not detect both adapters. Check Get-NetAdapter."
    exit 1
}

Write-Host "  NAT adapter      : $NAT_IFACE  (internet-facing, leave it)"
Write-Host "  Internal adapter : $INT_IFACE  (faces Relay)"
Write-Host ""

# ── [1/6] Static IP on Internal adapter ──────────────────────
Write-Host "[1/6] Setting static IP $GW_IP/$PREFIX on $INT_IFACE..."
Remove-NetIPAddress -InterfaceAlias $INT_IFACE -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceAlias $INT_IFACE -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress    -InterfaceAlias $INT_IFACE -IPAddress $GW_IP -PrefixLength $PREFIX
Write-Host "      Done."

# ── [2/6] Route to Node network ──────────────────────────────
Write-Host "[2/6] Adding route: $NODE_NET via $RELAY_IP ..."
New-NetRoute -InterfaceAlias $INT_IFACE -DestinationPrefix $NODE_NET -NextHop $RELAY_IP -ErrorAction SilentlyContinue
Write-Host "      Done."

# ── [3/6] Enable IP Routing ──────────────────────────────────
Write-Host "[3/6] Enabling IP routing..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "IPEnableRouter" -Value 1
Write-Host "      Done."

# ── [4/6] Install DHCP + Routing roles ───────────────────────
Write-Host "[4/6] Installing DHCP Server and Routing roles (this takes ~1 min)..."
Install-WindowsFeature -Name DHCP    -IncludeManagementTools | Out-Null
Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
Write-Host "      Done."

# ── [5/6] Configure DHCP scope ───────────────────────────────
Write-Host "[5/6] Configuring DHCP scope for 192.168.53.0/29..."
Add-DhcpServerInDC -ErrorAction SilentlyContinue
Add-DhcpServerv4Scope -Name "GW-Relay" `
    -StartRange $DHCP_START `
    -EndRange   $DHCP_END   `
    -SubnetMask $DHCP_MASK  `
    -State Active
Set-DhcpServerv4OptionValue -ScopeId $DHCP_SUBNET -Router $GW_IP -DnsServer 8.8.8.8,1.1.1.1
Set-Service     DHCPServer -StartupType Automatic
Restart-Service DHCPServer
Write-Host "      DHCP active. Pool: $DHCP_START (Relay only)."

# ── [6/6] NAT via RRAS ───────────────────────────────────────
Write-Host "[6/6] Configuring NAT..."
Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue
Start-Sleep 3
cmd /c "netsh routing ip nat install" 2>$null
cmd /c "netsh routing ip nat add interface `"$NAT_IFACE`" full"
cmd /c "netsh routing ip nat add interface `"$INT_IFACE`" private"
Write-Host "      NAT: $INT_IFACE (private) -> $NAT_IFACE (public/internet)"

# ── Lab 4: Firewall ───────────────────────────────────────────
Write-Host ""
Write-Host "[Lab4] Firewall: block all inbound except SSH (22)..."
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
New-NetFirewallRule -DisplayName "Allow SSH"  -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "Allow DHCP" -Direction Inbound -Protocol UDP -LocalPort 68 -Action Allow -Profile Any
Write-Host "      Done."

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================"
Write-Host "  GATEWAY SETUP COMPLETE"
Write-Host "============================================"
Write-Host "  $INT_IFACE  : $GW_IP/$PREFIX"
Write-Host "  Route       : $NODE_NET via $RELAY_IP"
Write-Host "  DHCP scope  : 192.168.53.0/29 -> pool .2 (Relay)"
Write-Host "  NAT         : $INT_IFACE -> $NAT_IFACE"
Write-Host "  Firewall    : Block all inbound except port 22"
Write-Host "============================================"
Write-Host ""
ipconfig
