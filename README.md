# Capture Scripts

A set of bash scripts for digitizing video tapes on a headless Linux machine. The system captures video and audio from tape decks while simultaneously streaming a preview feed to another machine over the network, allowing you to monitor the capture process remotely.

## A word of warning
This is like, fully vibe-coded.  No ragrats

## Overview

This project is designed for tape digitization workflows where:
- The capture machine runs Linux without a display
- You need to monitor the capture process from another machine
- Recordings are saved to a network-attached storage (NAS) share
- You want to organize captures by project and tape name

The system uses `ffmpeg` to capture from V4L2 video devices and ALSA audio devices, encoding the recording to disk while simultaneously serving a preview feed via TCP. The receiver connects to the sender, allowing you to monitor the capture process remotely.

## Features

- **Dual Output**: Records high-quality video to disk while streaming a preview feed
- **Interactive Device Selection**: Automatically detects and lets you choose video and audio capture devices
- **Project Organization**: Organizes recordings by project folder and tape name
- **Multiple Formats**: Supports ProRes, ProRes-LT, and HEVC output formats
- **Settings Persistence**: Saves your device and project selections for easy resuming
- **Flexible Audio Streaming**: Option to include or exclude audio in the preview stream

## Requirements

### Capture Machine (Linux)
- `ffmpeg` with support for:
  - V4L2 input (`-f v4l2`)
  - ALSA audio input (`-f alsa`)
  - ProRes encoding (`prores_ks` codec) or HEVC (`libx265`)
  - MPEG-2 encoding for streaming (`mpeg2video`)
- `v4l2-ctl` (for listing video devices)
- `arecord` (for listing audio devices)
- A mounted NAS share at `/mnt/<share_name>/`
- Network connectivity for UDP streaming

### Viewing Machine
- `ffplay` (part of FFmpeg)
- Network connectivity to the capture machine

## Setup

1. **Clone or download this repository** to your capture machine

2. **Mount your NAS share** to `/mnt/<share_name>/` (e.g., `/mnt/Production/`)

3. **Create a `.env` file** (optional) in the script directory to customize defaults:
   
   **On the capture machine:**
   ```bash
   cp .env.example .env
   # Edit .env with your preferred settings
   ```
   
   **On the viewing/receiving machine:**
   ```bash
   cp .env.receiver.example .env
   # Edit .env and set SENDER_IP to your capture machine's IP address
   ```
   
   See the [Configuration](#configuration) section below for all available environment variables.

4. **Create project folders** on your NAS share. The script will look for folders in `/mnt/<share>/` and let you select from them.

## Usage

### Capture Script (`capture.sh`)

The capture script can be run in fully interactive mode or with command-line arguments:

```bash
./capture.sh [options]
```

#### Options

- `--project <folder>` - Specify the project folder name (skips selection prompt)
- `--tape <name>` - Specify the tape name (skips input prompt)
- `--share <share>` - NAS share name (defaults to value in `.env` or "Production")
- `--streamAudio` - Include audio in the UDP preview stream (default: video only)
- `--format <type>` - Output format: `prores`, `prores-lt` (default), or `hevc`
- `-h, --help` - Show help message

#### Examples

```bash
# Fully interactive mode - prompts for everything
./capture.sh

# Specify project, prompt for tape name
./capture.sh --project "My Project"

# Specify both project and tape
./capture.sh --project "My Project" --tape "Tape001"

# Include audio in stream and use HEVC format
./capture.sh --streamAudio --format hevc

# Use a different NAS share
./capture.sh --share "Archive" --project "Old Tapes"
```

#### Workflow

1. **Select Project Folder**: Choose from available folders on your NAS share, or specify with `--project`
2. **Enter Tape Name**: Provide a name for the tape you're digitizing, or specify with `--tape`
3. **Select Video Device**: Choose from detected V4L2 video capture devices
4. **Select Audio Device**: Choose from detected ALSA audio capture devices
5. **Recording**: The script will:
   - Create a folder structure: `/mnt/<share>/<project>/<tape>/`
   - Start recording with an auto-incrementing filename (1.mov, 2.mov, etc.)
   - Start a TCP server waiting for receiver connections
   - Save your settings for next time

6. **Stop Recording**: Press `Ctrl+C` to stop the capture

#### Settings Persistence

The script saves your last used settings (project, tape, devices, format, etc.) to `.capture-settings`. When you run the script again, it will offer to resume with these settings, making it easy to digitize multiple tapes in the same project.

### Receive Script (`receive.sh`)

On your viewing machine, run the receive script to connect to and display the preview stream:

```bash
./receive.sh [<sender_ip>]
```

The script will connect to the capture machine and display the incoming stream with low-latency settings optimized for real-time preview.

#### Usage

You can provide the sender IP address in three ways:

1. **As a command-line argument** (recommended):
   ```bash
   ./receive.sh 10.0.0.100
   ```

2. **Set `SENDER_IP` in your `.env` file**:
   ```bash
   SENDER_IP=10.0.0.100
   ```
   Then just run: `./receive.sh`

3. **Set `SENDER_IP` as an environment variable**:
   ```bash
   export SENDER_IP=10.0.0.100
   ./receive.sh
   ```

#### Customizing the Port

The default port is 1234. You can change it by:
- Setting `STREAM_PORT` in your `.env` file on both machines
- Or providing it as a second argument: `./receive.sh 10.0.0.100 8080`

**Note**: The receiver connects to the sender (pull model), so you don't need to know the receiver's IP address on the capture machine. The capture machine will record to disk even if no receiver is connected.

## Output Formats

- **prores-lt** (default): Apple ProRes 422 LT - Good balance of quality and file size
- **prores**: Apple ProRes 422 - Higher quality, larger files
- **hevc**: H.265/HEVC - Modern codec, smaller files, requires more processing

All formats record audio as uncompressed PCM. HEVC outputs as `.mp4`, ProRes outputs as `.mov`.

## File Organization

Recordings are organized as:
```
/mnt/<share>/
  └── <project>/
      └── <tape>/
          ├── 1.mov (or .mp4 for HEVC)
          ├── 2.mov
          └── ...
```

The script automatically increments the filename number, so you can capture multiple segments from the same tape without overwriting previous files.

## Configuration

### Environment Variables

Create a `.env` file in the script directory to customize defaults. You can copy the appropriate example file as a starting point:

**On the capture machine:**
```bash
cp .env.example .env
```

**On the receiving machine:**
```bash
cp .env.receiver.example .env
# Edit .env and set SENDER_IP to your capture machine's IP address
```

#### Stream Configuration

- `STREAM_PORT` - TCP port for preview stream server (default: `1234`)
- `STREAM_DEST` - Stream destination URL (default: `tcp://0.0.0.0:1234?listen=1` - automatically uses `STREAM_PORT`)
- `SENDER_IP` - IP address of capture machine (for `receive.sh`, set in receiver's `.env`)
- `BITRATE` - Bitrate for preview stream video (default: `6M`)
- `BUF_SIZE` - Buffer size for preview stream (default: `12M`)
- `STREAM_AUDIO_CODEC` - Audio codec for stream (default: `mp2`)
- `STREAM_AUDIO_BITRATE` - Audio bitrate for stream (default: `128k`)

#### Video Capture Configuration

- `VIDEO_FORMAT` - Video capture format (default: `mjpeg`)
  - Common options: `mjpeg`, `yuyv422`, `h264`
- `VIDEO_SIZE` - Video capture resolution (default: `640x480`)
  - Common options: `640x480`, `1280x720`, `1920x1080`
- `FRAMERATE` - Video capture framerate (default: `30`)
  - Common options: `25`, `30`, `60`

#### Audio Configuration

- `AUDIO_CODEC` - Audio codec for recording (default: `pcm_s16le`)
  - Common options: `pcm_s16le`, `pcm_s24le`, `aac`

#### Output Configuration

- `FORMAT` - Default output format (default: `prores-lt`)
  - Options: `prores`, `prores-lt`, `hevc`
- `SHARE` - Default NAS share name (default: `Production`)
  - This is the name of the mounted share at `/mnt/<SHARE>/`

### Stream Settings

The preview stream uses these default settings (all configurable via environment variables):
- Video input: MJPEG format at 640x480, 30fps
- Stream codec: MPEG-2 video
- Stream bitrate: 6M
- Stream protocol: TCP (receiver connects to sender)
- Stream audio: Optional (disabled by default, enable with `--streamAudio`)
  - When enabled, uses MP2 codec at 128k bitrate

**Workflow**: The capture machine starts a TCP server and waits for connections. The viewing machine connects when `receive.sh` is run. The capture machine will continue recording to disk even if no receiver is connected.

## Troubleshooting

### No video devices found
- Ensure your capture card is connected and recognized by the system
- Check that V4L2 drivers are loaded: `lsmod | grep video`
- Verify device exists: `ls -la /dev/video*`

### No audio devices found
- Check ALSA devices: `arecord -l`
- Ensure audio capture device is connected and recognized
- Verify permissions (you may need to be in the `audio` group)

### Stream not visible on viewing machine
- Verify network connectivity between machines
- Check firewall settings (TCP port 1234, or your configured `STREAM_PORT`)
- Ensure `SENDER_IP` is set correctly in `receive.sh` (or provided as argument)
- Verify `capture.sh` is running and waiting for connections
- Verify `receive.sh` is running and connecting to the correct IP/port
- Try connecting with: `ffplay tcp://<sender_ip>:1234` to test directly

### NAS share not accessible
- Verify the share is mounted at `/mnt/<share_name>/`
- Check mount permissions
- Ensure the project folder exists on the share

## License

This project is provided as-is for personal use.

