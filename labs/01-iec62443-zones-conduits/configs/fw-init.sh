#!/bin/bash
# Ensure iptables is present in the container (no-op if already installed).
apk add --no-cache iptables >/dev/null 2>&1 || true
# ============================================================================
# IEC 62443 conduit policy - deny-by-default, adjacent-only permits
# ============================================================================
# This runs inside the "fw" node. It gives the firewall an interface in each
# zone, turns on forwarding, and then installs an iptables policy where the
# FORWARD chain defaults to DROP. Only the explicit conduits below are allowed,
# and only between ADJACENT Purdue levels.
#
# Zone map (interface -> zone -> Purdue level -> subnet):
#   eth1  enterprise   L4     10.40.0.0/24
#   eth2  idmz         L3.5   10.35.0.0/24
#   eth3  ops          L3     10.30.0.0/24
#   eth4  control      L2     10.20.0.0/24
#   eth5  field        L0/L1  10.10.0.0/24
# ============================================================================
set -e

# ---- Interface addressing --------------------------------------------------
ip addr add 10.40.0.1/24 dev eth1 || true
ip addr add 10.35.0.1/24 dev eth2 || true
ip addr add 10.30.0.1/24 dev eth3 || true
ip addr add 10.20.0.1/24 dev eth4 || true
ip addr add 10.10.0.1/24 dev eth5 || true
for i in 1 2 3 4 5; do ip link set eth$i up || true; done

# ---- Routing ---------------------------------------------------------------
sysctl -w net.ipv4.ip_forward=1

ENTERPRISE=10.40.0.0/24
IDMZ=10.35.0.0/24
OPS=10.30.0.0/24
CONTROL=10.20.0.0/24
FIELD=10.10.0.0/24

# ---- Baseline: deny by default --------------------------------------------
iptables -F FORWARD
iptables -P FORWARD DROP
# Allow already-established/related return traffic for permitted flows.
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Helper: permit a directional conduit for a single service port (tcp).
# usage: conduit <src_subnet> <dst_subnet> <proto> <dport> "<description>"
conduit () {
  local src=$1 dst=$2 proto=$3 dport=$4 desc=$5
  iptables -A FORWARD -s "$src" -d "$dst" -p "$proto" --dport "$dport" \
    -m conntrack --ctstate NEW -j ACCEPT
  echo "  PERMIT  $src -> $dst  $proto/$dport   ($desc)"
}

# Helper: permit ICMP echo between two adjacent zones (both directions).
icmp_pair () {
  iptables -A FORWARD -s "$1" -d "$2" -p icmp --icmp-type echo-request -j ACCEPT
  iptables -A FORWARD -s "$2" -d "$1" -p icmp --icmp-type echo-request -j ACCEPT
}

echo "Installing IEC 62443 conduits (adjacent-only, deny-by-default):"

# ---- Conduit L4 <-> L3.5 : enterprise reaches the IDMZ broker only ---------
conduit $ENTERPRISE $IDMZ tcp 443  "enterprise pulls from IDMZ data broker (HTTPS)"
icmp_pair $ENTERPRISE $IDMZ

# ---- Conduit L3.5 <-> L3 : IDMZ broker replicates from the historian -------
conduit $IDMZ $OPS tcp 443  "IDMZ historian replication (HTTPS)"
icmp_pair $IDMZ $OPS

# ---- Conduit L3 <-> L2 : site ops reads supervisory data (OPC UA) ----------
conduit $OPS $CONTROL tcp 4840  "operations reads SCADA/HMI via OPC UA"
icmp_pair $OPS $CONTROL

# ---- Conduit L2 <-> L1/L0 : control polls field devices --------------------
conduit $CONTROL $FIELD tcp 502    "control polls PLCs via Modbus/TCP"
conduit $CONTROL $FIELD tcp 44818  "control polls PLCs via EtherNet/IP"
icmp_pair $CONTROL $FIELD

# Everything not listed above falls through to the default DROP:
#   - enterprise (L4) can NOT reach ops, control, or field directly
#   - idmz (L3.5) can NOT reach control or field
#   - no zone can skip a level
iptables -A FORWARD -j LOG --log-prefix "CONDUIT-DROP " --log-level 4

echo "Conduit policy loaded. FORWARD default = DROP."
