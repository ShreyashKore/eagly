# Tip clips

Short looping animated WebPs shown at the top of a tip's detail dialog
(`Tip.media` in `lib/features/tips/tips_data.dart`). They are **not bundled**:
the app loads them from `TipMedia.baseUrl` (jsDelivr, tagged, so a published
URL never changes) only when the dialog opens, and drops the clip silently
when it can't load.

## Recording a clip (macOS)

Needs `brew install ffmpeg` (and libwebp's `img2webp`, already a dependency of it).

1. Make a fake log so no real device data reaches a published clip, and run
   the app in record mode (stand-in serials, fixed 1920×1080 window):

   ```bash
   python3 scripts/tips_media/make_sample_log.py /tmp/notes_sample.json
   fvm flutter run -d macos -a --record-mode
   ```

   Import the log (toolbar → *Import log file*). On a laptop screen the
   1920-wide window hangs off the left edge; drag it right so the area you
   film is on screen.

2. Record the region. `-i "2:none"` is the screen's avfoundation index
   (`ffmpeg -f avfoundation -list_devices true -i ""`); the crop is in
   *pixels*, i.e. points × 2 on Retina:

   ```bash
   ffmpeg -f avfoundation -pixel_format bgr0 -capture_cursor 1 -framerate 30 \
     -i "2:none" -t 14 -vf "crop=1764:1004:146:414" \
     -c:v libx264 -crf 12 -pix_fmt yuv444p take.mov
   ```

   `screencapture -v` needs a Screen Recording grant for the calling app and
   failed even with one; ffmpeg's capture worked.

3. Encode — trim to the action, crop away rows that never change:

   ```bash
   START=1.5 DURATION=8 scripts/tips_media/encode_webp.sh take.mov hide-columns.webp \
     "1764:760:0:0" 820 12 40 1600
   ```

   Aim for ≤ 150 KB. Plain lossy wins for UI: on the first clip lossless was
   2.1 MB and `-mixed` 317 KB against 105 KB at `-q 40`. 820 px is about 2× the
   dialog's content width, so it stays sharp on Retina.

   The dialog shows a wide crop at roughly half size, so small UI (menus,
   badges) is hard to read. `ZOOM` opens wide for context, then pushes in on
   the part that matters:

   ```bash
   ZOOM="1.6:0:0:0.8:1.4" START=1.5 DURATION=8.5 scripts/tips_media/encode_webp.sh \
     take.mov hide-columns.webp "1764:760:0:0" 720 12 40 1600
   ```

   A zoom repaints every pixel, so each moving frame is a full frame: sharp
   ones cost ~25 KB. Keep the move short (~0.6 s); its frames get a light blur
   (`ZOOM_BLUR`) and lower quality (`ZOOM_Q`), which reads as motion and
   roughly halves them. Zooming back out doubles that cost, so prefer
   staying close and letting the loop restart cut back to wide. On
   hide-columns: 1 s in + out, sharp → 837 KB; 0.6 s in only, blurred →
   188 KB at 820 px, 155 KB at 720 px.

4. Set `media: TipMedia('<file>.webp', aspectRatio: w / h)` on the tip and
   preview against a local server before publishing:

   ```bash
   (cd <dir with the webp> && python3 -m http.server 8765 --bind 127.0.0.1)
   fvm flutter run -d macos --dart-define=EAGLY_TIPS_MEDIA_BASE=http://127.0.0.1:8765/
   ```

## Publishing

Clips live in the public `ShreyashKore/eagly-tips-media` repo and are served
by jsDelivr from a tag (`…/eagly-tips-media@v1/<file>.webp`). Re-recording a
clip means a new tag and bumping `TipMedia.baseUrl`; older app builds keep
their tag.
