# Changelog

## Unreleased – 2026-09-22

- **New download address.** The script moved to `apps/cli/pve-transfer.sh` and is now downloaded from
  `https://raw.githubusercontent.com/sorglos-it/pve-transfer/main/apps/cli/pve-transfer.sh`.
  The old address `https://raw.githubusercontent.com/sorglos-it/pve-transfer/main/pve-transfer.sh` no longer works.
  Version 1.0.0 stays available as a release download:
  `https://github.com/sorglos-it/pve-transfer/releases/download/v1.0.0/pve-transfer.sh`.
- Layout follows the project structure standard: script and `VERSION` in `apps/cli/`, new `CHANGELOG.md` and
  `.gitignore`.
- README rewritten: purpose, folder table, start in 3 steps, update.
- The script itself is unchanged.

## 1.0.0 – 2026-07-17

- First release: transfer or clone LXC containers and VMs between Proxmox VE nodes without a cluster – stop, vzdump,
  transfer, restore, start. Four modes: remote → remote, push, pull, local clone.
