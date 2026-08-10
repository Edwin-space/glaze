# Bundled VLC runtime — third-party licenses

This directory (`Tools/vlc`) bundles `libvlc`/`libvlccore` and a curated set of VLC playback plugins, used by [`NativeVLCLibrary.swift`](../../Sources/GlazeMac/Core/Media/NativeVLCLibrary.swift) via `dlopen`. This notice exists to satisfy the LGPL's license/attribution requirements.

## Core engine

- **libvlc / libvlccore** — © VideoLAN and contributors. Licensed under the **GNU Lesser General Public License, version 2.1 or later**. Full text: <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>. Official project: <https://www.videolan.org/vlc/libvlc.html>.

## Methodology (2026-08-10)

`Tools/vlc/plugins` originally contained 339 plugins extracted from a full desktop VLC.app build, which is not VideoLAN's curated LGPL-only distribution and included GPL-only third-party modules — unsuitable for App Store distribution as-is (see `docs/16_foundation_redesign_audit.md` §2.3).

Every plugin embeds its own license declaration at build time (VideoLAN's `set_license(...)` module macro compiles a `"Licensed under the terms of the GNU [Lesser ]General Public License..."` string directly into the binary; FFmpeg-derived plugins separately embed a `"lib<name> license: ..."` string). We verified this for all 339 plugins with `strings <plugin>.dylib | grep -i "Licensed under the terms of"` (cross-checked against VideoLAN's official 2012 relicensing announcement, <https://www.videolan.org/press/lgpl-modules.html>, which confirms interface, streaming/transcode, and DVD-playback modules intentionally stayed GPLv2) and removed every plugin that:

- self-declares GPL (not LGPL), **or**
- is a streaming-server / VLC-own-interface / remote-control / service-discovery module we don't use (our app is file-playback only — see the empty `sout=`-option and DVD-reference `grep` results referenced in the plan for this cleanup)

**74 plugins removed, 265 remain.** All 265 remaining plugins were individually confirmed LGPL-2.1-or-later via the embedded declaration above (or, for the 4 FFmpeg-derived plugins, via FFmpeg's own embedded license string). Zero plugins with a non-LGPL or missing declaration remain as of this pass.

### Removed — GPL-licensed, no LGPL-safe use in this app (9)

| Plugin | Why GPL | Why removable |
|---|---|---|
| `libx264_plugin`, `libx26410b_plugin` | x264, GPL-2.0-or-later | H.264 **encoder** — we only decode |
| `libx265_plugin` | x265, GPL-2.0-or-later | HEVC **encoder** — we only decode |
| `libgoom_plugin` | goom, GPL-2.0 | Audio visualizer, unused |
| `libdvdnav_plugin`, `libdvdread_plugin` | GPL per VideoLAN's own relicensing carve-out (DVD playback explicitly excluded) | No DVD/VIDEO_TS support in this app (verified: no references in `Sources/`) |
| `libmad_plugin` | libmad, GPL-only (no LGPL release ever existed) | MP3 decode covered by `libmpg123_plugin` (LGPL) |
| `libfaad_plugin` | FAAD2, GPL-2.0-or-later | AAC decode covered by `libavcodec_plugin` (LGPL, confirmed below) |
| `libpostproc_plugin` | FFmpeg's `libpostproc`, embedded string confirms `"GPL version 2 or later"` (unlike `libavcodec`/`libavformat`/`libavutil`/`libswscale`, which embed `"LGPL version 2.1 or later"`) | Optional deblock/deband post-filter, not required for playback |

### Removed — GPL per VideoLAN's own module declaration, and not needed for local file playback (65)

All confirmed via the `strings`-based scan above (not by name-guessing). Grouped by why they're unnecessary for a local-file player embedding its own video surface (`NativeVLCPlayerView.swift`) rather than using VLC's own UI or server features:

- **Streaming/transcode output** (VideoLAN's press release: "streaming modules... not affected by this change") — all `libstream_out_*` (20), all `libaccess_output_*` (8), all `libmux_*` (9), plus `libvod_rtsp_plugin`, `libaccess_realrtsp_plugin`, `libsap_plugin`, `libt140_plugin`
- **VLC's own interface/remote-control** (press release: "interface modules... always stay GPLv2") — `libmacosx_plugin` (we embed our own `NSView` via `libvout_macosx_plugin`, which is LGPL and kept), `libhotkeys_plugin`, `libncurses_plugin`, `libgestures_plugin`, `libmpc_plugin` (MPD-style remote-control protocol, not the Musepack codec), `liboldrc_plugin`, `libosx_notifications_plugin` (we use our own `AppNotifications.swift`), `libdummy_plugin`
- **Service discovery / online features unused by this app** — `libpodcast_plugin`, `libmediadirs_plugin`, `libnetsync_plugin`, `libaudioscrobbler_plugin`, `liblua_plugin` (VLC's scripting/art-fetcher glue)
- **Logging/diagnostics** (we use our own `os_log`-based logging) — `liblogger_plugin`, `libfile_logger_plugin`, `libsyslog_plugin`, `libstats_plugin`, `libexport_plugin`
- **Optional audio/video filters not used by this app** — `libdolby_surround_decoder_plugin`, `libheadphone_channel_mixer_plugin`, `libmono_plugin`, `librotate_plugin`, `libmotion_plugin`
- **Legacy/niche format** — `libreal_plugin` (RealMedia; not in our supported extension list)

## Remaining bundled third-party libraries (LGPL / permissive)

Spot-checked license family for the notable third-party codec/format libraries among the 265 remaining plugins (embedded VLC module declaration says LGPL-2.1-or-later for all of them; upstream project's own license is noted for context):

| Library | Plugin(s) | Upstream license |
|---|---|---|
| FFmpeg (avcodec/avformat/avutil/swscale) | `libavcodec_plugin`, `libswscale_plugin` | LGPL-2.1+ (confirmed via embedded `"license: LGPL version 2.1 or later"`, i.e. built without `--enable-gpl`) |
| Opus, Vorbis, Theora, Speex, FLAC | `libopus_plugin`, `libvorbis_plugin`, `libtheora_plugin`, `libspeex_plugin`, `libspeex_resampler_plugin`, `libflac_plugin`, `libflacsys_plugin` | BSD-3-Clause (Xiph.Org) |
| FreeType | `libfreetype_plugin` | FreeType License (BSD-style) |
| libass | `liblibass_plugin` | ISC |
| libbluray | `liblibbluray_plugin` | LGPL-2.1+ |
| GnuTLS | `libgnutls_plugin` | LGPL-2.1+ |
| TagLib | `libtaglib_plugin` | LGPL-2.1 / MPL-1.1 dual |
| Game Music Emu | `libgme_plugin` | LGPL-2.1+ |
| dav1d | `libdav1d_plugin` | BSD-2-Clause (VideoLAN project) |
| libaom (AV1) | `libaom_plugin` | BSD-2-Clause + patent grant |
| libvpx (VP8/VP9) | `libvpx_plugin` | BSD-3-Clause |
| mpg123 | `libmpg123_plugin` | LGPL-2.1 |
| TwoLAME | `libtwolame_plugin` | LGPL-2.1 |
| Schroedinger | `libschroedinger_plugin` | MPL-1.1 / GPL-2.0 / LGPL-2.1 tri-license (used here under LGPL) |
| live555 | `liblive555_plugin` | live555's own custom license text (historically treated as LGPL-compatible by VideoLAN — recommend confirming the exact bundled version's `COPYING` before relying on this) |
| zvbi | `libzvbi_plugin` | LGPL-2.1+ |
| a52 (AC-3) | `liba52_plugin` | VLC's own module declares LGPL-2.1+; note the *original* upstream `a52dec`/`liba52` project (a52dec.sourceforge.net) is itself GPL-licensed — VideoLAN's bundled module is either a from-scratch/relicensed implementation or covered by an explicit relicense grant. Flagged for legal confirmation before submission, not treated as a blocker here since the shipped binary's own declaration is LGPL. |

The remaining ~245 plugins not listed above are VLC-authored demuxers, format parsers, and filters with no distinct third-party upstream license to track (they were part of VideoLAN's 2012 GPL→LGPL relicensing and self-declare LGPL-2.1-or-later individually, as verified by the scan above).

## Disclaimer

This classification is based on each plugin's own embedded license declaration, FFmpeg's own embedded build configuration, and VideoLAN's public relicensing statements — not a legal opinion. Recommend a licensing/legal review pass before actual App Store submission, particularly for `liba52_plugin` and `liblive555_plugin` (flagged above) and for confirming no plugin update since this pass (2026-08-10) reintroduced a GPL dependency.
