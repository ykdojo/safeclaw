---
name: yt-dlp
description: Download YouTube videos, audio, and subtitles/transcripts using yt-dlp.
---

# yt-dlp

Download YouTube videos, audio, and subtitles/transcripts.

## Setup

Check if yt-dlp is installed, and download it if not:

```bash
if ! command -v yt-dlp &>/dev/null && [ ! -f ~/yt-dlp ]; then
  curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/yt-dlp && chmod +x ~/yt-dlp
fi
```

Then use `~/yt-dlp` (or just `yt-dlp` if installed globally).

## Examples

Download subtitles/transcript:
```bash
~/yt-dlp --write-auto-sub --sub-lang en --skip-download -o "/tmp/%(id)s" <url>
```

Download audio only:
```bash
~/yt-dlp -x --audio-format mp3 -o "/tmp/%(title)s.%(ext)s" <url>
```

Download video:
```bash
~/yt-dlp -o "/tmp/%(title)s.%(ext)s" <url>
```

Get video info (title, duration, description):
```bash
~/yt-dlp --print title --print duration_string --print description --no-download <url>
```

## Notes

- Subtitles are saved as `.vtt` files - read them to get the transcript
- Use `/tmp/` for downloads to avoid cluttering the working directory
