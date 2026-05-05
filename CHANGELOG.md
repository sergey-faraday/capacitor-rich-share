# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] – 2026-05-05

### Added — unified destination router

- **`shareTo({ destination, ... })`** — single entry point that routes to the
  right native API based on `destination`. Discriminated union on the type
  side: each destination accepts only the fields that destination supports.
  Replaces the need for `if/else` chains across consumer code.

  Supported destinations:
  - `system` — OS share sheet (alias for `share()`)
  - `instagram-story` — `instagram-stories://` + `UIPasteboard` / FileProvider
  - `instagram-feed` — opens IG with image; iOS saves to camera roll first (no public deep-link to compose)
  - `facebook-story` — `facebook-stories://` + `com.facebook.sharedSticker.*` pasteboard / `com.facebook.stories.ADD_TO_STORY` intent
  - `snapchat-story` — `snapchat://creativekit/camera/1` + `com.snapchat.creativekit.*` pasteboard / package-targeted intent
  - `tiktok` — `snssdk1233://` (saves to camera roll first on iOS) / `com.zhiliaoapp.musically` package
  - `whatsapp` — `whatsapp://send?text=...` (iOS) / `com.whatsapp` package-targeted intent (Android). Routes image+text through the system sheet on iOS to avoid `whatsapp://` image-attachment quirks
  - `telegram` — `tg://msg_url?url=...&text=...` / `org.telegram.messenger`
  - `twitter` (also covers X) — `twitter://post?message=...&hashtags=...` with web-intent fallback / `com.twitter.android`
  - `linkedin` — `linkedin://shareArticle?...` / `com.linkedin.android` (text+url only — no image deep-link)
  - `sms` — `sms:?body=...` / `Intent.ACTION_VIEW` `smsto:`
  - `email` — `mailto:?subject=...&body=...` / `Intent.ACTION_SENDTO` `mailto:`
  - `clipboard` — `UIPasteboard.general` / `ClipboardManager.setPrimaryClip`

- **`copy({ text?, image? })`** — first-class clipboard write. iOS uses
  `UIPasteboard.setItems` with `public.utf8-plain-text` + `public.png`
  payloads so the user can paste the image into Photos/Notes/Mail.
  Android uses `ClipboardManager.setPrimaryClip` with a `text/uri-list`
  ClipData when an image is provided. Web uses `ClipboardItem` (Chrome /
  Safari 16+) for image+text.

### Web fallback expanded

The web build now opens each destination's web sharer URL where one exists:

- `twitter` → `https://x.com/intent/tweet?text=...`
- `whatsapp` → `https://wa.me/?text=...`
- `telegram` → `https://t.me/share/url?url=...&text=...`
- `linkedin` → `https://www.linkedin.com/sharing/share-offsite/?url=...`
- `sms` / `email` → `sms:` / `mailto:` anchor href
- `clipboard` → `navigator.clipboard.write` / `writeText`
- `system` → `navigator.share` files-aware, then text-only, then clipboard

App-only destinations (`instagram-story`, `facebook-story`, `snapchat-story`,
`tiktok`, `instagram-feed`) reject on web — UI should hide those buttons via
`isAppInstalled()` (returns `false` everywhere on web).

### Android probe expansion

`<queries>` block in the plugin's `AndroidManifest.xml` now includes Telegram
(`org.telegram.messenger`), Facebook (`com.facebook.katana`), LinkedIn
(`com.linkedin.android`), and WhatsApp Business (`com.whatsapp.w4b`), plus
broad intent-action queries for `image/*` SEND, `mailto:` SENDTO, and
`smsto:` VIEW so the system share sheet can enumerate destinations on
Android 11+.

`isAppInstalled()`'s scheme→package map covers all 12 supported destinations
plus aliases (`fb` → Facebook, `x` → Twitter, `instagram-stories` →
Instagram, etc.).

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
