#!/usr/bin/env bash
set -euo pipefail

# Configuration
DURATION_PER_IMAGE=5
MUSIC_INPUT=""
LOOP_AUDIO=false
EXTEND_TO_AUDIO=false
AUDIO_FADE_DURATION=3
AUDIO_CACHE_DIR="$HOME/.cache/create-slideshow/audio"

# Function to display usage
usage() {
  echo "Usage: $0 <directory_path> [options]"
  echo ""
  echo "Options:"
  echo "  -m, --music <input>      YouTube URL(s), video ID(s), playlist file, or local audio file"
  echo "  --loop-audio             Loop audio if shorter than video"
  echo "  --extend-to-audio        Extend slideshow to match audio duration"
  echo "  --fade-duration <sec>    Audio fade duration in seconds (default: 3)"
  echo "  --clear-cache            Clear audio cache and exit"
  echo "  --show-cache             Show cache status and exit"
  echo ""
  echo "Examples:"
  echo "  $0 ~/Pictures"
  echo "  $0 ~/Pictures -m playlist.txt"
  echo "  $0 ~/Pictures -m \"https://youtube.com/watch?v=dQw4w9WgXcQ\""
  echo "  $0 ~/Pictures -m background.mp3 --loop-audio"
  exit 1
}

# Parse command line arguments
SOURCE_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--music)
      MUSIC_INPUT="$2"
      shift 2
      ;;
    --loop-audio)
      LOOP_AUDIO=true
      shift
      ;;
    --extend-to-audio)
      EXTEND_TO_AUDIO=true
      shift
      ;;
    --fade-duration)
      AUDIO_FADE_DURATION="$2"
      shift 2
      ;;
    --clear-cache)
      clear_cache
      exit 0
      ;;
    --show-cache)
      show_cache_status
      exit 0
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      if [ -z "$SOURCE_DIR" ]; then
        SOURCE_DIR="$1"
      fi
      shift
      ;;
  esac
done

# Music processing functions
check_ytdlp() {
  if ! command -v yt-dlp &>/dev/null; then
    echo "⚠️  yt-dlp is not installed. Music features require yt-dlp."
    echo "   Install with one of these methods:"
    echo "   - pip install yt-dlp"
    echo "   - sudo apt install yt-dlp  (Ubuntu/Debian)"
    echo "   - brew install yt-dlp      (macOS)"
    echo ""
    echo "   Continuing without music..."
    return 1
  fi
  return 0
}

# Read URLs from a playlist file
read_music_file() {
  local file="$1"
  local -a urls=()
  
  if [ ! -f "$file" ]; then
    echo "❌ Error: Music file '$file' not found"
    return 1
  fi
  
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Trim whitespace
    line=$(echo "$line" | xargs)
    [ -n "$line" ] && urls+=("$line")
  done < "$file"
  
  if [ ${#urls[@]} -eq 0 ]; then
    echo "❌ Error: No valid URLs found in '$file'" >&2
    return 1
  fi
  
  printf '%s\n' "${urls[@]}"
}

# Get cache filename for a URL
get_cache_filename() {
  local url="$1"
  local video_id
  
  # Extract video ID from various YouTube URL formats
  if [[ "$url" =~ youtube\.com/watch\?v=([a-zA-Z0-9_-]{11}) ]] || \
     [[ "$url" =~ youtu\.be/([a-zA-Z0-9_-]{11}) ]] || \
     [[ "$url" =~ ^([a-zA-Z0-9_-]{11})$ ]]; then
    video_id="${BASH_REMATCH[1]}"
  else
    # Fallback: use hash of URL for non-YouTube or unrecognized URLs
    video_id=$(echo -n "$url" | sha256sum | cut -d' ' -f1 | head -c 11)
  fi
  
  echo "$AUDIO_CACHE_DIR/${video_id}.mp3"
}

# Show cache status
show_cache_status() {
  if [[ ! -d "$AUDIO_CACHE_DIR" ]]; then
    echo "Audio cache directory does not exist: $AUDIO_CACHE_DIR"
    return 0
  fi
  
  local file_count
  local total_size
  file_count=$(find "$AUDIO_CACHE_DIR" -name "*.mp3" | wc -l)
  total_size=$(du -sh "$AUDIO_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
  
  echo "Audio cache location: $AUDIO_CACHE_DIR"
  echo "Cached files: $file_count"
  echo "Total size: $total_size"
  
  if [[ $file_count -gt 0 ]]; then
    echo ""
    echo "Recent files:"
    find "$AUDIO_CACHE_DIR" -name "*.mp3" -exec ls -lh {} \; | sort -k6,7 | tail -5 | while read -r line; do
      echo "  $line"
    done
  fi
}

# Clear audio cache
clear_cache() {
  if [[ -d "$AUDIO_CACHE_DIR" ]]; then
    local file_count
    file_count=$(find "$AUDIO_CACHE_DIR" -name "*.mp3" | wc -l)
    if [[ $file_count -gt 0 ]]; then
      echo "Clearing $file_count cached audio files from $AUDIO_CACHE_DIR"
      rm -f "$AUDIO_CACHE_DIR"/*.mp3
      echo "Cache cleared."
    else
      echo "Cache is already empty."
    fi
  else
    echo "Cache directory does not exist."
  fi
}

# Download audio from YouTube URL
download_audio() {
  local url="$1"
  local output_file="$2"
  local cache_file
  
  # Create cache directory if it doesn't exist
  mkdir -p "$AUDIO_CACHE_DIR"
  
  # Get cache filename
  cache_file=$(get_cache_filename "$url")
  
  # Check if file exists in cache
  if [[ -f "$cache_file" ]]; then
    echo "📦 Using cached audio: $(basename "$cache_file")" >&2
    cp "$cache_file" "$output_file"
    return 0
  fi
  
  echo "📥 Downloading audio from: $url" >&2
  
  if yt-dlp -x \
    --audio-format mp3 \
    --audio-quality 0 \
    --no-playlist \
    --quiet \
    --progress \
    -o "$cache_file" \
    "$url" >/dev/null; then
    echo "✅ Downloaded successfully" >&2
    # Copy from cache to work directory
    cp "$cache_file" "$output_file"
    return 0
  else
    echo "❌ Failed to download audio from: $url" >&2
    return 1
  fi
}

# Process music input and download all tracks
process_music() {
  local input="$1"
  local work_dir="$2"
  local -a urls=()
  local -a audio_files=()
  
  # Determine input type
  if [ -f "$input" ]; then
    if [[ "$input" =~ \.(mp3|wav|m4a|aac|ogg|flac)$ ]]; then
      # It's a local audio file
      echo "🎵 Using local audio file: $input" >&2
      cp "$input" "$work_dir/audio_001.mp3"
      echo "$work_dir/audio_001.mp3"
      return 0
    else
      # It's a playlist file
      echo "📄 Reading playlist from: $input" >&2
      mapfile -t urls < <(read_music_file "$input")
      [ ${#urls[@]} -eq 0 ] && return 1
    fi
  elif [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
    # It's a URL or video ID (single or comma-separated)
    IFS=',' read -ra urls <<< "$input"
  else
    echo "❌ Error: Invalid music input: $input" >&2
    return 1
  fi
  
  # Download all audio tracks
  local count=1
  for url in "${urls[@]}"; do
    local output_file="$work_dir/audio_$(printf "%03d" $count).mp3"
    
    # Convert video ID to full URL if needed
    if [[ "$url" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
      url="https://youtube.com/watch?v=$url"
    fi
    
    if download_audio "$url" "$output_file"; then
      audio_files+=("$output_file")
      ((count++))
    fi
  done
  
  if [ ${#audio_files[@]} -eq 0 ]; then
    echo "❌ Error: No audio files were successfully downloaded" >&2
    return 1
  fi
  
  # Return list of downloaded audio files
  printf '%s\n' "${audio_files[@]}"
}

# Concatenate multiple audio files into one
concatenate_audio() {
  local work_dir="$1"
  shift
  local -a audio_files=("$@")
  local concat_file="$work_dir/concat_list.txt"
  local output_file="$work_dir/combined_audio.mp3"
  
  if [ ${#audio_files[@]} -eq 1 ]; then
    # Only one file, just rename it
    mv "${audio_files[0]}" "$output_file"
    echo "$output_file"
    return 0
  fi
  
  echo "🎵 Combining ${#audio_files[@]} audio tracks..." >&2
  
  # Create concat file for ffmpeg
  > "$concat_file"
  for file in "${audio_files[@]}"; do
    echo "file '$file'" >> "$concat_file"
  done
  
  # Concatenate audio files
  if ffmpeg -f concat -safe 0 -i "$concat_file" -c copy "$output_file" -y -loglevel error; then
    echo "✅ Audio tracks combined successfully" >&2
    # Clean up individual files
    rm -f "${audio_files[@]}" "$concat_file"
    echo "$output_file"
    return 0
  else
    echo "❌ Failed to combine audio tracks"
    return 1
  fi
}

# Get audio duration in seconds
get_audio_duration() {
  local audio_file="$1"
  ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null | cut -d. -f1
}

# Check for required directory argument
if [ -z "$SOURCE_DIR" ]; then
  echo "Error: No directory specified"
  usage
fi

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

# Process music if requested
AUDIO_FILE=""
AUDIO_DURATION=0
VIDEO_DURATION=0

if [ -n "$MUSIC_INPUT" ]; then
  echo ""
  echo "🎵 Processing music..."
  
  # Check for yt-dlp if needed
  if [[ ! -f "$MUSIC_INPUT" ]] || [[ ! "$MUSIC_INPUT" =~ \.(mp3|wav|m4a|aac|ogg|flac)$ ]]; then
    if ! check_ytdlp; then
      MUSIC_INPUT=""  # Clear music input if yt-dlp not available
    fi
  fi
  
  if [ -n "$MUSIC_INPUT" ]; then
    # Process and download music
    mapfile -t audio_files < <(process_music "$MUSIC_INPUT" "$WORK_DIR")
    
    if [ ${#audio_files[@]} -gt 0 ]; then
      # Concatenate if multiple files
      AUDIO_FILE=$(concatenate_audio "$WORK_DIR" "${audio_files[@]}")
      
      if [ -f "$AUDIO_FILE" ]; then
        # Get audio duration
        AUDIO_DURATION=$(get_audio_duration "$AUDIO_FILE")
        echo "🎵 Audio duration: ${AUDIO_DURATION}s"
      fi
    fi
  fi
  echo ""
fi

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

# Calculate video duration
VIDEO_DURATION=$((${#files[@]} * DURATION_PER_IMAGE))
echo "📹 Video duration: ${VIDEO_DURATION}s"

# Adjust duration if extending to audio
if [ -n "$AUDIO_FILE" ] && [ "$EXTEND_TO_AUDIO" = true ] && [ $AUDIO_DURATION -gt $VIDEO_DURATION ]; then
  echo "🎵 Extending slideshow to match audio duration: ${AUDIO_DURATION}s"
  # Calculate new duration per image
  DURATION_PER_IMAGE=$(( (AUDIO_DURATION + ${#files[@]} - 1) / ${#files[@]} ))
  VIDEO_DURATION=$((${#files[@]} * DURATION_PER_IMAGE))
  echo "⏱️  Adjusted duration per image: $DURATION_PER_IMAGE seconds"
fi

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
# Build FFmpeg command based on whether we have audio
if [ -n "$AUDIO_FILE" ]; then
  echo "🎵 Adding background music to slideshow..."
  
  # Build audio filter based on options
  AUDIO_FILTER=""
  
  # Handle audio duration vs video duration
  if [ "$LOOP_AUDIO" = true ] && [ $AUDIO_DURATION -lt $VIDEO_DURATION ]; then
    # Loop audio to match video duration
    LOOP_COUNT=$(( (VIDEO_DURATION + AUDIO_DURATION - 1) / AUDIO_DURATION ))
    echo "🔁 Looping audio $LOOP_COUNT times to match video duration"
    AUDIO_FILTER="aloop=loop=$((LOOP_COUNT - 1)):size=$((AUDIO_DURATION * 44100))"
  fi
  
  # Add fade out if audio is longer than video
  if [ $AUDIO_DURATION -gt $VIDEO_DURATION ]; then
    FADE_START=$(( VIDEO_DURATION - AUDIO_FADE_DURATION ))
    if [ -n "$AUDIO_FILTER" ]; then
      AUDIO_FILTER="${AUDIO_FILTER},afade=t=out:st=$FADE_START:d=$AUDIO_FADE_DURATION"
    else
      AUDIO_FILTER="afade=t=out:st=$FADE_START:d=$AUDIO_FADE_DURATION"
    fi
    echo "🎵 Adding ${AUDIO_FADE_DURATION}s fade out to audio"
  fi
  
  # Build final FFmpeg command with audio
  if [ -f "$AUDIO_FILE" ]; then
    if [ -n "$AUDIO_FILTER" ]; then
      ffmpeg -loglevel warning -stats \
        -f concat -safe 0 -i input.txt \
        -i "$AUDIO_FILE" \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease:eval=frame,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
        -af "$AUDIO_FILTER" \
        -c:v libx264 \
        -c:a aac -b:a 192k \
        -pix_fmt yuv420p \
        -t "$VIDEO_DURATION" \
        -y "$OUTPUT_FILE" 2>&1 | grep -v "deprecated pixel format"
    else
      ffmpeg -loglevel warning -stats \
        -f concat -safe 0 -i input.txt \
        -i "$AUDIO_FILE" \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease:eval=frame,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
        -c:v libx264 \
        -c:a aac -b:a 192k \
        -pix_fmt yuv420p \
        -t "$VIDEO_DURATION" \
        -y "$OUTPUT_FILE" 2>&1 | grep -v "deprecated pixel format"
    fi
  else
    echo "⚠️  Audio file not found: $AUDIO_FILE"
    echo "🎬 Creating slideshow without audio..."
    ffmpeg -loglevel warning -stats \
      -f concat -safe 0 -i input.txt \
      -vf "scale=1920:1080:force_original_aspect_ratio=decrease:eval=frame,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
      -c:v libx264 \
      -pix_fmt yuv420p \
      -y "$OUTPUT_FILE" 2>&1 | grep -v "deprecated pixel format"
  fi
else
  # Create video without audio (original behavior)
  ffmpeg -loglevel warning -stats \
    -f concat -safe 0 -i input.txt \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease:eval=frame,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
    -c:v libx264 \
    -pix_fmt yuv420p \
    -y "$OUTPUT_FILE" 2>&1 | grep -v "deprecated pixel format"
fi

# Cleanup
echo "🧹 Cleaning up temporary files..."
cd "$HOME" || exit 1
rm -rf "$WORK_DIR"

duration_seconds=$((${#files[@]} * DURATION_PER_IMAGE))
duration_formatted=$(printf '%02d:%02d' $((duration_seconds / 60)) $((duration_seconds % 60)))

echo "✅ Complete! Slideshow saved as: $OUTPUT_FILE"
echo "📁 Original images in $SOURCE_DIR are untouched"
echo "⏱️  Duration: $duration_formatted ($duration_seconds seconds)"
if [ -n "$AUDIO_FILE" ]; then
  echo "🎵 Background music added successfully"
fi
