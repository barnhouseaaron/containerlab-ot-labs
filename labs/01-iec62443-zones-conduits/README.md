# Lab 01 - IEC 62443 zones and conduits

A five-zone industrial network segmented on the Purdue model, with a firewall that
enforces **deny-by-default** and permits traffic **only between adjacent levels**, on
**only the service ports** a real plant would open. A validation script proves it.

## The design

```
   L4  Enterprise      10.40.0.0/24   business network
        |  conduit: HTTPS pull from the IDMZ broker only
   L3.5 IDMZ           10.35.0.0/24   data broker, patch/AV, remote-access jump
        |  conduit: historian replication (HTTPS)
   L3  Operations      10.30.0.0/24   historian, MES
        |  conduit: OPC UA read
   L2  Control         10.20.0.0/24   HMI, SCADA
        |  conduit: Modbus/TCP + EtherNet/IP poll
   L0/L1 Field         10.10.0.0/24   PLCs, sensors, actuators
```

A single `fw` node sits between every zone and routes among them. Its `FORWARD`
policy defaults to `DROP`. Each conduit below is the *only* thing punched through:

| Conduit | Direction | Service | Rationale |
|---------|-----------|---------|-----------|
| L4 <-> L3.5 | enterprise -> IDMZ | tcp/443 | business pulls data from the DMZ broker, never straight from the plant |
| L3.5 <-> L3 | IDMZ -> ops | tcp/443 | broker replicates from the historian |
| L3 <-> L2 | ops -> control | tcp/4840 | operations reads supervisory data over OPC UA |
| L2 <-> L0/L1 | control -> field | tcp/502, tcp/44818 | control polls PLCs (Modbus/TCP, EtherNet/IP) |

Everything else falls through to `DROP`. Critically, **no level can skip a level**:
enterprise cannot talk directly to control or field, the IDMZ cannot reach field, and
so on. That adjacent-only property is the core of the IEC 62443 conduit model and of a
defensible IT/OT boundary.

## Run it

```bash
sudo containerlab deploy         # bring up fw + 5 zone hosts
./validate.sh                    # run the allowed-vs-denied test matrix
```

Expected tail of `validate.sh`:

```
  RESULT: 10 passed, 0 failed
Segmentation policy verified.
```

Tear down:

```bash
sudo containerlab destroy --cleanup
```

## Poke at it yourself

```bash
# inspect the live policy
docker exec clab-ot-iec62443-fw iptables -L FORWARD -n -v

# watch a level-skip attempt get logged as it is dropped
docker exec clab-ot-iec62443-fw sh -c 'dmesg | grep CONDUIT-DROP | tail'

# prove a permitted conduit by hand
docker exec clab-ot-iec62443-control nc -z -w2 10.10.0.10 502  ; echo $?  # 0 = allowed
docker exec clab-ot-iec62443-enterprise nc -z -w2 10.10.0.10 502 ; echo $?  # non-zero = blocked
```

## What this demonstrates

- Zone and conduit segmentation per IEC 62443 / ISA-99
- Deny-by-default with least-privilege conduits (NIST SP 800-41 alignment)
- Purdue-model level adjacency enforced in an actual ruleset, not just a diagram
- Industrial-protocol awareness (Modbus/TCP 502, EtherNet/IP 44818, OPC UA 4840)

## Notes

- Fully synthetic: fictional plant, RFC 1918 example ranges, no real device data.
- The firewall here is Linux `iptables` for portability so anyone can run it with only
  Docker. The same policy maps cleanly onto a FortiGate (interface/zone pairs, address
  objects, and a service-scoped policy table with an implicit deny). A FortiGate variant
  is a planned addition.
