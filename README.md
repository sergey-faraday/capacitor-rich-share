# capacitor-rich-share

Native-quality sharing for Capacitor — system share sheet **with image+text together**, save to Photos / Gallery, Instagram Story / TikTok deep-links, and an `isAppInstalled()` probe.

The official `@capacitor/share` plugin is text-only on v8 and silently fails when you pass an image. This plugin handles the temp-file dance, scoped-storage MediaStore writes, `instagram-stories://` URL scheme + `UIPasteboard` items, Android `FileProvider` content URIs — all the bits that real share UX needs.

## Install

```bash
npm install capacitor-rich-share
npx cap sync
```

Add to `Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save your share images to your photo library.</string>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>instagram</string>
    <string>instagram-stories</string>
    <string>snssdk1233</string>
    <string>whatsapp</string>
    <string>snapchat</string>
    <string>twitter</string>
</array>
```

Android needs nothing extra — the plugin's manifest declares the `FileProvider` and `<queries>` itself.

## Quick start

```ts
import { RichShare, blobToDataUrl } from 'capacitor-rich-share';

// 1. Build an image (e.g. canvas → blob)
const blob = await canvas.toBlob('image/png');
const dataUrl = await blobToDataUrl(blob);

// 2. System share sheet with image + caption
await RichShare.share({
  image: { dataUrl },
  text: 'Day 30 nicotine-free 🎉',
  url: 'https://nicoff.app',
  filename: 'nicoff-day-30',
});

// 3. Save to user's Photos / Gallery
await RichShare.saveImage({
  image: { dataUrl },
  filename: 'nicoff-day-30',
  album: 'nicoff',          // optional
});

// 4. Direct deep-link to Instagram Story
if ((await RichShare.isAppInstalled({ scheme: 'instagram' })).installed) {
  await RichShare.shareToInstagramStory({
    stickerImage: { dataUrl },
    backgroundTopColor: '#14B8A6',
    backgroundBottomColor: '#0F766E',
    sourceApplication: 'com.your.app',  // optional, used for IG attribution
  });
}
```

## API

### `share(options)` → `{ completed, activityType }`

System share sheet. Accepts any combination of `image`, `text`, `url`, `title`, `filename`. When `image` is present, native side writes a temp PNG and shares it together with the text — most destinations (IG/Messages/AirDrop) display both.

### `saveImage(options)` → `{ assetId, path }`

Save image to Photos (iOS) or Gallery (Android). Triggers permission prompt on first use.

- iOS: creates album if `album` is provided.
- Android 29+: scoped storage (`MediaStore`), no runtime permission.
- Android <29: requires `WRITE_EXTERNAL_STORAGE`.

### `checkPermissions()` / `requestPermissions()` → `{ photos: 'prompt'|'granted'|'denied'|'limited' }`

### `shareToInstagramStory(options)` → `void`

Direct deep-link to IG Story with sticker + optional background image and gradient colours. Throws if Instagram isn't installed.

### `shareToTikTok(options)` → `void`

Deep-link to TikTok with the image attached.

### `isAppInstalled({ scheme })` → `{ installed }`

Probe for IG / Snapchat / TikTok / WhatsApp / X.

## Image input

All image-bearing methods accept either:

```ts
{ dataUrl: 'data:image/png;base64,iVBORw0...' }
// or
{ base64: 'iVBORw0...', mimeType: 'image/png' }
```

Use the exported helper to go from `Blob` (e.g. `canvas.toBlob` output):

```ts
import { blobToDataUrl } from 'capacitor-rich-share';
const dataUrl = await blobToDataUrl(blob);
```

## Web fallback

The web implementation prefers `navigator.share` with files when available, falls back to text-only `navigator.share`, then clipboard-write. `saveImage` uses an `<a download>` (browser handles the rest).

## License

MIT — see [LICENSE](./LICENSE).
