# Create Slideshow

A safe, user-friendly Bash script that creates MP4 video slideshows from collections of images. The script automatically handles image rotation, randomizes the order, and produces professional-quality video output.

## Features

- **Non-destructive**: Original images are never modified
- **Automatic image rotation**: Handles EXIF orientation data intelligently
- **Random ordering**: Images are shuffled for variety
- **Professional output**: Full HD (1920x1080) MP4 video with H.264 encoding
- **Background music support**: Add music from YouTube, local files, or playlists
- **Flexible audio options**: Loop short audio, extend video to match audio, or fade out
- **Cross-platform compatibility**: Works with standard Unix utilities
- **User-friendly**: Clear progress indicators and safety confirmations

## Prerequisites

### Required
- Bash shell
- FFmpeg
- Standard Unix utilities (find, shuf, etc.)

### Optional (but recommended)
- **exiftool** OR **ImageMagick** - for automatic image rotation based on EXIF data
  - The script will work without these, but images may not be correctly oriented
- **yt-dlp** - for downloading audio from YouTube
  - Required only if you want to use YouTube URLs for background music
  - The script will work without this, but won't be able to download YouTube audio

### Installation

#### Ubuntu/Debian
```bash
# Required
sudo apt-get install ffmpeg

# Optional for image rotation (choose one)
sudo apt-get install exiftool       # Recommended
# OR
sudo apt-get install imagemagick    # Alternative

# Optional for YouTube music
sudo apt-get install yt-dlp
# OR
pip install yt-dlp
```

#### macOS (using Homebrew)
```bash
# Required
brew install ffmpeg

# Optional for image rotation (choose one)
brew install exiftool               # Recommended
# OR
brew install imagemagick            # Alternative

# Optional for YouTube music
brew install yt-dlp
```

## Usage

```bash
./create-slideshow.sh <directory_path> [options]
```

### Options

- `-m, --music <input>` - Add background music (YouTube URL, playlist file, or local audio)
- `--loop-audio` - Loop audio if it's shorter than the video
- `--extend-to-audio` - Extend slideshow duration to match audio length
- `--fade-duration <seconds>` - Audio fade out duration (default: 3 seconds)

### Examples

```bash
# Basic slideshow without music
./create-slideshow.sh ~/Pictures

# Add music from YouTube
./create-slideshow.sh ~/Pictures -m "https://youtube.com/watch?v=dQw4w9WgXcQ"

# Add multiple YouTube songs (comma-separated)
./create-slideshow.sh ~/Pictures -m "url1,url2,url3"

# Use a playlist file
./create-slideshow.sh ~/Pictures -m playlist.txt

# Use local audio file and loop it
./create-slideshow.sh ~/Pictures -m background.mp3 --loop-audio

# Extend slideshow to match audio duration
./create-slideshow.sh ~/Pictures -m playlist.txt --extend-to-audio
```

## Configuration

The script has one main configurable parameter that can be modified by editing the script:

- **`DURATION_PER_IMAGE`**: Duration each image is displayed (default: 5 seconds)
  - Edit line near the top of the script: `DURATION_PER_IMAGE=5`

## Music Playlists

You can create a playlist file to specify multiple songs for your slideshow. The playlist format is simple:

```txt
# Comments start with #
https://youtube.com/watch?v=dQw4w9WgXcQ
https://youtube.com/watch?v=abcdef12345

# You can also use just video IDs
dQw4w9WgXcQ
xyz789

# Empty lines are ignored
```

See `sample-playlist.txt` for a complete example.

### Music Options Explained

- **Loop Audio**: If your music is shorter than the slideshow, it will repeat
- **Extend to Audio**: The slideshow will be lengthened to match the music duration
- **Fade Duration**: Audio will fade out smoothly at the end (default: 3 seconds)

## Output

The script creates an MP4 file in your home directory with the filename format:
```
slideshow_YYYYMMDD_HHMMSS.mp4
```

Example: `slideshow_20231225_143052.mp4`

### Video Specifications
- Resolution: 1920x1080 (Full HD)
- Codec: H.264
- Pixel Format: YUV420p
- Aspect Ratio: Images are scaled to fit while maintaining their original aspect ratio, with black padding added as needed

## How It Works

1. **Validation**: Checks that the provided directory exists and contains images
2. **Safety Confirmation**: Shows what will happen and asks for user confirmation
3. **Temporary Directory**: Creates a temporary working directory to ensure original files are not modified
4. **Image Processing**:
   - Finds all JPG, JPEG, and PNG files in the directory
   - Randomizes the order
   - Copies and renames images sequentially
   - Applies EXIF-based rotation if tools are available
5. **Video Creation**: Uses FFmpeg to create the slideshow with smooth transitions
6. **Cleanup**: Removes temporary files after completion

## Supported Image Formats

- JPEG (.jpg, .jpeg, .JPG, .JPEG)
- PNG (.png, .PNG)

## Troubleshooting

### "No images found" error
- Ensure the directory contains JPG, JPEG, or PNG files
- Note: The script only looks in the specified directory, not subdirectories

### Images appear rotated incorrectly
- Install either `exiftool` or `ImageMagick` for automatic rotation
- Without these tools, images will appear in their stored orientation

### FFmpeg errors
- Ensure FFmpeg is properly installed: `ffmpeg -version`
- Check that you have sufficient disk space for the output video

### Permission denied
- Make the script executable: `chmod +x create-slideshow.sh`

## Safety Features

- Never modifies original images
- Requires explicit user confirmation before processing
- Works in a temporary directory
- Cleans up all temporary files after completion
- Clear error messages and exit codes
