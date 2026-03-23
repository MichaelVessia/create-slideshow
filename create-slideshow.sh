#!/usr/bin/env bash
set -euo pipefail

# Configuration
DURATION_PER_IMAGE=5
MUSIC_INPUT=""
LOOP_AUDIO=true
EXTEND_TO_AUDIO=false
AUDIO_FADE_DURATION=3
AUDIO_CACHE_DIR="$HOME/.cache/create-slideshow/audio"
DEDUP=false
DEDUP_THRESHOLD=10
HASH_CACHE_FILE="$HOME/.cache/create-slideshow/hashes.tsv"
FIRST_FILE=""
OUTPUT=""

# Function to display usage
usage() {
  echo "Usage: $0 <directory_path> [options]"
  echo ""
  echo "Options:"
  echo "  -m, --music <input>      YouTube URL(s), video ID(s), playlist file, or local audio file"
  echo "  --no-loop-audio          Don't loop audio if shorter than video (loops by default)"
  echo "  --extend-to-audio        Extend slideshow to match audio duration"
  echo "  --fade-duration <sec>    Audio fade duration in seconds (default: 3)"
  echo "  -o, --output <path>      Output file or directory (default: ~/slideshow_<timestamp>.mp4)"
  echo "  --first <file>           Pin a file as the first in the slideshow"
  echo "  --dedup                  Skip perceptually duplicate files"
  echo "  --dedup-threshold <N>    Hamming distance threshold (default: 10)"
  echo "  --clear-cache            Clear audio and hash caches and exit"
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
    --no-loop-audio)
      LOOP_AUDIO=false
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
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    --first)
      FIRST_FILE="$2"
      shift 2
      ;;
    --dedup)
      DEDUP=true
      shift
      ;;
    --dedup-threshold)
      DEDUP_THRESHOLD="$2"
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

  echo ""
  if [[ -f "$HASH_CACHE_FILE" ]]; then
    local hash_count
    hash_count=$(wc -l < "$HASH_CACHE_FILE")
    local hash_size
    hash_size=$(du -sh "$HASH_CACHE_FILE" 2>/dev/null | cut -f1 || echo "0")
    echo "Hash cache: $HASH_CACHE_FILE"
    echo "Cached hashes: $hash_count"
    echo "Hash cache size: $hash_size"
  else
    echo "Hash cache: not yet created"
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
      echo "Audio cache is already empty."
    fi
  else
    echo "Audio cache directory does not exist."
  fi

  if [[ -f "$HASH_CACHE_FILE" ]]; then
    local hash_count
    hash_count=$(wc -l < "$HASH_CACHE_FILE")
    echo "Clearing $hash_count cached hashes from $HASH_CACHE_FILE"
    rm -f "$HASH_CACHE_FILE"
    echo "Hash cache cleared."
  else
    echo "Hash cache does not exist."
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

# Get file identity (mtime + size) for cache validation
get_file_identity() {
  local filepath="$1"
  # Linux stat format, with macOS fallback
  if stat -c '%Y %s' "$filepath" 2>/dev/null; then
    return
  fi
  stat -f '%m %z' "$filepath"
}

# Compute perceptual hash (dHash) for an image or video file
# Produces a 16-char hex string (64-bit fingerprint)
compute_phash() {
  local file="$1"
  local ext="${file##*.}"
  local ext_lower
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  local raw_hex=""

  # Get 9x8 grayscale pixel data as hex
  case "$ext_lower" in
    mov|mp4|avi|mkv|webm|m4v)
      # Extract first frame from video, pipe to magick
      if $HAS_MAGICK; then
        raw_hex=$(ffmpeg -loglevel error -i "$file" -vframes 1 -f image2pipe -vcodec png pipe:1 2>/dev/null \
          | magick png:- -colorspace Gray -resize '9x8!' gray:- 2>/dev/null \
          | od -An -tx1 | tr -d ' \n')
      elif $HAS_CONVERT; then
        raw_hex=$(ffmpeg -loglevel error -i "$file" -vframes 1 -f image2pipe -vcodec png pipe:1 2>/dev/null \
          | convert png:- -colorspace Gray -resize '9x8!' gray:- 2>/dev/null \
          | od -An -tx1 | tr -d ' \n')
      fi
      ;;
    *)
      if $HAS_MAGICK; then
        raw_hex=$(magick "$file" -colorspace Gray -resize '9x8!' gray:- 2>/dev/null \
          | od -An -tx1 | tr -d ' \n')
      elif $HAS_CONVERT; then
        raw_hex=$(convert "$file" -colorspace Gray -resize '9x8!' gray:- 2>/dev/null \
          | od -An -tx1 | tr -d ' \n')
      fi
      ;;
  esac

  # Need exactly 72 pixels (144 hex chars)
  if [[ ${#raw_hex} -lt 144 ]]; then
    echo ""
    return 1
  fi

  # Build dHash: for each row (9 pixels), compare adjacent pairs (8 comparisons)
  # 8 rows x 8 bits = 64 bits = 16 hex chars
  local hash_bits=""
  for row in $(seq 0 7); do
    for col in $(seq 0 7); do
      local idx=$(( (row * 9 + col) * 2 ))
      local next_idx=$(( (row * 9 + col + 1) * 2 ))
      local pixel_val=$((16#${raw_hex:$idx:2}))
      local next_val=$((16#${raw_hex:$next_idx:2}))
      if [[ $pixel_val -lt $next_val ]]; then
        hash_bits+="1"
      else
        hash_bits+="0"
      fi
    done
  done

  # Convert 64-bit binary string to 16-char hex
  local hash_hex=""
  for i in $(seq 0 4 60); do
    local nibble="${hash_bits:$i:4}"
    local val=0
    [[ "${nibble:0:1}" == "1" ]] && ((val += 8))
    [[ "${nibble:1:1}" == "1" ]] && ((val += 4))
    [[ "${nibble:2:1}" == "1" ]] && ((val += 2))
    [[ "${nibble:3:1}" == "1" ]] && ((val += 1))
    hash_hex+=$(printf '%x' $val)
  done

  echo "$hash_hex"
}

# Load hash cache from TSV file into HASH_CACHE associative array
load_hash_cache() {
  declare -gA HASH_CACHE
  if [[ ! -f "$HASH_CACHE_FILE" ]]; then
    return
  fi
  while IFS=$'\t' read -r path mtime size phash; do
    [[ -z "$path" || "$path" == "#"* ]] && continue
    HASH_CACHE["$path"]="${mtime}	${size}	${phash}"
  done < "$HASH_CACHE_FILE"
}

# Save hash cache associative array back to TSV file
save_hash_cache() {
  mkdir -p "$(dirname "$HASH_CACHE_FILE")"
  > "$HASH_CACHE_FILE"
  for path in "${!HASH_CACHE[@]}"; do
    printf '%s\t%s\n' "$path" "${HASH_CACHE[$path]}" >> "$HASH_CACHE_FILE"
  done
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

# Resolve relative music input path before cd
if [[ -n "$MUSIC_INPUT" && "$MUSIC_INPUT" != /* && -f "$MUSIC_INPUT" ]]; then
  MUSIC_INPUT="$(cd "$(dirname "$MUSIC_INPUT")" && pwd)/$(basename "$MUSIC_INPUT")"
fi

# Set up working directory and output file
WORK_DIR="$HOME/slideshow_temp_$$"
if [[ -n "$OUTPUT" ]]; then
  # If output is a directory, put a timestamped file inside it
  if [[ -d "$OUTPUT" ]] || [[ "$OUTPUT" == */ ]]; then
    mkdir -p "$OUTPUT"
    OUTPUT_FILE="$OUTPUT/slideshow_$(date +%Y%m%d_%H%M%S).mp4"
  else
    mkdir -p "$(dirname "$OUTPUT")"
    OUTPUT_FILE="$OUTPUT"
  fi
else
  OUTPUT_FILE="$HOME/slideshow_$(date +%Y%m%d_%H%M%S).mp4"
fi

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

# Find media files
echo "📋 Finding and randomizing media..."
mapfile -d '' files < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.mov" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.m4v" \) -print0 | shuf -z)

if [ ${#files[@]} -eq 0 ]; then
  echo "❌ No media files found in $SOURCE_DIR"
  cd "$HOME" || exit 1
  rmdir "$WORK_DIR"
  exit 1
fi

# Pin --first file to front of array
if [[ -n "$FIRST_FILE" ]]; then
  # Resolve to absolute path relative to SOURCE_DIR if not absolute
  if [[ "$FIRST_FILE" != /* ]]; then
    FIRST_FILE="$SOURCE_DIR/$FIRST_FILE"
  fi
  if [[ ! -f "$FIRST_FILE" ]]; then
    echo "❌ Error: --first file not found: $FIRST_FILE"
    exit 1
  fi
  pinned=()
  rest=()
  for f in "${files[@]}"; do
    if [[ "$f" == "$FIRST_FILE" ]]; then
      pinned=("$f")
    else
      rest+=("$f")
    fi
  done
  if [[ ${#pinned[@]} -eq 0 ]]; then
    echo "❌ Error: --first file not in media list: $FIRST_FILE"
    exit 1
  fi
  files=("${pinned[@]}" "${rest[@]}")
  echo "📌 Pinned first: $(basename "$FIRST_FILE")"
fi

# Detect available image tools
HAS_MAGICK=false
HAS_CONVERT=false
command -v magick &>/dev/null && HAS_MAGICK=true
command -v convert &>/dev/null && HAS_CONVERT=true

# Dedup
if [[ "$DEDUP" == true ]]; then
  # Prefer images over videos with the same basename (e.g. IMG_1234.jpg + IMG_1234.MOV)
  declare -A basename_has_image=()
  for f in "${files[@]}"; do
    base="${f%.*}"
    ext_lower=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lower" in
      jpg|jpeg|png|heic) basename_has_image["$base"]=1 ;;
    esac
  done

  declare -a dedup_basename_filtered=()
  basename_dropped=0
  for f in "${files[@]}"; do
    base="${f%.*}"
    ext_lower=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lower" in
      mov|mp4|avi|mkv|webm|m4v)
        if [[ -n "${basename_has_image[$base]:-}" ]]; then
          echo "  Dropping video (image exists): $(basename "$f")"
          ((basename_dropped++)) || true
          continue
        fi
        ;;
    esac
    dedup_basename_filtered+=("$f")
  done

  if [[ $basename_dropped -gt 0 ]]; then
    echo "🔍 Dropped $basename_dropped video(s) with matching image basenames"
    files=("${dedup_basename_filtered[@]}")
  fi

  if ! $HAS_MAGICK && ! $HAS_CONVERT; then
    echo "⚠️  Neither magick nor convert found, skipping perceptual dedup"
  else
    echo "🔍 Computing perceptual hashes for dedup..."
    load_hash_cache

    declare -a file_hashes=()
    for f in "${files[@]}"; do
      identity=$(get_file_identity "$f")
      cached="${HASH_CACHE[$f]:-}"
      if [[ -n "$cached" ]]; then
        cached_mtime=$(echo "$cached" | cut -f1)
        cached_size=$(echo "$cached" | cut -f2)
        cached_hash=$(echo "$cached" | cut -f3)
        file_mtime=$(echo "$identity" | cut -d' ' -f1)
        file_size=$(echo "$identity" | cut -d' ' -f2)
        if [[ "$cached_mtime" == "$file_mtime" && "$cached_size" == "$file_size" ]]; then
          file_hashes+=("$cached_hash")
          continue
        fi
      fi
      echo "  Computing hash: $(basename "$f")" >&2
      phash=$(compute_phash "$f")
      if [[ -n "$phash" ]]; then
        file_mtime=$(echo "$identity" | cut -d' ' -f1)
        file_size=$(echo "$identity" | cut -d' ' -f2)
        HASH_CACHE["$f"]="${file_mtime}	${file_size}	${phash}"
        file_hashes+=("$phash")
      else
        file_hashes+=("")
      fi
    done

    # Pairwise comparison via awk (avoids ~n^2 subshell forks)
    # Build input: index, hash, basename per line
    awk_input=""
    for ((i = 0; i < ${#files[@]}; i++)); do
      awk_input+="${i}"$'\t'"${file_hashes[$i]}"$'\t'"$(basename "${files[$i]}")"$'\n'
    done

    # awk does all comparisons in-process, outputs duplicate indices
    dup_output=""
    dup_output=$(printf '%s' "$awk_input" | gawk -v threshold="$DEDUP_THRESHOLD" '
    BEGIN {
      FS = "\t"
      split("0 1 1 2 1 2 2 3 1 2 2 3 2 3 3 4", pop, " ")
      hex["0"]=0;  hex["1"]=1;  hex["2"]=2;  hex["3"]=3
      hex["4"]=4;  hex["5"]=5;  hex["6"]=6;  hex["7"]=7
      hex["8"]=8;  hex["9"]=9;  hex["a"]=10; hex["b"]=11
      hex["c"]=12; hex["d"]=13; hex["e"]=14; hex["f"]=15
    }
    {
      idx[NR] = $1
      hashes[NR] = $2
      names[NR] = $3
      n = NR
    }
    END {
      for (i = 1; i <= n; i++) {
        if (hashes[i] == "" || dup[i]) continue
        for (j = i + 1; j <= n; j++) {
          if (hashes[j] == "" || dup[j]) continue
          h1 = hashes[i]; h2 = hashes[j]
          dist = 0
          for (k = 1; k <= 16; k++) {
            c1 = substr(h1, k, 1)
            c2 = substr(h2, k, 1)
            xor_val = xor(hex[c1], hex[c2])
            dist += pop[xor_val + 1]
          }
          if (dist < threshold) {
            dup[j] = 1
            printf "DUP\t%s\t%s\t%d\n", names[j], names[i], dist
            print idx[j]
          }
        }
      }
    }
    ')

    declare -A dup_indices=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" == DUP$'\t'* ]]; then
        echo "  Duplicate: $(echo "$line" | cut -f2) ~ $(echo "$line" | cut -f3) (distance $(echo "$line" | cut -f4))"
      else
        dup_indices[$line]=1
      fi
    done <<< "$dup_output"

    # Filter out duplicates
    if [[ ${#dup_indices[@]} -gt 0 ]]; then
      declare -a filtered_files=()
      for ((i = 0; i < ${#files[@]}; i++)); do
        if [[ -z "${dup_indices[$i]:-}" ]]; then
          filtered_files+=("${files[$i]}")
        fi
      done
      echo "🔍 Skipped ${#dup_indices[@]} duplicate(s), ${#filtered_files[@]} files remaining"
      files=("${filtered_files[@]}")
    else
      echo "🔍 No duplicates found"
    fi

    save_hash_cache
  fi
fi

# Classify files into images and videos
image_count=0
video_count=0
for f in "${files[@]}"; do
  ext="${f##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  case "$ext_lower" in
    jpg|jpeg|png|heic) ((image_count++)) || true ;;
    mov|mp4|avi|mkv|webm|m4v) ((video_count++)) || true ;;
  esac
done

echo "📷 Found ${#files[@]} media files ($image_count images, $video_count videos)"
echo "📋 Processing media files..."

if $HAS_MAGICK; then
  echo "✅ Using ImageMagick v7 for auto-orient"
elif $HAS_CONVERT; then
  echo "✅ Using ImageMagick v6 for auto-orient"
else
  echo "⚠️  ImageMagick not found. Images may not be rotated correctly."
  echo "   Install with: sudo apt install imagemagick"
fi

processed_files=()
total_clip_duration=0

for i in "${!files[@]}"; do
  printf "\rProcessing: %d/%d" $((i + 1)) ${#files[@]}
  src="${files[$i]}"
  ext="${src##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  seq_num="$(printf "%04d" $((i + 1)))"

  case "$ext_lower" in
    jpg|jpeg|png)
      output_name="${seq_num}.jpg"
      if $HAS_MAGICK; then
        magick "$src" -auto-orient "$output_name"
      elif $HAS_CONVERT; then
        convert "$src" -auto-orient "$output_name" 2>/dev/null || convert "$src" -auto-orient "$output_name"
      else
        cp "$src" "$output_name"
      fi
      processed_files+=("$output_name")
      ;;
    heic)
      output_name="${seq_num}.jpg"
      if $HAS_MAGICK; then
        magick "$src" -auto-orient "$output_name"
      elif $HAS_CONVERT; then
        convert "$src" -auto-orient "$output_name" 2>/dev/null || convert "$src" -auto-orient "$output_name"
      else
        ffmpeg -loglevel error -i "$src" -vframes 1 "$output_name"
      fi
      processed_files+=("$output_name")
      ;;
    mov|mp4|avi|mkv|webm|m4v)
      output_name="${seq_num}.mp4"
      ffmpeg -loglevel error -i "$src" \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1:color=black,format=yuv420p" \
        -c:v libx264 -pix_fmt yuv420p -an \
        -y "$output_name"
      clip_dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$output_name" 2>/dev/null)
      total_clip_duration=$(echo "$total_clip_duration + $clip_dur" | bc)
      processed_files+=("$output_name")
      ;;
  esac
done
echo ""

# Calculate video duration
# total_clip_duration may be fractional; truncate to integer for arithmetic
total_clip_duration_int=$(printf "%.0f" "$total_clip_duration")
VIDEO_DURATION=$(( image_count * DURATION_PER_IMAGE + total_clip_duration_int ))
echo "📹 Video duration: ${VIDEO_DURATION}s ($image_count images x ${DURATION_PER_IMAGE}s + ${total_clip_duration_int}s video clips)"

# Adjust duration if extending to audio
if [ -n "$AUDIO_FILE" ] && [ "$EXTEND_TO_AUDIO" = true ] && [ $AUDIO_DURATION -gt $VIDEO_DURATION ]; then
  echo "🎵 Extending slideshow to match audio duration: ${AUDIO_DURATION}s"
  if [ $image_count -gt 0 ]; then
    # Only stretch image duration, video clip durations stay fixed
    remaining=$((AUDIO_DURATION - total_clip_duration_int))
    DURATION_PER_IMAGE=$(( (remaining + image_count - 1) / image_count ))
    VIDEO_DURATION=$(( image_count * DURATION_PER_IMAGE + total_clip_duration_int ))
    echo "⏱️  Adjusted duration per image: $DURATION_PER_IMAGE seconds"
  else
    echo "⚠️  No images to extend, video clip durations are fixed"
  fi
fi

# Create slideshow using concat demuxer for precise timing
echo "🎬 Creating slideshow..."
if [ $image_count -gt 0 ]; then
  echo "⏱️  Each image will display for $DURATION_PER_IMAGE seconds"
fi

# Create input file list with durations
> input.txt
for pf in "${processed_files[@]}"; do
  echo "file '$pf'" >> input.txt
  if [[ "$pf" == *.jpg ]]; then
    echo "duration $DURATION_PER_IMAGE" >> input.txt
  fi
done

# Add last file again if it's a jpg (required by concat demuxer for images)
last_file="${processed_files[-1]}"
if [[ "$last_file" == *.jpg ]]; then
  echo "file '$last_file'" >> input.txt
fi

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

duration_formatted=$(printf '%02d:%02d' $((VIDEO_DURATION / 60)) $((VIDEO_DURATION % 60)))

echo "✅ Complete! Slideshow saved as: $OUTPUT_FILE"
echo "📁 Original files in $SOURCE_DIR are untouched"
echo "⏱️  Duration: $duration_formatted ($VIDEO_DURATION seconds)"
if [ -n "$AUDIO_FILE" ]; then
  echo "🎵 Background music added successfully"
fi
