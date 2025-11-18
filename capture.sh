#!/bin/bash

# ---- CONFIG ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

VIDEO_FORMAT="mjpeg"
VIDEO_SIZE="640x480"
FRAMERATE="30"
STREAM_DEST="${STREAM_DEST:-udp://10.0.0.120:1234}"
BITRATE="${BITRATE:-6M}"
BUF_SIZE="12M"
DEFAULT_SHARE="Production"
# ----------------

# ---- HELP ----
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo ""
  echo "Usage:"
  echo "  $0 [--project <folder>] [--tape <name>] [--share <share>] [--streamAudio] [--format <type>]"
  echo ""
  echo "Options:"
  echo "  --project <folder>  Optional. Name of the project on the NAS. If omitted, will prompt for selection."
  echo "  --tape <name>       Optional. Name of the tape you're digitizing. If omitted, will prompt for input."
  echo "  --share <share>     Optional. NAS share name. Defaults to 'Production'."
  echo "  --streamAudio       Optional. Include audio in UDP stream (default: stream video only)."
  echo "  --format <type>     Optional. Output recording format. Options: prores, prores-lt (default), hevc."
  echo ""
  echo "Folder Selection:"
  echo "  If no project folder is specified, the script will list available folders in the share."
  echo "  You can then select from the numbered list."
  echo ""
  echo "Tape Name Input:"
  echo "  If no tape name is specified, the script will prompt you to enter one interactively."
  echo ""
  echo "Device Selection:"
  echo "  The script will automatically detect and prompt you to select video and audio devices."
  echo "  Video devices are detected using v4l2-ctl --list-devices"
  echo "  Audio devices are detected using arecord -l"
  echo ""
  echo "Examples:"
  echo "  $0                                    # Fully interactive mode"
  echo "  $0 --project \"My Project\"            # Select project, prompt for tape"
  echo "  $0 --tape \"Tape001\"                 # Prompt for project, specify tape"
  echo "  $0 --project \"My Project\" --tape \"Tape001\"  # Specify both"
  echo "  $0 --streamAudio --format hevc       # Include audio in stream, use HEVC"
  echo ""
  exit 0
fi

# ---- Device Selection Functions ----
list_video_devices() {
  echo "📹 Available video devices:"
  echo ""
  v4l2-ctl --list-devices 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
      continue
    elif [[ "$line" =~ ^[[:space:]]*/dev/video[0-9]+ ]]; then
      device=$(echo "$line" | tr -d ' ')
      echo "  $device"
    elif [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
      echo "  $line"
    fi
  done
  echo ""
}

list_audio_devices() {
  echo "🎤 Available audio devices:"
  echo ""
  arecord -l 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ card[[:space:]]+([0-9]+):[[:space:]]+.*device[[:space:]]+([0-9]+) ]]; then
      card_num="${BASH_REMATCH[1]}"
      device_num="${BASH_REMATCH[2]}"
      device_name=$(echo "$line" | sed 's/.*device[[:space:]]*[0-9]*:[[:space:]]*//')
      echo "  hw:${card_num},${device_num} - $device_name"
    fi
  done
  echo ""
}

select_video_device() {
  local devices=()
  
  # Parse v4l2-ctl output to extract devices
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*(/dev/video[0-9]+) ]]; then
      device="${BASH_REMATCH[1]}"
      devices+=("$device")
    fi
  done < <(v4l2-ctl --list-devices 2>/dev/null)
  
  if [ ${#devices[@]} -eq 0 ]; then
    echo "❌ No video devices found!"
    exit 1
  fi
  
  echo "📹 Select video device:"
  for i in "${!devices[@]}"; do
    echo "  $((i+1)). ${devices[i]}"
  done
  
  # Debug: Show what devices were detected
  echo "Debug: Detected devices: ${devices[*]}"
  
  while true; do
    read -p "Enter choice (1-${#devices[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#devices[@]}" ]; then
      VIDEO_DEVICE="${devices[$((choice-1))]}"
      echo "✅ Selected video device: $VIDEO_DEVICE"
      break
    else
      echo "❌ Invalid choice. Please enter a number between 1 and ${#devices[@]}."
    fi
  done
}

select_audio_device() {
  local devices=()
  local device_names=()
  
  # Parse arecord output to extract devices
  while IFS= read -r line; do
    if [[ "$line" =~ card[[:space:]]+([0-9]+):[[:space:]]+.*device[[:space:]]+([0-9]+) ]]; then
      card_num="${BASH_REMATCH[1]}"
      device_num="${BASH_REMATCH[2]}"
      device_name=$(echo "$line" | sed 's/.*device[[:space:]]*[0-9]*:[[:space:]]*//')
      devices+=("hw:${card_num},${device_num}")
      device_names+=("$device_name")
    fi
  done < <(arecord -l 2>/dev/null)
  
  if [ ${#devices[@]} -eq 0 ]; then
    echo "❌ No audio devices found!"
    exit 1
  fi
  
  echo "🎤 Select audio device:"
  for i in "${!devices[@]}"; do
    echo "  $((i+1)). ${devices[i]} - ${device_names[i]}"
  done
  
  # Debug: Show what devices were detected
  # echo "Debug: Detected audio devices: ${devices[*]}"
  
  while true; do
    read -p "Enter choice (1-${#devices[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#devices[@]}" ]; then
      AUDIO_DEVICE="${devices[$((choice-1))]}"
      echo "✅ Selected audio device: $AUDIO_DEVICE"
      break
    else
      echo "❌ Invalid choice. Please enter a number between 1 and ${#devices[@]}."
    fi
  done
}

# ---- Folder Selection Functions ----
get_project_folders() {
  local base_share="/mnt/${SHARE}"
  if [ ! -d "$base_share" ]; then
    echo "❌ Error: Share directory does not exist: $base_share" >&2
    exit 1
  fi
  
  local folders=()
  while IFS= read -r -d '' folder; do
    if [ -d "$folder" ]; then
      folder_name=$(basename "$folder")
      folders+=("$folder_name")
    fi
  done < <(find "$base_share" -maxdepth 1 -type d -not -path "$base_share" -print0 2>/dev/null)
  
  if [ ${#folders[@]} -eq 0 ]; then
    echo "❌ No project folders found in share '$SHARE'!" >&2
    echo "   Please create a project folder first." >&2
    exit 1
  fi
  
  # Return the folders array via printf (to stdout)
  printf '%s\n' "${folders[@]}"
}

list_project_folders() {
  local folders=()
  
  echo "📁 Available project folders in share '$SHARE':"
  echo ""
  
  # Get the list of folders
  while IFS= read -r folder; do
    folders+=("$folder")
  done < <(get_project_folders)
  
  for i in "${!folders[@]}"; do
    echo "  $((i+1)). ${folders[i]}"
  done
  echo ""
}

select_project_folder() {
  local folders=()
  
  # Get the list of folders
  while IFS= read -r folder; do
    folders+=("$folder")
  done < <(get_project_folders)
  
  if [ ${#folders[@]} -eq 0 ]; then
    echo "❌ No project folders found!"
    exit 1
  fi
  
  echo "📁 Select project folder:"
  for i in "${!folders[@]}"; do
    echo "  $((i+1)). ${folders[i]}"
  done
  
  while true; do
    read -p "Enter choice (1-${#folders[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#folders[@]}" ]; then
      PROJECT="${folders[$((choice-1))]}"
      echo "✅ Selected project folder: $PROJECT"
      break
    else
      echo "❌ Invalid choice. Please enter a number between 1 and ${#folders[@]}."
    fi
  done
}

# ---- Tape Name Input Function ----
input_tape_name() {
  echo "📼 Enter tape name:"
  while true; do
    read -p "Tape name: " tape_input
    if [ -n "$tape_input" ]; then
      TAPE="$tape_input"
      echo "✅ Tape name set to: $TAPE"
      break
    else
      echo "❌ Tape name cannot be empty. Please enter a tape name."
    fi
  done
}

# ---- Settings Save/Load Functions ----
SAVE_FILE="$SCRIPT_DIR/.capture-settings"

save_settings() {
  cat > "$SAVE_FILE" <<EOF
PROJECT="$PROJECT"
TAPE="$TAPE"
VIDEO_DEVICE="$VIDEO_DEVICE"
AUDIO_DEVICE="$AUDIO_DEVICE"
SHARE="$SHARE"
FORMAT="$FORMAT"
MUTE_STREAM="$MUTE_STREAM"
EOF
}

prompt_resume() {
  local saved_project saved_tape saved_video saved_audio saved_share saved_format saved_mute
  local current_project current_tape current_video current_audio current_share current_format current_mute
  
  if [[ ! -f "$SAVE_FILE" ]]; then
    return 1
  fi
  
  # Save current values
  current_project="$PROJECT"
  current_tape="$TAPE"
  current_video="$VIDEO_DEVICE"
  current_audio="$AUDIO_DEVICE"
  current_share="$SHARE"
  current_format="$FORMAT"
  current_mute="$MUTE_STREAM"
  
  # Load saved values
  # shellcheck disable=SC1090
  source "$SAVE_FILE"
  
  # Copy to saved_* variables
  saved_project="$PROJECT"
  saved_tape="$TAPE"
  saved_video="$VIDEO_DEVICE"
  saved_audio="$AUDIO_DEVICE"
  saved_share="$SHARE"
  saved_format="$FORMAT"
  saved_mute="$MUTE_STREAM"
  
  # Restore current values
  PROJECT="$current_project"
  TAPE="$current_tape"
  VIDEO_DEVICE="$current_video"
  AUDIO_DEVICE="$current_audio"
  SHARE="$current_share"
  FORMAT="$current_format"
  MUTE_STREAM="$current_mute"
  
  echo ""
  echo "💾 Resume with these settings?"
  echo "=============================="
  echo "  📁 Project: $saved_project"
  echo "  📼 Tape: $saved_tape"
  echo "  📹 Video Device: $saved_video"
  echo "  🎤 Audio Device: $saved_audio"
  echo "  📂 Share: $saved_share"
  echo "  🎬 Format: $saved_format"
  echo "  🔊 Stream Audio: $([ "$saved_mute" = "true" ] && echo "No" || echo "Yes")"
  echo ""
  
  while true; do
    read -p "Resume with these settings? (y/n): " response
    case "$response" in
      [yY]|[yY][eE][sS])
        echo "✅ Resuming with saved settings..."
        # Apply saved settings only if not overridden by command line
        [ -z "$PROJECT" ] && PROJECT="$saved_project"
        [ -z "$TAPE" ] && TAPE="$saved_tape"
        [ -z "$VIDEO_DEVICE" ] && VIDEO_DEVICE="$saved_video"
        [ -z "$AUDIO_DEVICE" ] && AUDIO_DEVICE="$saved_audio"
        [ "$SHARE" = "$DEFAULT_SHARE" ] && SHARE="$saved_share"
        [ "$FORMAT" = "prores-lt" ] && FORMAT="$saved_format"
        [ "$MUTE_STREAM" = "true" ] && MUTE_STREAM="$saved_mute"
        return 0
        ;;
      [nN]|[nN][oO])
        echo "🔄 Starting fresh configuration..."
        return 1
        ;;
      *)
        echo "❌ Please enter 'y' or 'n'."
        ;;
    esac
  done
}

# ---- Default Flags ----
PROJECT=""
TAPE=""
SHARE="$DEFAULT_SHARE"
MUTE_STREAM=true
FORMAT="prores-lt"
VIDEO_DEVICE=""
AUDIO_DEVICE=""

# ---- Parse Named Parameters ----
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift
      ;;
    --tape)
      TAPE="$2"
      shift
      ;;
    --share)
      SHARE="$2"
      shift
      ;;
    --muteStream)
      MUTE_STREAM=true
      ;;
    --streamAudio)
      MUTE_STREAM=false
      ;;
    --format)
      FORMAT="$2"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

# ---- Check for Saved Settings ----
RESUME_MODE=false
if prompt_resume; then
  RESUME_MODE=true
  echo ""
fi

# ---- Folder Selection ----
if [ -z "$PROJECT" ]; then
  echo "📁 Project Folder Selection"
  echo "=========================="
  select_project_folder
  echo ""
fi

# ---- Tape Name Input ----
if [ -z "$TAPE" ]; then
  echo "📼 Tape Name Input"
  echo "================="
  input_tape_name
  echo ""
fi

# ---- Device Selection ----
if [ -z "$VIDEO_DEVICE" ] || [ -z "$AUDIO_DEVICE" ]; then
  echo "🔧 Device Selection"
  echo "=================="
  if [ -z "$VIDEO_DEVICE" ]; then
    list_video_devices
    select_video_device
    echo ""
  fi
  if [ -z "$AUDIO_DEVICE" ]; then
    list_audio_devices
    select_audio_device
    echo ""
  fi
fi

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

# ---- Device Validation ----
# echo "🔍 Validating selected devices..."
if [ ! -e "$VIDEO_DEVICE" ]; then
  echo "❌ Error: Video device '$VIDEO_DEVICE' does not exist!"
  echo "   Please check that the device path is correct."
  exit 1
fi

if ! arecord -l | grep -q "card.*device.*$(echo "$AUDIO_DEVICE" | cut -d: -f2 | cut -d, -f1)"; then
  echo "❌ Error: Audio device '$AUDIO_DEVICE' not found in available devices!"
  echo "   Please check that the device is available."
  exit 1
fi

# echo "✅ Device validation passed"
# echo ""

# ---- Save Settings ----
save_settings

# ---- Feedback ----
echo "🎬 Recording to $OUTPUT_FILE using format: $FORMAT"
echo "📹 Using video device: $VIDEO_DEVICE"
echo "🎤 Using audio device: $AUDIO_DEVICE"
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
