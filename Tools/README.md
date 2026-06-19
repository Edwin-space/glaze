# Glaze bundled media tools

Put local compatibility tools here when validating MKV/WebM/AVI playback:

```text
Tools/ffmpeg
Tools/ffprobe
```

`script/build_and_run.sh` copies executable files from this directory into:

```text
dist/Glaze.app/Contents/Resources/Tools/
```

Runtime lookup order:

1. Bundled app resources under `Contents/Resources/Tools`
2. Homebrew/system locations such as `/opt/homebrew/bin`

Distribution rules:

- Use an LGPL-compatible FFmpeg build for App Store candidates.
- Do not use builds configured with `--enable-gpl` or `--enable-nonfree` for the default App Store build.
- Keep binary provenance, license text, source offer, and build flags documented before shipping.
- Do not commit downloaded FFmpeg binaries until the license and distribution plan are explicitly approved.

Local LGPL build:

```bash
./script/build_lgpl_ffmpeg_tools.sh
```

The script downloads official FFmpeg source, configures it without GPL/nonfree flags, builds `ffmpeg` and `ffprobe`, and places the local validation binaries in this directory. The generated binaries and build note are ignored by Git.
