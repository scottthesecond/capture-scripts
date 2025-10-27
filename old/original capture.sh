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
# ----------------

# Check for filename input
if [ -z "$1" ]; then
  echo "Usage: $0 <filename_without_extension> [--muteStream]"
  exit 1
fi

FILENAME="$1"
OUTPUT_FILE="${FILENAME}.mkv"

# Check for mute flag
MUTE_STREAM=false
if [[ "$2" == "--muteStream" ]]; then
  MUTE_STREAM=true
fi

echo "Recording to $OUTPUT_FILE"
if [ "$MUTE_STREAM" = true ]; then
  echo "Streaming video only (muted) to $STREAM_DEST"
else
  echo "Streaming video + audio to $STREAM_DEST"
fi
echo "Press Ctrl+C to stop."

# Build ffmpeg command dynamically
if [ "$MUTE_STREAM" = true ]; then
  ffmpeg \
    -f v4l2 -input_format $VIDEO_FORMAT -framerate $FRAMERATE -video_size $VIDEO_SIZE -i "$VIDEO_DEVICE" \
    -f alsa -i "$AUDIO_DEVICE" \
    -map 0:v -map 1:a -c:v copy -c:a pcm_s16le "$OUTPUT_FILE" \
    -map 0:v -c:v mpeg2video -b:v $BITRATE -maxrate $BITRATE -bufsize $BUF_SIZE -an \
    -f mpegts "$STREAM_DEST"
else
  ffmpeg \
    -f v4l2 -input_format $VIDEO_FORMAT -framerate $FRAMERATE -video_size $VIDEO_SIZE -i "$VIDEO_DEVICE" \
    -f alsa -i "$AUDIO_DEVICE" \
    -map 0:v -map 1:a -c:v copy -c:a pcm_s16le "$OUTPUT_FILE" \
    -map 0:v -map 1:a -c:v mpeg2video -b:v $BITRATE -maxrate $BITRATE -bufsize $BUF_SIZE \
    -c:a mp2 -b:a 128k -f mpegts "$STREAM_DEST"
fi