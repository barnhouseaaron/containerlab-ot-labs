#!/bin/bash
# ============================================================================
# Conduit policy validation - proves the segmentation actually holds.
#
# Runs a matrix of tests against the deployed lab:
#   - ALLOWED conduits (adjacent zones, correct port) must succeed
#   - DENIED paths (non-adjacent, or wrong port) must be blocked
#
# Run AFTER `sudo containerlab deploy`.
# ============================================================================
LAB=ot-iec62443
PASS=0
FAIL=0

# container name helper (containerlab prefixes clab-<lab>-<node>)
c () { echo "clab-${LAB}-$1"; }

# Start service listeners in each zone host so TCP conduit tests have a target.
start_listeners () {
  docker exec -d "$(c idmz)"       nc -lk -p 443
  docker exec -d "$(c ops)"        nc -lk -p 443
  docker exec -d "$(c control)"    nc -lk -p 4840
  docker exec -d "$(c field)"      nc -lk -p 502
  docker exec -d "$(c field)"      nc -lk -p 44818
  sleep 2
}

# test_tcp <src_node> <dst_ip> <port> <expect: PERMIT|DENY> "<label>"
test_tcp () {
  local src=$1 dip=$2 port=$3 expect=$4 label=$5
  if docker exec "$(c $src)" nc -z -w2 "$dip" "$port" >/dev/null 2>&1; then
    result=PERMIT
  else
    result=DENY
  fi
  if [ "$result" = "$expect" ]; then
    printf "  [ PASS ] %-55s (%s)\n" "$label" "$result"
    PASS=$((PASS+1))
  else
    printf "  [ FAIL ] %-55s (got %s, want %s)\n" "$label" "$result" "$expect"
    FAIL=$((FAIL+1))
  fi
}

echo "Starting zone service listeners..."
start_listeners

echo ""
echo "=== ALLOWED conduits (adjacent level, correct service) ==="
test_tcp enterprise 10.35.0.10 443   PERMIT "L4 enterprise -> L3.5 IDMZ  : HTTPS broker"
test_tcp idmz       10.30.0.10 443   PERMIT "L3.5 IDMZ      -> L3 ops     : historian replication"
test_tcp ops        10.20.0.10 4840  PERMIT "L3 ops         -> L2 control : OPC UA"
test_tcp control    10.10.0.10 502   PERMIT "L2 control     -> L0/L1 field: Modbus/TCP"
test_tcp control    10.10.0.10 44818 PERMIT "L2 control     -> L0/L1 field: EtherNet/IP"

echo ""
echo "=== DENIED paths (non-adjacent, or wrong service) ==="
test_tcp enterprise 10.10.0.10 502   DENY   "L4 enterprise -> L0/L1 field : direct PLC access (level-skip)"
test_tcp enterprise 10.20.0.10 4840  DENY   "L4 enterprise -> L2 control  : direct SCADA access (level-skip)"
test_tcp idmz       10.10.0.10 502   DENY   "L3.5 IDMZ     -> L0/L1 field : direct PLC access (level-skip)"
test_tcp enterprise 10.35.0.10 22    DENY   "L4 enterprise -> L3.5 IDMZ   : SSH (port not in conduit)"
test_tcp ops        10.10.0.10 502   DENY   "L3 ops        -> L0/L1 field : Modbus (level-skip)"

echo ""
echo "============================================================"
echo "  RESULT: $PASS passed, $FAIL failed"
echo "============================================================"
[ "$FAIL" -eq 0 ] && echo "Segmentation policy verified." || echo "Policy did NOT behave as designed - investigate."
exit "$FAIL"
