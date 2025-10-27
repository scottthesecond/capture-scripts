#!/bin/bash

# ---- CONFIG ----
VIDEO_DEVICE="/dev/video0"
AUDIO_DEVICE="hw:2,0"
VIDEO_FORMAT="mjpeg"
VIDEO_SIZE="640x480"
FRAMERATE="30"
STREAM_DEST="udp://10.0.0.120:1234"
BITRATE="6M"
BUF_SIZE="12M"
DEFAULT_SHARE="Production"
# ----------------

# ---- HELP ----
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo ""
  echo "Usage:"
  echo "  $0 <project_folder> <tape_name> [--share <share>] [--muteStream] [--format prores|prores-lt|hevc]"
  echo ""
  echo "Arguments:"
  echo "  <project_folder>  Required. Name of the project on the NAS. Can contain spaces (wrap in quotes)."
  echo "  <tape_name>       Required. Name of the tape you're digitizing."
  echo "  --share <share>   Optional. NAS share name. Defaults to 'Production'."
  echo "  --muteStream      Optional. Mute the UDP stream (record audio, stream silent)."
  echo "  --format <type>   Optional. Output recording format. Options: prores, prores-lt (default), hevc."
  echo ""
  exit 0
fi

# ---- Parse Positional Args ----
PROJECT="$1"
TAPE="$2"
shift 2

if [ -z "$PROJECT" ] || [ -z "$TAPE" ]; then
  echo "❌ Error: Missing required arguments <project_folder> and/or <tape_name>"
  echo "Run with --help for usage."
  exit 1
fi

# ---- Default Flags ----
SHARE="$DEFAULT_SHARE"
MUTE_STREAM=false
FORMAT="prores-lt"

# ---- Parse Optional Flags ----
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --muteStream)
      MUTE_STREAM=true
      ;;
    --format)
      FORMAT="$2"
      shift
      ;;
    --share)
      SHARE="$2"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

# ---- Paths ----
BASE_DIR="/mnt/${SHARE}/${PROJECT}"
TAPE_DIR="${BASE_DIR}/${TAPE}"

# Check that base project dir exists
if [ ! -d "$BASE_DIR" ]; then
  echo "❌ Error: Project folder does not exist: $BASE_DIR"
  exit 1
fi

# Create tape folder if it doesn't exist
mkdir -p "$TAPE_DIR"

# Determine next available filename
INDEX=1
while [[ -e "${TAPE_DIR}/${INDEX}.mov" ]]; do
  INDEX=$((INDEX + 1))
done
OUTPUT_FILE="${TAPE_DIR}/${INDEX}.mov"

# ---- Determine Codec Options ----
VIDEO_CODEC=""
AUDIO_CODEC="pcm_s16le"
PIX_FMT=""
ENC_OPTIONS=""

case "$FORMAT" in
  prores)
    VIDEO_CODEC="prores_ks"
    ENC_OPTIONS="-profile:v 3"
    PIX_FMT="yuv422p10le"
    ;;
  prores-lt)
    VIDEO_CODEC="prores_ks"
    ENC_OPTIONS="-profile:v 1"
    PIX_FMT="yuv422p10le"
    ;;
  hevc)
    VIDEO_CODEC="libx265"
    ENC_OPTIONS="-crf 18"
    PIX_FMT="yuv420p10le"
    OUTPUT_FILE="${TAPE_DIR}/${INDEX}.mp4"
    ;;
  *)
    echo "Unsupported format: $FORMAT"
    exit 1
    ;;
esac

# ---- Feedback ----
echo "🎬 Recording to $OUTPUT_FILE using format: $FORMAT"
if [ "$MUTE_STREAM" = true ]; then
  echo "🔇 Stream will be video-only"
else
  echo "📡 Streaming video + audio to $STREAM_DEST"
fi
echo "⏹ Press Ctrl+C to stop."

# ---- Run ffmpeg ----
if [ "$MUTE_STREAM" = true ]; then
  ffmpeg \
    -f v4l2 -input_format "$VIDEO_FORMAT" -framerate "$FRAMERATE" -video_size "$VIDEO_SIZE" -i "$VIDEO_DEVICE" \
    -f alsa -i "$AUDIO_DEVICE" \
    -map 0:v -map 1:a -c:v "$VIDEO_CODEC" $ENC_OPTIONS -pix_fmt "$PIX_FMT" -c:a "$AUDIO_CODEC" "$OUTPUT_FILE" \
    -map 0:v -c:v mpeg2video -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BUF_SIZE" -an \
    -f mpegts "$STREAM_DEST"
else
  ffmpeg \
    -f v4l2 -input_format "$VIDEO_FORMAT" -framerate "$FRAMERATE" -video_size "$VIDEO_SIZE" -i "$VIDEO_DEVICE" \
    -f alsa -i "$AUDIO_DEVICE" \
    -map 0:v -map 1:a -c:v "$VIDEO_CODEC" $ENC_OPTIONS -pix_fmt "$PIX_FMT" -c:a "$AUDIO_CODEC" "$OUTPUT_FILE" \
    -map 0:v -map 1:a -c:v mpeg2video -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BUF_SIZE" -c:a mp2 -b:a 128k \
    -f mpegts "$STREAM_DEST"
fi