# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] – 2026-05-05

Initial release. Replaces a pile of half-working `@capacitor/share` glue
across NicOff with a single cross-cutting plugin.

### Added

- **`share()`** — system share sheet with `image` + `text` + `url`. Image
  is written to a temp file and shared natively so destinations like
  IG/Messages/AirDrop receive both the image and the caption (the official
  `@capacitor/share` v8 doesn't accept files at all).
- **`saveImage()`** — save PNG/JPG/WebP to the user's Photos / Gallery.
  - iOS: `PHPhotoLibrary` with optional album creation.
  - Android 29+: `MediaStore.Images` scoped storage (no runtime permission).
  - Android <29: `WRITE_EXTERNAL_STORAGE` runtime grant + `FileOutputStream` +
    `ACTION_MEDIA_SCANNER_SCAN_FILE` broadcast so the gallery picks it up.
  - Web: anchor-download fallback (browser triggers Save Image / picker on
    iOS WebView).
- **`shareToInstagramStory()`** — direct deep-link bypassing the system
  sheet. iOS uses `instagram-stories://share` + `UIPasteboard` general
  items per Meta's docs; Android uses `com.instagram.share.ADD_TO_STORY`
  intent with content URIs from a `FileProvider`.
- **`shareToTikTok()`** — `snssdk1233://` scheme on iOS (saves to camera
  roll first, opens TikTok); `com.zhiliaoapp.musically` package-targeted
  `Intent.ACTION_SEND` on Android.
- **`isAppInstalled({ scheme })`** — query whether IG / TikTok / Snapchat /
  WhatsApp / X are present. iOS `canOpenURL` requires the scheme listed in
  `LSApplicationQueriesSchemes`; Android uses `PackageManager.getPackageInfo`.
- **`checkPermissions()` / `requestPermissions()`** — Photos write
  permission state for iOS + pre-29 Android.

### Image input

All image-bearing methods accept `{ dataUrl }` or `{ base64, mimeType? }` —
both serialise cleanly through the JS↔native bridge. Use the exported
`blobToDataUrl(blob)` helper to convert a Canvas blob (e.g. from
`canvas.toBlob`) before calling.

### Web fallback

`navigator.share` files-aware path when available; text-only `navigator.share`;
clipboard-write fallback. Returns `{ completed, activityType }` so callers
can update UI accordingly.

### iOS setup notes

Add to `Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save your achievement and milestone images to your photo library.</string>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>instagram</string>
    <string>instagram-stories</string>
    <string>snssdk1233</string>
    <string>snapchat</string>
    <string>whatsapp</string>
    <string>twitter</string>
</array>
```

### Android setup notes

The plugin's `AndroidManifest.xml` declares the `FileProvider` and `<queries>`
needed for IG/TikTok/etc. detection on Android 11+. Nothing extra required
in the host app.
