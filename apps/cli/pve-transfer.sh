#!/bin/bash
# ============================================================================
# pve-transfer.sh
# Transfer an LXC container or VM between PVE nodes (stop -> vzdump ->
# transfer -> restore -> start). Type (lxc/qemu) is auto-detected.
# All disks / mount points are included: backup flags are enabled
# temporarily if needed and reverted afterwards.
# Any side without a host runs on the LOCAL node:
#   s= + d= set : remote -> remote
#   only d= set : local  -> remote   (push local guest to d=)
#   only s= set : remote -> local    (pull guest from s= to this node)
#   none set    : local  -> local    (copy to new ID on this node)
#
# Usage:    ./pve-transfer.sh [s=<src-host>] [d=<dst-host>] oid=<source-id> nid=<target-id> st=<storage> [u=<user>] [p=<pass>]
# Remote:   ./pve-transfer.sh s=pve-1.example.com d=pve-2.example.com oid=100 nid=102 st=ssd_1tb u=root p=secret
# Push:     ./pve-transfer.sh d=pve-2.example.com oid=100 nid=102 st=ssd_1tb
# Pull:     ./pve-transfer.sh s=pve-1.example.com oid=100 nid=102 st=local-lvm
# Local:    ./pve-transfer.sh oid=100 nid=110 st=local-lvm
# Note:     Argument order is arbitrary. Aliases: src= dst= storage= user= pass=
#           No arguments or -h/-help/--help prints usage info.
#
# Dependencies: ssh with root privileges on remote nodes,
#               sshpass (password auth only), pv (optional, progress bar)
# Exit codes:   0=OK, 1=error, 2=usage
# ============================================================================
set -euo pipefail

# --- Configuration ----------------------------------------------------------
TMPBASE="/var/tmp"        # backup staging path on source and destination
SHUTDOWN_TIMEOUT=120      # seconds before hard stop

# --- Functions ---------------------------------------------------------------
die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo "" ; echo "== $* =="; }
usage() {
    echo "Usage:   $0 [s=<src-host>] [d=<dst-host>] oid=<source-id> nid=<target-id> st=<storage> [u=<user>] [p=<pass>]"
    echo ""
    echo "Transfers an LXC container or VM between PVE nodes:"
    echo "stop -> vzdump backup -> transfer -> restore -> start. Type is auto-detected."
    echo "All disks / mount points are included (backup flags enabled temporarily)."
    echo ""
    echo "Any side without a host runs on the LOCAL node:"
    echo "  s= + d= set : remote -> remote"
    echo "  only d= set : local  -> remote   (push local guest to d=)"
    echo "  only s= set : remote -> local    (pull guest from s= to this node)"
    echo "  none set    : local  -> local    (copy to new ID on this node)"
    echo ""
    echo "Examples:"
    echo "  $0 s=pve-1.example.com d=pve-2.example.com oid=100 nid=102 st=ssd_1tb u=root p=secret"
    echo "  $0 d=pve-2.example.com oid=100 nid=102 st=ssd_1tb"
    echo "  $0 s=pve-1.example.com oid=100 nid=102 st=local-lvm"
    echo "  $0 oid=100 nid=110 st=local-lvm"
    echo ""
    echo "Parameters (order is arbitrary):"
    echo "  s=   | src=      source PVE host       (omitted = local node)"
    echo "  d=   | dst=      destination PVE host  (omitted = local node)"
    echo "  oid=             source VMID/CTID"
    echo "  nid=             new VMID/CTID on destination"
    echo "  st=  | storage=  target storage on destination"
    echo "  u=   | user=     SSH user      (optional, prompted if a remote side is used)"
    echo "  p=   | pass=     SSH password  (optional, prompted if missing, empty = key auth)"
    echo ""
    echo "  -h | -help | --help | no arguments: show this help"
    exit 2
}

# --- Validation: arguments ---------------------------------------------------
SRC=""; DST=""; SID=""; DID=""; STOR=""; SSHUSER=""; SSHPW=""

[ $# -ge 1 ] || usage

for arg in "$@"; do
    case "$arg" in
        s=*|src=*)       SRC="${arg#*=}" ;;
        d=*|dst=*)       DST="${arg#*=}" ;;
        oid=*)           SID="${arg#*=}" ;;
        nid=*)           DID="${arg#*=}" ;;
        st=*|storage=*)  STOR="${arg#*=}" ;;
        u=*|user=*)      SSHUSER="${arg#*=}" ;;
        p=*|pass=*)      SSHPW="${arg#*=}" ;;
        -h|-help|--help) usage ;;
        *)               die "Unknown parameter: '$arg' (-h for help)" ;;
    esac
done

[ -n "$SID" ]  || die "oid=<source-id> missing"
[ -n "$DID" ]  || die "nid=<target-id> missing"
[ -n "$STOR" ] || die "st=<storage> missing"

echo "$SID" | grep -qE '^[0-9]+$' || die "Source ID '$SID' is not a number"
echo "$DID" | grep -qE '^[0-9]+$' || die "Target ID '$DID' is not a number"

# --- Mode setup: each side is remote (host given) or local (host omitted) ----
SRC_REMOTE=1; DST_REMOTE=1
[ -n "$SRC" ] || { SRC_REMOTE=0; SRC="localhost"; }
[ -n "$DST" ] || { DST_REMOTE=0; DST="localhost"; }

if [ $SRC_REMOTE -eq 0 ] && [ $DST_REMOTE -eq 0 ]; then FULLY_LOCAL=1; else FULLY_LOCAL=0; fi

if [ $SRC_REMOTE -eq 0 ] || [ $DST_REMOTE -eq 0 ]; then
    command -v vzdump >/dev/null || die "Local side requires running on a PVE node (vzdump not found)"
fi
if [ $FULLY_LOCAL -eq 1 ] && [ "$SID" = "$DID" ]; then
    die "oid and nid must differ when copying on the same node"
fi

if [ $SRC_REMOTE -eq 1 ] || [ $DST_REMOTE -eq 1 ]; then
    [ -n "$SSHUSER" ] || { read -rp "SSH user [root]: " SSHUSER; SSHUSER="${SSHUSER:-root}"; }
    [ -n "$SSHPW" ]   || { read -rsp "SSH password (empty = key auth): " SSHPW; echo ""; }

    SSHOPT=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
    if [ -n "$SSHPW" ]; then
        command -v sshpass >/dev/null || die "sshpass not found (apt install sshpass)"
        RS() { sshpass -p "$SSHPW" ssh "${SSHOPT[@]}" "$SSHUSER@$1" "$2"; }
    else
        RS() { ssh "${SSHOPT[@]}" "$SSHUSER@$1" "$2"; }
    fi
fi

if [ $SRC_REMOTE -eq 1 ]; then S() { RS "$SRC" "$1"; }; else S() { bash -c "$1"; }; fi
if [ $DST_REMOTE -eq 1 ]; then D() { RS "$DST" "$1"; }; else D() { bash -c "$1"; }; fi

side() { [ "$1" -eq 1 ] && echo "remote" || echo "local"; }

# --- Backup flag handling (include ALL disks / mount points) ------------------
# vzdump skips VM disks with backup=0 and LXC mount points without backup=1.
# Flags are enabled temporarily before the dump and reverted afterwards.
REVERT_KEYS=(); REVERT_VALS=()

enable_backup_flags() {
    local excl line key val newval
    if [ "$TYPE" = "qemu" ]; then
        excl=$(S "$CMD config $SID" | grep -E '^(ide|sata|scsi|virtio|efidisk|tpmstate)[0-9]+:' \
               | grep -v 'media=cdrom' | grep 'backup=0' || true)
    else
        excl=$(S "$CMD config $SID" | grep -E '^mp[0-9]+:' | grep -v 'backup=1' || true)
    fi
    [ -n "$excl" ] || return 0

    echo "Disks/mount points excluded from backup - enabling temporarily:"
    local lines=()
    mapfile -t lines <<< "$excl"
    for line in "${lines[@]}"; do
        [ -n "$line" ] || continue
        key="${line%%:*}"
        val="${line#*: }"
        if [ "$TYPE" = "qemu" ]; then
            newval=$(echo "$val" | sed -E 's/,?backup=0//')
        else
            newval="$(echo "$val" | sed -E 's/,?backup=0//'),backup=1"
        fi
        S "$CMD set $SID -$key '$newval'"
        REVERT_KEYS+=("$key"); REVERT_VALS+=("$val")
        echo "  $key: backup enabled"
    done
}

revert_backup_flags() {
    local i
    [ ${#REVERT_KEYS[@]} -gt 0 ] || return 0
    for i in "${!REVERT_KEYS[@]}"; do
        S "$CMD set $SID -${REVERT_KEYS[$i]} '${REVERT_VALS[$i]}'" || true
    done
    echo "Backup flags reverted to original values"
    REVERT_KEYS=(); REVERT_VALS=()
}

# --- Cleanup -----------------------------------------------------------------
TMPDIR_SRC=""; ARCNAME=""
cleanup() {
    revert_backup_flags 2>/dev/null || true
    [ -n "$TMPDIR_SRC" ] && S "rm -rf '$TMPDIR_SRC'" 2>/dev/null || true
    if [ $FULLY_LOCAL -eq 0 ] && [ -n "$ARCNAME" ]; then
        D "rm -f '$TMPBASE/$ARCNAME'" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- 1/6 Checks --------------------------------------------------------------
step "1/6 Checks (source: $(side $SRC_REMOTE) $SRC, dest: $(side $DST_REMOTE) $DST)"
if [ $SRC_REMOTE -eq 1 ]; then S "true" || die "No SSH connection to $SRC"; fi
if [ $DST_REMOTE -eq 1 ]; then D "true" || die "No SSH connection to $DST"; fi

if   S "test -e /etc/pve/lxc/$SID.conf";         then TYPE="lxc";  CMD="pct"
elif S "test -e /etc/pve/qemu-server/$SID.conf"; then TYPE="qemu"; CMD="qm"
else die "ID $SID not found on $SRC"; fi
echo "Type: $TYPE"

D "test ! -e /etc/pve/lxc/$DID.conf && test ! -e /etc/pve/qemu-server/$DID.conf" \
    || die "ID $DID already in use on $DST"
D "pvesm status --storage '$STOR' >/dev/null" \
    || die "Storage '$STOR' not found on $DST"

UNUSED=$(S "$CMD config $SID" | grep -E '^unused[0-9]+:' || true)
if [ -n "$UNUSED" ]; then
    echo "WARNING: 'unused' disks are never included in backups and will NOT be transferred:"
    echo "$UNUSED" | sed 's/^/  /'
fi

# --- 2/6 Stop ----------------------------------------------------------------
step "2/6 Stopping $TYPE $SID on $SRC"
if S "$CMD status $SID" | grep -q running; then
    S "$CMD shutdown $SID --timeout $SHUTDOWN_TIMEOUT" || S "$CMD stop $SID"
    echo "stopped"
else
    echo "already stopped"
fi

# --- 3/6 Backup --------------------------------------------------------------
step "3/6 Backup (vzdump, all disks)"
enable_backup_flags
TMPDIR_SRC=$(S "mktemp -d $TMPBASE/pvetransfer.XXXXXX")
S "chmod 755 '$TMPDIR_SRC'"   # unprivileged CT: vzdump runs tar as mapped uid 100000, needs to traverse dumpdir (mktemp default 700 blocks it)
S "vzdump $SID --dumpdir '$TMPDIR_SRC' --mode stop --compress zstd"
revert_backup_flags
ARCPATH=$(S "ls $TMPDIR_SRC/*.zst" | head -n1)
[ -n "$ARCPATH" ] || die "No backup archive found"
ARCNAME=$(basename "$ARCPATH")
SIZE=$(S "stat -c%s '$ARCPATH'")
echo "Archive: $ARCNAME ($((SIZE / 1024 / 1024)) MB)"

# --- 4/6 Transfer ------------------------------------------------------------
step "4/6 Transfer $SRC -> $DST"
if [ $FULLY_LOCAL -eq 1 ]; then
    RESTORE_PATH="$ARCPATH"
    echo "skipped (same node, archive used in place)"
else
    if command -v pv >/dev/null; then
        S "cat '$ARCPATH'" | pv -s "$SIZE" | D "cat > '$TMPBASE/$ARCNAME'"
    else
        S "cat '$ARCPATH'" | D "cat > '$TMPBASE/$ARCNAME'"
    fi
    [ "$(D "stat -c%s '$TMPBASE/$ARCNAME'")" = "$SIZE" ] || die "Transfer incomplete (size mismatch)"
    RESTORE_PATH="$TMPBASE/$ARCNAME"
    echo "OK, size verified"
fi

# --- 5/6 Restore -------------------------------------------------------------
step "5/6 Restore as $DID on $DST (storage: $STOR)"
if [ "$TYPE" = "lxc" ]; then
    D "pct restore $DID '$RESTORE_PATH' --storage '$STOR'"
else
    D "qmrestore '$RESTORE_PATH' $DID --storage '$STOR'"
fi

# --- 6/6 Start ---------------------------------------------------------------
step "6/6 Starting $DID"
D "$CMD start $DID"
D "$CMD status $DID"

echo ""
echo "DONE: $TYPE $SID ($SRC) -> $DID ($DST)."
echo "Note: source $SID stays stopped (avoid MAC/IP conflicts). Temp files removed."
