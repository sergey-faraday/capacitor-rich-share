# capacitor-rich-share

Native-quality sharing for Capacitor — system share sheet **with image+text together**, save to Photos / Gallery, deep-links to Instagram / Facebook / Snapchat / TikTok / WhatsApp / Telegram / X / LinkedIn / SMS / Email / clipboard, and an `isAppInstalled()` probe.

The official `@capacitor/share` plugin is text-only and silently fails when you pass an image. This plugin handles the temp-file dance, scoped-storage `MediaStore` writes, `instagram-stories://` URL scheme + `UIPasteboard` items, Android `FileProvider` content URIs, package-targeted `Intent.ACTION_SEND` — all the bits that real share UX needs.

## Install

```bash
npm install capacitor-rich-share
npx cap sync
```

### iOS — `Info.plist`

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save your share images to your photo library.</string>

<!-- Schemes you intend to probe / open. List only what you actually use. -->
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>instagram</string>
    <string>instagram-stories</string>
    <string>facebook-stories</string>
    <string>snapchat</string>
    <string>snssdk1233</string>          <!-- TikTok -->
    <string>whatsapp</string>
    <string>tg</string>                  <!-- Telegram -->
    <string>twitter</string>             <!-- covers X -->
    <string>linkedin</string>
</array>
```

`mailto:` and `sms:` are allowed by iOS without an `LSApplicationQueriesSchemes` entry.

### Android

Nothing extra — the plugin's `AndroidManifest.xml` declares the `FileProvider` and the `<queries>` block needed for package visibility on Android 11+.

## Quick start

```ts
import { RichShare, blobToDataUrl } from 'capacitor-rich-share';

// 1. Build an image (e.g. canvas → blob)
const blob = await canvas.toBlob('image/png');
const dataUrl = await blobToDataUrl(blob);

// 2. System share sheet with image + caption
await RichShare.share({
  image: { dataUrl },
  text: 'Check out this thing I made',
  url: 'https://example.com',
  filename: 'my-share',
});

// 3. Save to user's Photos / Gallery
await RichShare.saveImage({
  image: { dataUrl },
  filename: 'my-image',
  album: 'MyApp',          // optional
});

// 4. Direct deep-link to Instagram Story
if ((await RichShare.isAppInstalled({ scheme: 'instagram' })).installed) {
  await RichShare.shareToInstagramStory({
    stickerImage: { dataUrl },
    backgroundTopColor: '#14B8A6',
    backgroundBottomColor: '#0F766E',
    sourceApplication: 'com.your.app',  // defaults to your bundle ID
  });
}
```

## Unified destinations

```ts
// One call, any destination — type-safe per destination.
await RichShare.shareTo({ destination: 'instagram-story', stickerImage: { dataUrl } });
await RichShare.shareTo({ destination: 'whatsapp', text: 'check this out', url: 'https://example.com' });
await RichShare.shareTo({ destination: 'twitter', text: 'Hello!', hashtags: ['hello', 'world'] });
await RichShare.shareTo({ destination: 'tiktok', image: { dataUrl } });
await RichShare.shareTo({ destination: 'sms', text: 'Look at this' });
await RichShare.shareTo({ destination: 'email', subject: 'Hi', body: 'How are you?', to: 'friend@example.com' });
await RichShare.shareTo({ destination: 'clipboard', text: 'https://example.com' });
await RichShare.shareTo({ destination: 'system', image: { dataUrl }, text: 'pick anywhere' });

// Clipboard write — first-class
await RichShare.copy({ text: 'pasted in Notes', image: { dataUrl } });
```

13 destinations: `system`, `instagram-story`, `instagram-feed`, `facebook-story`,
`snapchat-story`, `tiktok`, `whatsapp`, `telegram`, `twitter` (covers X),
`linkedin`, `sms`, `email`, `clipboard`.

## API

### `share(options)` → `{ completed, activityType }`

System share sheet. Accepts any combination of `image`, `text`, `url`, `title`, `filename`. When `image` is present, native side writes a temp PNG and shares it together with the text — most destinations (IG / Messages / AirDrop) display both.

### `saveImage(options)` → `{ assetId, path }`

Save image to Photos (iOS) or Gallery (Android). Triggers permission prompt on first use.

- iOS: creates album if `album` is provided.
- Android 29+: scoped storage (`MediaStore`), no runtime permission.
- Android <29: requires `WRITE_EXTERNAL_STORAGE`.

### `checkPermissions()` / `requestPermissions()` → `{ photos: 'prompt' | 'granted' | 'denied' | 'limited' }`

Photo-library write permission. Android 29+ always reports `granted` since scoped storage doesn't need a runtime grant.

### `shareToInstagramStory(options)` → `void`

Direct deep-link to IG Story with sticker + optional background image and gradient colours. Throws if Instagram isn't installed.

### `shareToTikTok(options)` → `void`

Deep-link to TikTok with the image attached.

### `isAppInstalled({ scheme })` → `{ installed }`

Probe for IG / FB / Snapchat / TikTok / WhatsApp / Telegram / X / LinkedIn. iOS requires the scheme listed in `LSApplicationQueriesSchemes` — otherwise this always returns `false`.

### `shareTo(options)` → `{ completed, destination }`

Unified destination router. `options.destination` discriminates the union; each branch accepts only the fields that destination supports. The native side picks the right URL scheme / targeted Intent / pasteboard payload.

| destination | iOS | Android | Image |
|---|---|---|---|
| `system` | `UIActivityViewController` | `Intent.createChooser` | ✅ |
| `instagram-story` | `instagram-stories://` + `UIPasteboard` | `com.instagram.share.ADD_TO_STORY` | sticker |
| `instagram-feed` | open IG (image saved to camera roll first) | `Intent.ACTION_SEND` to IG package | ✅ |
| `facebook-story` | `facebook-stories://` + pasteboard | `com.facebook.stories.ADD_TO_STORY` | sticker |
| `snapchat-story` | `snapchat://creativekit/camera/1` + pasteboard | `Intent.ACTION_SEND` to Snap package | sticker |
| `tiktok` | `snssdk1233://` (image saved to camera roll first) | `Intent.ACTION_SEND` to TikTok package | ✅ |
| `whatsapp` | image+text via system sheet, else `whatsapp://send` | `Intent.ACTION_SEND` to WA package | ✅ |
| `telegram` | `tg://msg_url` | `Intent.ACTION_SEND` to TG package | ✅ |
| `twitter` | `twitter://post` (web intent fallback) | `Intent.ACTION_SEND` to X package | ✅ |
| `linkedin` | `linkedin://shareArticle` | `Intent.ACTION_SEND` to LI package | ❌ (text+url only) |
| `sms` | `sms:?body=...` | `smsto:` `ACTION_VIEW` | ❌ |
| `email` | `mailto:?subject=&body=` | `mailto:` `ACTION_SENDTO` | ❌ |
| `clipboard` | `UIPasteboard` | `ClipboardManager` | ✅ |

### `copy(options)` → `void`

Clipboard write. iOS uses `UIPasteboard.setItems` with `public.utf8-plain-text` + `public.png` payloads so the user can paste the image into Photos / Notes / Mail. Android uses `ClipboardManager.setPrimaryClip` with a `text/uri-list` `ClipData` when an image is provided. Web uses `ClipboardItem` (Chrome / Safari 16+).

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

`share()` prefers `navigator.share` with files when available, falls back to text-only `navigator.share`, then clipboard-write. `saveImage` uses an `<a download>`. `shareTo()` opens each destination's web sharer URL where one exists (X intent, `wa.me`, `t.me/share`, LinkedIn sharer, `mailto:`, `sms:`). App-only destinations (IG / FB / Snap Story, TikTok, IG Feed) reject on web — UI should hide those buttons via `isAppInstalled()` (always returns `false` in browsers).

## License

MIT — see [LICENSE](./LICENSE).
