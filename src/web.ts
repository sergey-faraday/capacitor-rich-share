import { WebPlugin } from '@capacitor/core';

import type {
  CopyOptions,
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
  ShareToOptions,
  ShareToResult,
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
    a.download = `${options.filename || `share-${Date.now()}`}.${ext}`;
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

  /**
   * Web fallback for shareTo() — opens each destination's web sharer URL
   * in a new tab where one exists (X intent, WA wa.me, TG t.me/share,
   * FB sharer, LinkedIn). Native-only destinations (IG/Snap Story,
   * TikTok with image attachment) reject — UI should hide those buttons
   * on web via `isAppInstalled` (which returns false everywhere on web).
   */
  async shareTo(options: ShareToOptions): Promise<ShareToResult> {
    const open = (href: string) => {
      if (typeof window !== 'undefined') window.open(href, '_blank');
    };
    const enc = encodeURIComponent;
    const text = (options as any).text || '';
    const url = (options as any).url || '';

    switch (options.destination) {
      case 'system':
        await this.share({
          title: options.title,
          text: options.text,
          url: options.url,
          image: options.image,
          filename: options.filename,
        });
        return { completed: true, destination: 'system' };

      case 'twitter': {
        const tags = options.hashtags?.length ? `&hashtags=${enc(options.hashtags.join(','))}` : '';
        open(`https://x.com/intent/tweet?text=${enc(text)}&url=${enc(url)}${tags}`);
        return { completed: true, destination: 'twitter' };
      }

      case 'whatsapp': {
        const body = `${text}${url ? `\n${url}` : ''}`.trim();
        const phone = options.phone ? `phone=${enc(options.phone)}&` : '';
        open(`https://wa.me/?${phone}text=${enc(body)}`);
        return { completed: true, destination: 'whatsapp' };
      }

      case 'telegram':
        open(`https://t.me/share/url?url=${enc(url)}&text=${enc(text)}`);
        return { completed: true, destination: 'telegram' };

      case 'linkedin':
        open(`https://www.linkedin.com/sharing/share-offsite/?url=${enc(url)}`);
        return { completed: true, destination: 'linkedin' };

      case 'sms':
        open(`sms:${options.phone || ''}?body=${enc(text)}`);
        return { completed: true, destination: 'sms' };

      case 'email':
        open(`mailto:${options.to || ''}?subject=${enc(options.subject || '')}&body=${enc(options.body || '')}`);
        return { completed: true, destination: 'email' };

      case 'clipboard':
        await this.copy({ text: options.text, image: options.image });
        return { completed: true, destination: 'clipboard' };

      // App-only destinations — no useful web equivalent
      case 'instagram-story':
      case 'instagram-feed':
      case 'facebook-story':
      case 'snapchat-story':
      case 'tiktok':
        throw this.unimplemented(
          `shareTo({ destination: '${options.destination}' }) is native-only on web. Hide the button using isAppInstalled() (always false in browsers).`,
        );

      default:
        throw this.unimplemented(`Unknown destination: ${(options as any).destination}`);
    }
  }

  async copy(options: CopyOptions): Promise<void> {
    if (typeof navigator === 'undefined' || !navigator.clipboard) {
      throw new Error('Clipboard API unavailable');
    }
    if (options.image) {
      try {
        const dataUrl = imageToDataUrl(options.image);
        const blob = await dataUrlToBlob(dataUrl);
        const ClipboardItemCtor = typeof window !== 'undefined' ? (window as any).ClipboardItem : undefined;
        if (ClipboardItemCtor && (navigator.clipboard as any).write) {
          const items = [new ClipboardItemCtor({ [blob.type || 'image/png']: blob })];
          await (navigator.clipboard as any).write(items);
          return;
        }
      } catch {
        /* fall through to text-only */
      }
    }
    if (options.text) {
      await navigator.clipboard.writeText(options.text);
    }
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
