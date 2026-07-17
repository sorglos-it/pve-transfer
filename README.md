# pve-transfer

[![Shell](https://img.shields.io/badge/shell-bash-89e051.svg)](#)
[![Platform](https://img.shields.io/badge/platform-Proxmox%20VE-e57000.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Donate](https://img.shields.io/badge/Donate-PayPal-00457C.svg?logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

Bash script to transfer or clone **LXC containers and VMs** between Proxmox VE nodes — or on the same node — without requiring a cluster. Workflow: **stop → vzdump backup → transfer → restore → start**. The guest type (`lxc` / `qemu`) is detected automatically.

## Features

- Works for **LXC containers and QEMU VMs** — type is auto-detected
- **Four modes** depending on which hosts you specify (see below): remote→remote, push, pull, local clone
- No Proxmox cluster required — plain **SSH** is enough
- Streaming transfer (no intermediate file on the machine running the script), optional progress bar via `pv`
- Size verification after transfer
- Handles **unprivileged containers** correctly (dump directory permissions are fixed automatically)
- Safety checks: SSH connectivity, source ID exists, target ID free, target storage exists
- Automatic cleanup of temporary files on success **and** on failure
- Key=value arguments in any order, interactive prompts for missing credentials

## Modes

The side you omit runs on the **local node** (the machine executing the script):

| Arguments given | Mode | Behavior |
|---|---|---|
| `s=` and `d=` | remote → remote | Transfer between two remote nodes |
| only `d=` | push | Back up local guest, restore it on `d=` |
| only `s=` | pull | Back up guest on `s=`, restore it locally |
| none | local clone | Copy a guest to a new ID on the same node |

## Requirements

- Proxmox VE on all involved nodes (`vzdump`, `pct`/`qm`, `pvesm`)
- SSH access with root privileges on remote nodes
- `sshpass` on the executing machine (only for password authentication)
- `pv` (optional, shows a progress bar during transfer)
- Enough free space in `/var/tmp` on source and destination for the compressed backup

## Installation

```bash
wget https://raw.githubusercontent.com/sorglos-it/pve-transfer/main/pve-transfer.sh
chmod +x pve-transfer.sh
```

## Usage

```text
./pve-transfer.sh [s=<src-host>] [d=<dst-host>] oid=<source-id> nid=<target-id> st=<storage> [u=<user>] [p=<pass>]
```

### Parameters

| Key | Alias | Description |
|---|---|---|
| `s=` | `src=` | Source PVE host (omitted = local node) |
| `d=` | `dst=` | Destination PVE host (omitted = local node) |
| `oid=` | – | Source VMID / CTID |
| `nid=` | – | New VMID / CTID on the destination |
| `st=` | `storage=` | Target storage on the destination |
| `u=` | `user=` | SSH user (optional, prompted if a remote side is used) |
| `p=` | `pass=` | SSH password (optional, prompted if missing; empty = key auth) |

Argument order is arbitrary. `-h`, `-help`, `--help` or no arguments print the built-in help.

### Examples

```bash
# Remote -> remote: move guest 100 from pve-1 to pve-2 as 102
./pve-transfer.sh s=pve-1.example.com d=pve-2.example.com oid=100 nid=102 st=ssd_1tb u=root p=secret

# Push: copy local guest 100 to pve-2 as 102
./pve-transfer.sh d=pve-2.example.com oid=100 nid=102 st=ssd_1tb

# Pull: fetch guest 100 from pve-1 and restore it locally as 102
./pve-transfer.sh s=pve-1.example.com oid=100 nid=102 st=local-lvm

# Local clone: copy guest 100 to ID 110 on this node
./pve-transfer.sh oid=100 nid=110 st=local-lvm
```

## How it works

1. **Checks** — SSH connectivity, guest type detection, target ID free, target storage exists
2. **Stop** — graceful shutdown (120 s timeout), hard stop as fallback
3. **Backup** — `vzdump --mode stop --compress zstd` into a temporary directory
4. **Transfer** — archive is streamed source → destination through the executing machine (skipped for local clones)
5. **Restore** — `pct restore` / `qmrestore` with the new ID on the chosen storage
6. **Start** — the restored guest is started on the destination

## Notes & caveats

- **The source guest stays stopped** after a successful run. The backup preserves MAC addresses and IP configuration — running both copies simultaneously causes conflicts. Adjust the network config of the copy (`pct set` / `qm set`) before starting both.
- Passing `p=` on the command line exposes the password in the process list and shell history. Prefer the interactive prompt or SSH key authentication.
- In remote→remote mode the data is streamed **through the machine running the script** — consider its bandwidth, or run the script directly on one of the nodes.
- Exit codes: `0` = success, `1` = error, `2` = usage.

## Support

If this script saved you time, you can support further development:

[![Donate with PayPal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

## License

MIT
