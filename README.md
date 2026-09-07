# containerlab-ot-labs

Runnable, containerized labs for **OT / ICS network security**. Each lab spins up a
small industrial network with [containerlab](https://containerlab.dev/), enforces a
real segmentation policy, and ships a validation script that *proves* the policy does
what it claims - allowed conduits pass, everything else is dropped.

Everything is synthetic. Fictional plant, RFC 1918 example ranges, no vendor or client
data. The point is to demonstrate design patterns you can read, run, and break.

## Why these labs

Segmentation diagrams are easy to draw and hard to trust. A picture of a firewall
between two zones tells you nothing about whether the ruleset actually blocks the
traffic it should. These labs make the policy executable: you bring the topology up,
run the tests, and watch a non-adjacent path get denied.

## Labs

| # | Lab | Demonstrates |
|---|-----|--------------|
| 01 | [IEC 62443 zones and conduits](labs/01-iec62443-zones-conduits/) | Purdue-model segmentation with deny-by-default conduits; adjacent-only permits from field to enterprise |

More on the way (ring resiliency, FortiGate variant, flat-vs-segmented lateral-movement demo).

## Prerequisites

- Linux host (or WSL2) with Docker
- [containerlab](https://containerlab.dev/install/) v0.50+
- ~1 GB RAM free; these labs are small

```bash
# install containerlab (one-liner from the project)
bash -c "$(curl -sL https://get.containerlab.dev)"
```

## Quick start

```bash
cd labs/01-iec62443-zones-conduits
sudo containerlab deploy         # bring the topology up
./validate.sh                    # prove the conduit policy
sudo containerlab destroy --cleanup
```

## Repo layout

```
containerlab-ot-labs/
├── labs/
│   └── 01-iec62443-zones-conduits/
│       ├── topology.clab.yml     # the network
│       ├── configs/fw-init.sh    # firewall / conduit policy
│       ├── validate.sh           # allowed vs denied test matrix
│       └── README.md             # the design, zone by zone
├── LICENSE
└── .gitignore
```

## License

MIT - see [LICENSE](LICENSE).
