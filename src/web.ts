import { WebPlugin } from '@capacitor/core';

import type {
  ImageInput,
  InstagramStoryOptions,
  IsAppInstalledOptions,
  IsAppInstalledResult,
  PermissionStatus,
  RichSharePlugin,
  SaveImageOptions,
  SaveImageResult,
  ShareOptions,
  ShareResult,
  TikTokShareOptions,
} from './definitions';

// ── helpers ─────────────────────────────────────────────────────────

function imageToDataUrl(image: ImageInput): string {
  if ('dataUrl' in image) return image.dataUrl;
  const mime = image.mimeType || 'image/png';
  return `data:${mime};base64,${image.base64}`;
}

async function dataUrlToBlob(dataUrl: string): Promise<Blob> {
  // Native fetch handles `data:` URLs across browsers.
  return await (await fetch(dataUrl)).blob();
}

function pickExt(mime: string): string {
  if (mime.includes('jpeg') || mime.includes('jpg')) return 'jpg';
  if (mime.includes('webp')) return 'webp';
  return 'png';
}

// ── implementation ──────────────────────────────────────────────────

export class RichShareWeb extends WebPlugin implements RichSharePlugin {
  /**
   * Web: prefer native `navigator.share()` with files when available
   * (mobile Safari + Chrome support files since 2021). Fall back to text-
   * only `navigator.share`, then to clipboard write of `text + url`.
   */
  async share(options: ShareOptions): Promise<ShareResult> {
    const text = options.text;
    const url = options.url;
    const title = options.title;

    if (typeof navigator === 'undefined') {
      return { completed: false, activityType: null };
    }

    // Build a File from the image, if any
    let file: File | undefined;
    if (options.image) {
      try {
        const dataUrl = imageToDataUrl(options.image);
        const blob = await dataUrlToBlob(dataUrl);
        const ext = pickExt(blob.type || 'image/png');
        file = new File([blob], `${options.filename || 'share'}.${ext}`, {
          type: blob.type || 'image/png',
        });
      } catch {
        /* fall through to text-only */
      }
    }

    // Try files-aware share first
    const nav = navigator as Navigator & {
      canShare?: (data: ShareData) => boolean;
      share?: (data: ShareData) => Promise<void>;
    };
    if (file && nav.canShare && nav.share) {
      const data: ShareData = { title, text, url, files: [file] };
      if (nav.canShare(data)) {
        try {
          await nav.share(data);
          return { completed: true, activityType: null };
        } catch (err) {
          // User cancelled or share failed — fall through
          if ((err as Error).name === 'AbortError') {
            return { completed: false, activityType: null };
          }
        }
      }
    }

    // Text-only share
    if (nav.share) {
      try {
        await nav.share({ title, text, url });
        return { completed: true, activityType: null };
      } catch (err) {
        if ((err as Error).name === 'AbortError') {
          return { completed: false, activityType: null };
        }
      }
    }

    // Clipboard fallback
    try {
      await navigator.clipboard.writeText(`${text || ''}${url ? `\n${url}` : ''}`.trim());
      return { completed: true, activityType: 'clipboard' };
    } catch {
      return { completed: false, activityType: null };
    }
  }

  /**
   * Web: trigger an `<a download>` click to download the PNG. On iOS WebView
   * this opens the native save-to-photos sheet; on desktop it goes to the
   * Downloads folder. There's no programmatic "save to gallery" on the web —
   * native platforms must implement the real Photos/MediaStore call.
   */
  async saveImage(options: SaveImageOptions): Promise<SaveImageResult> {
    const dataUrl = imageToDataUrl(options.image);
    const blob = await dataUrlToBlob(dataUrl);
    const ext = pickExt(blob.type || 'image/png');
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${options.filename || `nicoff-${Date.now()}`}.${ext}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 5000);
    return { assetId: '', path: null };
  }

  async checkPermissions(): Promise<PermissionStatus> {
    return { photos: 'granted' }; // Web — anchor download has no perm gate
  }

  async requestPermissions(): Promise<PermissionStatus> {
    return { photos: 'granted' };
  }

  async shareToInstagramStory(_options: InstagramStoryOptions): Promise<void> {
    throw this.unimplemented('shareToInstagramStory is native-only — use RichShare.share() on web.');
  }

  async shareToTikTok(_options: TikTokShareOptions): Promise<void> {
    throw this.unimplemented('shareToTikTok is native-only — use RichShare.share() on web.');
  }

  /** Web has no notion of "another app installed" — always false. */
  async isAppInstalled(_options: IsAppInstalledOptions): Promise<IsAppInstalledResult> {
    return { installed: false };
  }
}

// ── public web utilities ────────────────────────────────────────────

/**
 * Convenience helper for converting a Blob (e.g. canvas.toBlob output) to
 * a `data:` URL ready for the plugin's `ImageInput`. Lives in `web.ts`
 * because it depends on FileReader / browser APIs.
 */
export async function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result as string);
    r.onerror = reject;
    r.readAsDataURL(blob);
  });
}
