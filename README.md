# pve-transfer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-89e051.svg)](#)
[![Platform](https://img.shields.io/badge/platform-Proxmox%20VE-e57000.svg)](#)
[![Donate](https://img.shields.io/badge/Donate-PayPal-00457C.svg?logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

Copies a container (LXC) or virtual machine (VM) from one Proxmox VE server to another – or to a new ID on the same
server. No cluster needed, SSH is enough. One command does it all: stop, back up, transfer, restore, start.

| Folder | Purpose | Language | Start | Build |
|---|---|---|---|---|
| `apps/cli` | Copy an LXC container or VM between Proxmox VE nodes, or clone it on one node | Bash | `./pve-transfer.sh …` | none |

## Start in 3 steps

1. **Download** the script in the shell of a Proxmox VE node (web interface: select the node → **Shell**):
   ```bash
   wget https://raw.githubusercontent.com/sorglos-it/pve-transfer/main/apps/cli/pve-transfer.sh
   ```
2. **Make it executable:**
   ```bash
   chmod +x pve-transfer.sh
   ```
3. **Run it** – for example, fetch guest `100` from `pve-1` and restore it on this node as `102` on storage `local-lvm`:
   ```bash
   ./pve-transfer.sh s=pve-1.example.com oid=100 nid=102 st=local-lvm
   ```
   It asks for the SSH user and password of `pve-1` (empty password = SSH key). Without arguments it shows its help.

## Modes

The side you leave out runs on the **local node** – the machine running the script:

| Arguments given | Mode | What happens |
|---|---|---|
| `s=` and `d=` | remote → remote | transfer between two remote nodes |
| only `d=` | push | back up the local guest, restore it on `d=` |
| only `s=` | pull | back up the guest on `s=`, restore it locally |
| none | local clone | copy a guest to a new ID on the same node |

Push, pull and local clone must run on a Proxmox VE node. Remote → remote also works from any other Linux machine
with SSH.

## Usage

```text
./pve-transfer.sh [s=<src-host>] [d=<dst-host>] oid=<source-id> nid=<target-id> st=<storage> [u=<user>] [p=<pass>]
```

| Key | Alias | Meaning |
|---|---|---|
| `s=` | `src=` | source node (left out = local node) |
| `d=` | `dst=` | destination node (left out = local node) |
| `oid=` | – | ID of the guest to copy (VMID / CTID) |
| `nid=` | – | new ID on the destination |
| `st=` | `storage=` | storage on the destination |
| `u=` | `user=` | SSH user (optional, asked for when a remote node is used, default `root`) |
| `p=` | `pass=` | SSH password (optional, asked for when missing, empty = SSH key) |

The order does not matter. `-h`, `-help`, `--help` or no arguments show the built-in help.

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

## What it does

1. **Checks** – SSH connection, guest exists and its type (LXC or VM), target ID is free, target storage exists.
   Disks marked `unused` are never part of a backup; the script warns about them.
2. **Stop** – shuts the guest down (up to 120 s), stops it hard if needed.
3. **Backup** – `vzdump --mode stop --compress zstd` into a temporary folder in `/var/tmp`. All disks and mount
   points are included: those excluded from backups are switched on for this one dump.
4. **Transfer** – streams the archive from source to destination through the machine running the script, nothing is
   stored there. The size is compared afterwards. A progress bar appears if `pv` is installed. Skipped for a local
   clone.
5. **Restore** – `pct restore` or `qmrestore` with the new ID on the chosen storage.
6. **Start** – starts the copy on the destination.

Unprivileged containers work without extra steps. Whether it succeeds or fails, the script removes its temporary
files and sets the backup settings of the disks back.

## Requirements

- Proxmox VE on all nodes involved (`vzdump`, `pct` / `qm`, `pvesm`)
- SSH access as root to the remote nodes
- `sshpass` on the machine running the script – only for password login
- `pv` – optional, shows a progress bar
- Enough free space in `/var/tmp` on source and destination for the compressed backup

## Good to know

- **The original guest stays stopped** after a successful run. The copy has the same MAC addresses and IP settings
  – running both at the same time causes conflicts. Change the network settings of the copy (`pct set` / `qm set`)
  before starting both.
- `p=` on the command line shows the password in the process list and shell history. Better: let the script ask, or
  use SSH keys.
- Remote → remote sends all data **through the machine running the script** – mind its bandwidth, or run the script
  on one of the nodes.
- Exit codes: `0` = success, `1` = error, `2` = usage.

## Update

Download again and overwrite the old file:

```bash
wget -O pve-transfer.sh https://raw.githubusercontent.com/sorglos-it/pve-transfer/main/apps/cli/pve-transfer.sh
```

The download address changed on 2026-09-22 – see [CHANGELOG](CHANGELOG.md).

## License

MIT – see [LICENSE](LICENSE).

## Donate via PayPal

If this script saved you time, you can support further development:

**[➡️ Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)**
