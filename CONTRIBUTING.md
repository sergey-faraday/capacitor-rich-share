# Contributing

Thanks for your interest! A few notes:

## Local setup

```bash
npm install
npm run build
```

## Running on a device

The plugin needs a Capacitor host app to test natively. Any Capacitor 7/8 project will do — install this package via local path:

```bash
# in your test app
npm install /path/to/capacitor-rich-share
npx cap sync
```

## Testing matrix

When changing native code, please test against:
- iOS device with Instagram / TikTok / WhatsApp installed (deep-links)
- iOS Simulator (system share sheet, `mailto:`, `sms:`)
- Android 12+ (scoped storage `MediaStore`, package visibility)
- Android <10 device or emulator (`WRITE_EXTERNAL_STORAGE` legacy path)

## Code style

- TS: `npm run lint` (eslint + prettier)
- Swift: keep style consistent with the existing `RichSharePlugin.swift`
- Java: 2-space indent, single-import lines

## PRs

Please update `CHANGELOG.md` under the `[Unreleased]` section.
