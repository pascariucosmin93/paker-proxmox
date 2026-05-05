#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "Usage: $0 <vmid> <vm-name> <image-path> <storage-pool> [bridge]" >&2
  exit 1
fi

VMID="$1"
VM_NAME="$2"
IMAGE_PATH="$3"
STORAGE_POOL="$4"
BRIDGE="${5:-vmbr0}"

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "Image not found: $IMAGE_PATH" >&2
  exit 1
fi

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VMID $VMID already exists. Remove it first or choose another VMID." >&2
  exit 1
fi

qm create "$VMID" \
  --name "$VM_NAME" \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-single \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0

qm importdisk "$VMID" "$IMAGE_PATH" "$STORAGE_POOL"
qm set "$VMID" --scsi0 "${STORAGE_POOL}:vm-${VMID}-disk-0"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --ide2 "${STORAGE_POOL}:cloudinit"
qm set "$VMID" --ipconfig0 ip=dhcp
qm set "$VMID" --ciuser ubuntu
qm template "$VMID"

echo "Created Proxmox cloud base template:"
echo "  VMID: ${VMID}"
echo "  Name: ${VM_NAME}"
