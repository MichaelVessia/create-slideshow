#!/usr/bin/env bash
set -euo pipefail

# Configuration
DURATION_PER_IMAGE=5

# Check for command line argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <directory_path>"
  echo "Example: $0 /media/username/drive/photos"
  echo "         $0 ~/Pictures"
  echo "         $0 ."
  exit 1
fi

# Get source directory from argument
SOURCE_DIR="$1"

# Verify directory exists
if [ ! -d "$SOURCE_DIR" ]; then
  echo "❌ Error: Directory '$SOURCE_DIR' does not exist"
  exit 1
fi

# Convert to absolute path
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)

# Set up working directory and output file
WORK_DIR="$HOME/slideshow_temp_$$"
OUTPUT_FILE="$HOME/slideshow_$(date +%Y%m%d_%H%M%S).mp4"

# Safety check
echo "🔒 This script is NON-DESTRUCTIVE"
echo "📁 Source: $SOURCE_DIR (read-only)"
echo "🔧 Working in: $WORK_DIR (temporary)"
echo "💾 Output to: $OUTPUT_FILE"
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

# Create working directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit 1

# Copy images
echo "📋 Finding and randomizing images..."
mapfile -d '' files < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 | shuf -z)

if [ ${#files[@]} -eq 0 ]; then
  echo "❌ No images found in $SOURCE_DIR"
  cd "$HOME" || exit 1
  rmdir "$WORK_DIR"
  exit 1
fi

echo "📷 Found ${#files[@]} images"
echo "📋 Copying and auto-rotating images based on EXIF..."

# Check if exiftool is available
if command -v exiftool &>/dev/null; then
  echo "✅ Using exiftool for EXIF-based rotation"
  for i in "${!files[@]}"; do
    printf "\rProcessing: %d/%d" $((i + 1)) ${#files[@]}
    output_name="$(printf "%04d" $((i + 1))).jpg"
    cp "${files[$i]}" "$output_name"
    # Auto-rotate based on EXIF and remove orientation tag
    exiftool -overwrite_original -Orientation= -n -q "$output_name"
  done
elif command -v magick &>/dev/null; then
  echo "✅ Using ImageMagick v7 for EXIF-based rotation"
  for i in "${!files[@]}"; do
    printf "\rProcessing: %d/%d" $((i + 1)) ${#files[@]}
    output_name="$(printf "%04d" $((i + 1))).jpg"
    # Auto-orient images based on EXIF data using ImageMagick v7
    magick "${files[$i]}" -auto-orient "$output_name"
  done
elif command -v convert &>/dev/null; then
  echo "✅ Using ImageMagick v6 for EXIF-based rotation"
  for i in "${!files[@]}"; do
    printf "\rProcessing: %d/%d" $((i + 1)) ${#files[@]}
    output_name="$(printf "%04d" $((i + 1))).jpg"
    # Auto-orient images based on EXIF data
    convert "${files[$i]}" -auto-orient "$output_name" 2>/dev/null || convert "${files[$i]}" -auto-orient "$output_name"
  done
else
  echo "⚠️  Neither exiftool nor ImageMagick found. Installing one is recommended."
  echo "   Install with: sudo apt install exiftool  OR  sudo apt install imagemagick"
  echo "   Continuing without auto-rotation..."
  for i in "${!files[@]}"; do
    printf "\rCopying: %d/%d" $((i + 1)) ${#files[@]}
    cp "${files[$i]}" "$(printf "%04d" $((i + 1))).jpg"
  done
fi
echo ""

# Create slideshow using concat demuxer for precise timing
echo "🎬 Creating slideshow..."
echo "⏱️  Each image will display for $DURATION_PER_IMAGE seconds"

# Create input file list with durations
for img in *.jpg; do
  echo "file '$img'"
  echo "duration $DURATION_PER_IMAGE"
done >input.txt

# Add last image again (required by concat)
last_image=$(find . -maxdepth 1 -name "*.jpg" -print0 | sort -zV | tail -z -n1 | tr -d '\0')
echo "file '$last_image'" >>input.txt

# Create video using concat
# Note: We're not using transpose filter anymore since images are pre-rotated
ffmpeg -loglevel warning -stats \
  -f concat -safe 0 -i input.txt \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease:eval=frame,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -y "$OUTPUT_FILE" 2>&1 | grep -v "deprecated pixel format"

# Cleanup
echo "🧹 Cleaning up temporary files..."
cd "$HOME" || exit 1
rm -rf "$WORK_DIR"

duration_seconds=$((${#files[@]} * DURATION_PER_IMAGE))
duration_formatted=$(printf '%02d:%02d' $((duration_seconds / 60)) $((duration_seconds % 60)))

echo "✅ Complete! Slideshow saved as: $OUTPUT_FILE"
echo "📁 Original images in $SOURCE_DIR are untouched"
echo "⏱️  Duration: $duration_formatted ($duration_seconds seconds)"
