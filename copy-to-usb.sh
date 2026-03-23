#!/usr/bin/env bash
set -euo pipefail

# Configuration defaults
DEVICE=""
LABEL=""
SKIP_CONFIRM=false

usage() {
  echo "Usage: $0 <file> [options]"
  echo ""
  echo "Wipe a USB drive (FAT32) and copy a file onto it."
  echo ""
  echo "Options:"
  echo "  -d, --device <dev>   Override device (skip auto-detect)"
  echo "  -l, --label <name>   Volume label (default: derived from filename)"
  echo "  -y, --yes            Skip confirmation prompt"
  echo "  -h, --help           Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 slideshow.mp4"
  echo "  $0 slideshow.mp4 -d /dev/sda"
  echo "  $0 slideshow.mp4 -l MONTAGE -y"
  exit 1
}

# Parse arguments
INPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--device)
      DEVICE="$2"
      shift 2
      ;;
    -l|--label)
      LABEL="$2"
      shift 2
      ;;
    -y|--yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      if [[ -z "$INPUT_FILE" ]]; then
        INPUT_FILE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "Error: No file specified"
  usage
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: File not found: $INPUT_FILE"
  exit 1
fi

# Derive label from filename if not provided
if [[ -z "$LABEL" ]]; then
  basename_no_ext="${INPUT_FILE##*/}"
  basename_no_ext="${basename_no_ext%.*}"
  # Uppercase, strip non-alphanumeric (FAT32 label rules), truncate to 11 chars
  LABEL=$(echo "$basename_no_ext" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_' | cut -c1-11)
  if [[ -z "$LABEL" ]]; then
    LABEL="USB"
  fi
fi

# Device selection
detect_usb_devices() {
  lsblk -dnpo NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -i 'usb' || true
}

if [[ -z "$DEVICE" ]]; then
  mapfile -t usb_lines < <(detect_usb_devices)

  if [[ ${#usb_lines[@]} -eq 0 || -z "${usb_lines[0]}" ]]; then
    echo "Error: No removable USB devices found"
    echo "Insert a USB drive or use --device to specify one manually."
    exit 1
  fi

  if [[ ${#usb_lines[@]} -eq 1 ]]; then
    DEVICE=$(echo "${usb_lines[0]}" | awk '{print $1}')
    echo "Found USB device:"
    echo "  ${usb_lines[0]}"
  else
    echo "Multiple USB devices found:"
    for i in "${!usb_lines[@]}"; do
      echo "  $((i + 1)). ${usb_lines[$i]}"
    done
    echo ""
    read -r -p "Select device [1-${#usb_lines[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#usb_lines[@]} )); then
      echo "Error: Invalid selection"
      exit 1
    fi
    DEVICE=$(echo "${usb_lines[$((choice - 1))]}" | awk '{print $1}')
  fi
fi

# Resolve partition name (e.g. /dev/sda -> /dev/sda1)
PARTITION="${DEVICE}1"

# Get device info for confirmation
DEVICE_INFO=$(lsblk -dnpo NAME,SIZE,MODEL "$DEVICE" 2>/dev/null || echo "$DEVICE (unknown size)")

# Safety prompt
if [[ "$SKIP_CONFIRM" != true ]]; then
  echo ""
  echo "WARNING: This will ERASE ALL DATA on the device!"
  echo "  Device: $DEVICE_INFO"
  echo "  Label:  $LABEL"
  echo "  File:   $INPUT_FILE"
  echo ""
  read -r -p "Press Enter to proceed or Ctrl+C to cancel..."
fi

# Cleanup trap: unmount on error
MOUNTPOINT=""
cleanup() {
  if [[ -n "$MOUNTPOINT" ]]; then
    sudo umount "$MOUNTPOINT" 2>/dev/null || true
    rmdir "$MOUNTPOINT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Unmount any existing partitions on the device
echo "Unmounting existing partitions..."
for part in "${DEVICE}"*; do
  sudo umount "$part" 2>/dev/null || true
done

# Wipe and format
echo "Creating partition table on $DEVICE..."
sudo nix run nixpkgs#parted -- "$DEVICE" mklabel msdos
sudo nix run nixpkgs#parted -- "$DEVICE" mkpart primary fat32 1MiB 100%

echo "Formatting $PARTITION as FAT32 (label: $LABEL)..."
sudo mkfs.vfat -F 32 -n "$LABEL" "$PARTITION"

# Mount, copy, unmount
MOUNTPOINT=$(mktemp -d /tmp/usb-copy.XXXXXX)
echo "Mounting $PARTITION at $MOUNTPOINT..."
sudo mount "$PARTITION" "$MOUNTPOINT"

echo "Copying $(basename "$INPUT_FILE")..."
sudo cp "$INPUT_FILE" "$MOUNTPOINT/"

echo "Unmounting..."
sudo umount "$MOUNTPOINT"
rmdir "$MOUNTPOINT"
MOUNTPOINT=""

echo "Done! Safe to remove $DEVICE."
