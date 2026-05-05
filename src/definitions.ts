// ─── Image input ─────────────────────────────────────────────────────
//
// All image-bearing methods accept either:
//   · a `data:image/png;base64,...` data URL, or
//   · a raw base64 string (no `data:` prefix)
//
// Web Blob/File inputs aren't accepted directly because the JS↔native
// bridge serialises everything through JSON. Convert in JS first via
// `await blob2dataurl(blob)` (the plugin re-exports a helper) and pass
// the data URL.

export type ImageInput =
  | { dataUrl: string }                    // "data:image/png;base64,iVBORw0KGgo..."
  | { base64: string; mimeType?: string }; // raw base64; mime defaults to image/png

// ─── Plain "system share sheet" share ────────────────────────────────

export interface ShareOptions {
  /** Title of the share — passed to native share sheet (Android uses this as activity-chooser title). */
  title?: string;
  /** Plain-text caption to share. */
  text?: string;
  /** Optional URL appended to the share. */
  url?: string;
  /** Optional image — when set, native sheet receives image+text together. */
  image?: ImageInput;
  /** Filename hint for the temporary image file (without extension). */
  filename?: string;
}

export interface ShareResult {
  /** Did the user actually complete a share, or did they cancel the sheet? */
  completed: boolean;
  /** Identifier of the destination the user chose (iOS UTI / Android package name). null if cancelled. */
  activityType: string | null;
}

// ─── Save image to device library ────────────────────────────────────

export interface SaveImageOptions {
  image: ImageInput;
  /**
   * Filename without extension. If omitted, defaults to a timestamp-based
   * name. iOS Photos ignores filename for the in-album asset display name.
   */
  filename?: string;
  /**
   * Optional album name. When provided:
   *   · iOS — creates the album in Photos if missing and saves the image into it.
   *   · Android — sets the relative path under `Pictures/<album>/`.
   */
  album?: string;
}

export interface SaveImageResult {
  /** Localised asset identifier (iOS PHAsset localIdentifier / Android content URI). */
  assetId: string;
  /** Absolute filesystem path where the image landed (Android) or null (iOS — Photos paths are private). */
  path: string | null;
}

// ─── Permission state ────────────────────────────────────────────────

export type PermissionState = 'prompt' | 'granted' | 'denied' | 'limited';

export interface PermissionStatus {
  /** Photo-library write permission. iOS only — Android pre-29 needs WRITE_EXTERNAL_STORAGE; 29+ uses scoped storage and doesn't need a runtime grant. */
  photos: PermissionState;
}

// ─── Deep-link helpers ───────────────────────────────────────────────

export interface InstagramStoryOptions {
  /** Foreground sticker image. Recommended 9:16 PNG with transparency. */
  stickerImage: ImageInput;
  /** Optional background image. If omitted, IG fills with `backgroundTopColor` → `backgroundBottomColor`. */
  backgroundImage?: ImageInput;
  /** Top hex (`#RRGGBB`) for the gradient background — only used when backgroundImage is absent. */
  backgroundTopColor?: string;
  /** Bottom hex for the gradient background. */
  backgroundBottomColor?: string;
  /** Source-application identifier registered with Instagram for attribution. */
  sourceApplication?: string;
}

export interface TikTokShareOptions {
  /** Image to share to TikTok. TikTok will open with the image attached for editing. */
  image: ImageInput;
  /** TikTok client key (from TikTok developer console). */
  clientKey?: string;
}

export interface IsAppInstalledOptions {
  /** URL scheme to test (e.g. "instagram", "snapchat", "tiktok", "whatsapp"). */
  scheme: string;
}

export interface IsAppInstalledResult {
  installed: boolean;
}

// ─── shareTo() — unified destination router ──────────────────────────
//
// Discriminated union: each destination accepts only the fields that
// destination supports. The native side picks the right URL scheme /
// targeted Intent / pasteboard payload based on `destination`.

export type ShareDestination =
  | 'system'           // OS share sheet (same as share())
  | 'instagram-story'
  | 'instagram-feed'
  | 'facebook-story'
  | 'snapchat-story'
  | 'tiktok'
  | 'whatsapp'
  | 'telegram'
  | 'twitter'          // accepts X too
  | 'linkedin'
  | 'sms'
  | 'email'
  | 'clipboard';

export type ShareToOptions =
  | { destination: 'system'; text?: string; url?: string; image?: ImageInput; title?: string; filename?: string }
  | ({ destination: 'instagram-story' } & InstagramStoryOptions)
  | { destination: 'instagram-feed'; image: ImageInput }
  | ({ destination: 'facebook-story' } & InstagramStoryOptions)  // FB Story uses the same sticker/background protocol as IG
  | { destination: 'snapchat-story'; stickerImage: ImageInput; attachmentUrl?: string; sourceApplication?: string }
  | { destination: 'tiktok'; image: ImageInput }
  | { destination: 'whatsapp'; text?: string; url?: string; image?: ImageInput; phone?: string }
  | { destination: 'telegram'; text?: string; url?: string; image?: ImageInput }
  | { destination: 'twitter'; text?: string; url?: string; image?: ImageInput; hashtags?: string[] }
  | { destination: 'linkedin'; text?: string; url?: string }
  | { destination: 'sms'; text?: string; phone?: string; image?: ImageInput }
  | { destination: 'email'; subject?: string; body?: string; to?: string; image?: ImageInput }
  | { destination: 'clipboard'; text?: string; image?: ImageInput };

export interface ShareToResult {
  /** Did the share complete (or at least hand-off succeed)? */
  completed: boolean;
  /** Same destination string echoed back. */
  destination: ShareDestination;
}

// ─── copy() — clipboard write convenience ────────────────────────────

export interface CopyOptions {
  /** Text to write to the clipboard. */
  text?: string;
  /**
   * Optional image. iOS writes the image to `UIPasteboard.general` so it
   * can be pasted into Photos/Notes/Mail. Android writes the image as a
   * `text/uri-list` ClipData with a content:// URI from the FileProvider.
   * Web copies the image as a Blob via `ClipboardItem` (Chrome/Safari 16+).
   */
  image?: ImageInput;
}

// ─── Plugin interface ────────────────────────────────────────────────

export interface RichSharePlugin {
  /**
   * Open the system share sheet. When `image` is provided, the native side
   * writes a temp PNG file and shares it together with the text/url so the
   * destination app receives both pieces.
   *
   * @example
   * await RichShare.share({ text: 'Day 30 nicotine-free 🎉', url: 'https://nicoff.app' });
   * await RichShare.share({ image: { dataUrl }, text: 'My streak', url: 'https://nicoff.app' });
   */
  share(options: ShareOptions): Promise<ShareResult>;

  /**
   * Save an image to the device's photo library. Triggers the OS permission
   * prompt the first time. On Android 29+ the image goes to scoped storage
   * (no runtime permission needed); pre-29 requires `WRITE_EXTERNAL_STORAGE`.
   *
   * @example
   * await RichShare.saveImage({ image: { dataUrl }, filename: 'nicoff-day-30', album: 'nicoff' });
   */
  saveImage(options: SaveImageOptions): Promise<SaveImageResult>;

  /**
   * Check / request photo-library write permission. Returns the current
   * state on the next tick. Calling before `saveImage` lets you customise
   * the rationale UI shown to users.
   */
  checkPermissions(): Promise<PermissionStatus>;
  requestPermissions(): Promise<PermissionStatus>;

  /**
   * Open Instagram Story directly with the given sticker / background.
   * Throws if Instagram isn't installed — wrap in a try/catch and fall
   * back to the system sheet.
   *
   * On iOS, uses the `instagram-stories://share?source_application=...`
   * URL scheme + `UIPasteboard` general items as documented by Meta.
   *
   * On Android, uses `Intent.ACTION_SEND` with `com.instagram.share.ADD_TO_STORY`
   * action and content URIs from the Instagram FileProvider authority.
   */
  shareToInstagramStory(options: InstagramStoryOptions): Promise<void>;

  /**
   * Open TikTok with the given image attached, ready for the user to edit
   * + post. Requires the TikTok app installed and (on iOS) the
   * `LSApplicationQueriesSchemes` entry in Info.plist.
   */
  shareToTikTok(options: TikTokShareOptions): Promise<void>;

  /**
   * Detect whether an external app supporting the given URL scheme is
   * installed. Useful for hiding destination icons that won't work on the
   * current device.
   *
   * iOS requires the scheme to be listed in `LSApplicationQueriesSchemes`
   * in Info.plist or the call returns `false` regardless of installation.
   */
  isAppInstalled(options: IsAppInstalledOptions): Promise<IsAppInstalledResult>;

  /**
   * Unified destination router. Pick a `destination` and pass the fields
   * that destination supports. Internally routes to the right native API:
   *   · 'system'                    → UIActivityViewController / Intent.createChooser
   *   · 'instagram-story'           → instagram-stories:// + UIPasteboard
   *   · 'facebook-story'            → facebook-stories:// (same protocol as IG)
   *   · 'snapchat-story'            → snapchat://creativekit/camera + UIPasteboard
   *   · 'instagram-feed'            → Intent ADD_TO_FEED on Android, opens IG with image on iOS
   *   · 'tiktok'                    → snssdk1233:// (saves to camera roll first on iOS)
   *   · 'whatsapp'                  → whatsapp://send + temp file
   *   · 'telegram'                  → tg://msg_url + temp file
   *   · 'twitter'                   → twitter://post + intent
   *   · 'linkedin'                  → linkedin://shareArticle (text+url only — no image)
   *   · 'sms'                       → sms:?body=
   *   · 'email'                     → mailto:?subject=&body=
   *   · 'clipboard'                 → UIPasteboard / ClipboardManager
   *
   * Throws if the destination's app isn't installed (see `isAppInstalled`).
   */
  shareTo(options: ShareToOptions): Promise<ShareToResult>;

  /**
   * Copy text and/or image to the system clipboard. Convenience wrapper
   * around the platform clipboard API.
   */
  copy(options: CopyOptions): Promise<void>;
}
