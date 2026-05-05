package com.ocool.plugins.richshare;

import android.Manifest;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.text.TextUtils;
import android.util.Base64;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.UUID;

/**
 * RichShare — Android implementation.
 *
 * Capabilities:
 *   · share()                 — Intent.ACTION_SEND with optional image+text
 *   · saveImage()             — MediaStore on Android 29+, FileOutputStream + scan on pre-29
 *   · shareToInstagramStory() — com.instagram.share.ADD_TO_STORY intent
 *   · shareToTikTok()         — com.zhiliaoapp.musically launch with image
 *   · isAppInstalled()        — PackageManager probe
 */
@CapacitorPlugin(
    name = "RichShare",
    permissions = {
        @Permission(strings = { Manifest.permission.WRITE_EXTERNAL_STORAGE }, alias = "photos")
    }
)
public class RichSharePlugin extends Plugin {

    private static final String TAG = "RichShare";

    // ─── share() ────────────────────────────────────────────────────────

    @PluginMethod
    public void share(PluginCall call) {
        String title = call.getString("title");
        String text = call.getString("text");
        String url = call.getString("url");
        String filename = call.getString("filename", "share");
        JSObject imageObj = call.getObject("image");

        Intent intent = new Intent(Intent.ACTION_SEND);
        boolean hasImage = false;
        if (imageObj != null) {
            Uri uri = writeImageToCacheUri(imageObj, filename);
            if (uri != null) {
                intent.setType("image/png");
                intent.putExtra(Intent.EXTRA_STREAM, uri);
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                hasImage = true;
            }
        }
        if (!hasImage) {
            intent.setType("text/plain");
        }

        StringBuilder body = new StringBuilder();
        if (text != null) body.append(text);
        if (url != null) {
            if (body.length() > 0) body.append("\n");
            body.append(url);
        }
        if (body.length() > 0) {
            intent.putExtra(Intent.EXTRA_TEXT, body.toString());
        }
        if (title != null) intent.putExtra(Intent.EXTRA_SUBJECT, title);

        Intent chooser = Intent.createChooser(intent, title);
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            getContext().startActivity(chooser);
        } catch (Exception e) {
            call.reject("Could not start share chooser: " + e.getMessage());
            return;
        }
        // Android offers no completion callback for the chooser. Resolve
        // optimistically — JS treats this as "user has been handed off".
        JSObject ret = new JSObject();
        ret.put("completed", true);
        ret.put("activityType", JSObject.NULL);
        call.resolve(ret);
    }

    // ─── saveImage() ────────────────────────────────────────────────────

    @PluginMethod
    public void saveImage(PluginCall call) {
        JSObject imageObj = call.getObject("image");
        if (imageObj == null) {
            call.reject("saveImage() requires `image`");
            return;
        }
        String filename = call.getString("filename", "nicoff-" + System.currentTimeMillis());
        String album = call.getString("album");

        // Android 29+ — scoped storage, no runtime permission needed.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveImageScoped(call, imageObj, filename, album);
            return;
        }

        // Android <29 — needs WRITE_EXTERNAL_STORAGE.
        if (getPermissionState("photos") != com.getcapacitor.PermissionState.GRANTED) {
            // Stash params for callback
            saveCall(call);
            requestPermissionForAlias("photos", call, "saveImagePermissionCallback");
            return;
        }
        saveImageLegacy(call, imageObj, filename, album);
    }

    @PermissionCallback
    private void saveImagePermissionCallback(PluginCall call) {
        if (getPermissionState("photos") != com.getcapacitor.PermissionState.GRANTED) {
            call.reject("Photo library permission denied");
            return;
        }
        JSObject imageObj = call.getObject("image");
        String filename = call.getString("filename", "nicoff-" + System.currentTimeMillis());
        String album = call.getString("album");
        saveImageLegacy(call, imageObj, filename, album);
    }

    private void saveImageScoped(PluginCall call, JSObject imageObj, String filename, String album) {
        try {
            Bitmap bitmap = decodeBitmap(imageObj);
            if (bitmap == null) {
                call.reject("Failed to decode image input");
                return;
            }

            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, filename + ".png");
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            String relativePath = album != null && !album.isEmpty()
                ? Environment.DIRECTORY_PICTURES + "/" + album
                : Environment.DIRECTORY_PICTURES;
            values.put(MediaStore.Images.Media.RELATIVE_PATH, relativePath);

            ContentResolver resolver = getContext().getContentResolver();
            Uri uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                call.reject("Could not create MediaStore record");
                return;
            }

            try (OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) {
                    call.reject("Could not open MediaStore output stream");
                    return;
                }
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
            }

            JSObject ret = new JSObject();
            ret.put("assetId", uri.toString());
            ret.put("path", JSObject.NULL);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("saveImage failed: " + e.getMessage());
        }
    }

    private void saveImageLegacy(PluginCall call, JSObject imageObj, String filename, String album) {
        try {
            Bitmap bitmap = decodeBitmap(imageObj);
            if (bitmap == null) {
                call.reject("Failed to decode image input");
                return;
            }

            File pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
            File dir = album != null && !album.isEmpty() ? new File(pictures, album) : pictures;
            if (!dir.exists()) dir.mkdirs();

            File file = new File(dir, filename + ".png");
            try (FileOutputStream out = new FileOutputStream(file)) {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
            }

            // Tell the gallery scanner so the image shows up immediately
            Intent scan = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
            scan.setData(Uri.fromFile(file));
            getContext().sendBroadcast(scan);

            JSObject ret = new JSObject();
            ret.put("assetId", file.getAbsolutePath());
            ret.put("path", file.getAbsolutePath());
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("saveImage failed: " + e.getMessage());
        }
    }

    // ─── permissions ───────────────────────────────────────────────────

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("photos", photosPermissionState());
        call.resolve(ret);
    }

    @PluginMethod
    public void requestPermissions(PluginCall call) {
        // 29+ doesn't need runtime permission — return granted immediately
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            JSObject ret = new JSObject();
            ret.put("photos", "granted");
            call.resolve(ret);
            return;
        }
        requestPermissionForAlias("photos", call, "permissionCallback");
    }

    @PermissionCallback
    private void permissionCallback(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("photos", photosPermissionState());
        call.resolve(ret);
    }

    private String photosPermissionState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return "granted";
        com.getcapacitor.PermissionState state = getPermissionState("photos");
        switch (state) {
            case GRANTED: return "granted";
            case DENIED:  return "denied";
            default:      return "prompt";
        }
    }

    // ─── shareToInstagramStory() ───────────────────────────────────────

    @PluginMethod
    public void shareToInstagramStory(PluginCall call) {
        JSObject stickerObj = call.getObject("stickerImage");
        if (stickerObj == null) {
            call.reject("shareToInstagramStory() requires `stickerImage`");
            return;
        }
        Uri stickerUri = writeImageToCacheUri(stickerObj, "ig-sticker-" + UUID.randomUUID());
        if (stickerUri == null) {
            call.reject("Failed to write sticker image to cache");
            return;
        }

        Intent intent = new Intent("com.instagram.share.ADD_TO_STORY");
        intent.setDataAndType(stickerUri, "image/png");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.putExtra("interactive_asset_uri", stickerUri);
        intent.putExtra("source_application", call.getString("sourceApplication", "com.nicoff.app"));

        // Optional background
        JSObject bgObj = call.getObject("backgroundImage");
        if (bgObj != null) {
            Uri bgUri = writeImageToCacheUri(bgObj, "ig-bg-" + UUID.randomUUID());
            if (bgUri != null) {
                intent.setDataAndType(bgUri, "image/png");
            }
        }

        String topColor = call.getString("backgroundTopColor");
        String bottomColor = call.getString("backgroundBottomColor");
        if (topColor != null) intent.putExtra("top_background_color", topColor);
        if (bottomColor != null) intent.putExtra("bottom_background_color", bottomColor);

        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("Instagram is not installed");
            return;
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().grantUriPermission("com.instagram.android", stickerUri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            getContext().startActivity(intent);
            call.resolve();
        } catch (Exception e) {
            call.reject("Failed to open Instagram: " + e.getMessage());
        }
    }

    // ─── shareToTikTok() ───────────────────────────────────────────────

    @PluginMethod
    public void shareToTikTok(PluginCall call) {
        JSObject imageObj = call.getObject("image");
        if (imageObj == null) {
            call.reject("shareToTikTok() requires `image`");
            return;
        }
        Uri uri = writeImageToCacheUri(imageObj, "tt-" + UUID.randomUUID());
        if (uri == null) {
            call.reject("Failed to write image to cache");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("image/png");
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        intent.setPackage("com.zhiliaoapp.musically");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("TikTok is not installed");
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            getContext().startActivity(intent);
            call.resolve();
        } catch (Exception e) {
            call.reject("Failed to open TikTok: " + e.getMessage());
        }
    }

    // ─── isAppInstalled() ──────────────────────────────────────────────

    @PluginMethod
    public void isAppInstalled(PluginCall call) {
        String scheme = call.getString("scheme");
        if (scheme == null || scheme.isEmpty()) {
            call.reject("isAppInstalled() requires `scheme`");
            return;
        }
        // Map common schemes to package names
        String pkg = packageNameForScheme(scheme);
        boolean installed = false;
        if (pkg != null) {
            try {
                PackageManager pm = getContext().getPackageManager();
                pm.getPackageInfo(pkg, 0);
                installed = true;
            } catch (PackageManager.NameNotFoundException ignored) {
                installed = false;
            }
        } else {
            // Fallback — Intent resolve via VIEW + scheme:// URL
            String probe = scheme.contains("://") ? scheme : scheme + "://";
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(probe));
            installed = intent.resolveActivity(getContext().getPackageManager()) != null;
        }
        JSObject ret = new JSObject();
        ret.put("installed", installed);
        call.resolve(ret);
    }

    private String packageNameForScheme(String scheme) {
        String s = scheme.replace("://", "").toLowerCase();
        switch (s) {
            case "instagram":
            case "instagram-stories":
            case "instagram-feed":
                return "com.instagram.android";
            case "snapchat":
            case "snapchat-story":
                return "com.snapchat.android";
            case "tiktok":
            case "snssdk1233":
                return "com.zhiliaoapp.musically";
            case "whatsapp":
                return "com.whatsapp";
            case "twitter":
            case "x":
                return "com.twitter.android";
            case "telegram":
            case "tg":
                return "org.telegram.messenger";
            case "facebook":
            case "facebook-stories":
            case "facebook-story":
            case "fb":
                return "com.facebook.katana";
            case "linkedin":
                return "com.linkedin.android";
            default:
                return null;
        }
    }

    // ─── helpers ───────────────────────────────────────────────────────

    // ─── shareTo() — unified router ────────────────────────────────────

    @PluginMethod
    public void shareTo(PluginCall call) {
        String destination = call.getString("destination");
        if (destination == null) {
            call.reject("shareTo() requires `destination`");
            return;
        }
        switch (destination) {
            case "system":            share(call); return;
            case "instagram-story":   shareToInstagramStory(call); return;
            case "facebook-story":    shareToFacebookStoryInternal(call); return;
            case "snapchat-story":    shareToSnapchatInternal(call); return;
            case "instagram-feed":    shareToInstagramFeedInternal(call); return;
            case "tiktok":            shareToTikTok(call); return;
            case "whatsapp":          openTargetedSend(call, "com.whatsapp", destination); return;
            case "telegram":          openTargetedSend(call, "org.telegram.messenger", destination); return;
            case "twitter":           openTargetedSend(call, "com.twitter.android", destination); return;
            case "linkedin":          openTargetedSend(call, "com.linkedin.android", destination); return;
            case "sms":               openSMS(call); return;
            case "email":             openEmail(call); return;
            case "clipboard":         copy(call); return;
            default:
                call.reject("Unknown destination: " + destination);
        }
    }

    // ─── copy() ────────────────────────────────────────────────────────

    @PluginMethod
    public void copy(PluginCall call) {
        String text = call.getString("text");
        JSObject imageObj = call.getObject("image");
        ClipboardManager cm = (ClipboardManager) getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm == null) {
            call.reject("Clipboard service unavailable");
            return;
        }

        if (imageObj != null) {
            Uri uri = writeImageToCacheUri(imageObj, "clip-" + UUID.randomUUID());
            if (uri != null) {
                ClipData clip = ClipData.newUri(getContext().getContentResolver(), "RichShare image", uri);
                cm.setPrimaryClip(clip);
                call.resolve();
                return;
            }
        }
        if (text != null) {
            cm.setPrimaryClip(ClipData.newPlainText("RichShare", text));
            call.resolve();
            return;
        }
        call.reject("copy() requires text or image");
    }

    // ─── per-destination helpers ───────────────────────────────────────

    /**
     * Build an Intent.ACTION_SEND with optional image+text, target it at a
     * specific package, fire it. Used for WhatsApp / Twitter / Telegram /
     * LinkedIn — destinations whose intent flow is "system share but locked
     * to one app".
     */
    private void openTargetedSend(PluginCall call, String packageName, String destination) {
        String text = call.getString("text");
        String url = call.getString("url");
        JSObject imageObj = call.getObject("image");

        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setPackage(packageName);
        boolean hasImage = false;
        if (imageObj != null) {
            Uri uri = writeImageToCacheUri(imageObj, destination + "-" + UUID.randomUUID());
            if (uri != null) {
                intent.setType("image/png");
                intent.putExtra(Intent.EXTRA_STREAM, uri);
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                getContext().grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                hasImage = true;
            }
        }
        if (!hasImage) intent.setType("text/plain");

        StringBuilder body = new StringBuilder();
        if (text != null) body.append(text);
        if (url != null) {
            if (body.length() > 0) body.append("\n");
            body.append(url);
        }
        if (body.length() > 0) intent.putExtra(Intent.EXTRA_TEXT, body.toString());

        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject(destination + " is not installed");
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", destination);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open " + destination + ": " + e.getMessage());
        }
    }

    private void openSMS(PluginCall call) {
        String text = call.getString("text", "");
        String phone = call.getString("phone", "");
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(
            "smsto:" + phone
        ));
        intent.putExtra("sms_body", text);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("No SMS app installed");
            return;
        }
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", "sms");
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open SMS: " + e.getMessage());
        }
    }

    private void openEmail(PluginCall call) {
        String to = call.getString("to", "");
        String subject = call.getString("subject", "");
        String body = call.getString("body", "");
        Intent intent = new Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:" + to));
        if (!subject.isEmpty()) intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        if (!body.isEmpty()) intent.putExtra(Intent.EXTRA_TEXT, body);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("No email app installed");
            return;
        }
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", "email");
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open email: " + e.getMessage());
        }
    }

    private void shareToFacebookStoryInternal(PluginCall call) {
        JSObject stickerObj = call.getObject("stickerImage");
        if (stickerObj == null) {
            call.reject("facebook-story requires `stickerImage`");
            return;
        }
        Uri stickerUri = writeImageToCacheUri(stickerObj, "fb-sticker-" + UUID.randomUUID());
        if (stickerUri == null) {
            call.reject("Failed to write sticker to cache");
            return;
        }
        Intent intent = new Intent("com.facebook.stories.ADD_TO_STORY");
        intent.setDataAndType(stickerUri, "image/png");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.putExtra("interactive_asset_uri", stickerUri);
        String topColor = call.getString("backgroundTopColor");
        String bottomColor = call.getString("backgroundBottomColor");
        if (topColor != null) intent.putExtra("top_background_color", topColor);
        if (bottomColor != null) intent.putExtra("bottom_background_color", bottomColor);
        intent.setPackage("com.facebook.katana");

        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("Facebook is not installed");
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().grantUriPermission("com.facebook.katana", stickerUri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", "facebook-story");
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open Facebook: " + e.getMessage());
        }
    }

    private void shareToSnapchatInternal(PluginCall call) {
        JSObject stickerObj = call.getObject("stickerImage");
        if (stickerObj == null) {
            call.reject("snapchat-story requires `stickerImage`");
            return;
        }
        Uri uri = writeImageToCacheUri(stickerObj, "snap-" + UUID.randomUUID());
        if (uri == null) {
            call.reject("Failed to write sticker to cache");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("image/png");
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        intent.setPackage("com.snapchat.android");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("Snapchat is not installed");
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().grantUriPermission("com.snapchat.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", "snapchat-story");
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open Snapchat: " + e.getMessage());
        }
    }

    private void shareToInstagramFeedInternal(PluginCall call) {
        JSObject imageObj = call.getObject("image");
        if (imageObj == null) {
            call.reject("instagram-feed requires `image`");
            return;
        }
        Uri uri = writeImageToCacheUri(imageObj, "ig-feed-" + UUID.randomUUID());
        if (uri == null) {
            call.reject("Failed to write image to cache");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("image/png");
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        intent.setPackage("com.instagram.android");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        if (intent.resolveActivity(getContext().getPackageManager()) == null) {
            call.reject("Instagram is not installed");
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            getContext().startActivity(intent);
            JSObject ret = new JSObject();
            ret.put("completed", true);
            ret.put("destination", "instagram-feed");
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to open Instagram: " + e.getMessage());
        }
    }

    /** Decode a `dataUrl` or raw `base64` payload from JS. */
    private Bitmap decodeBitmap(JSObject imageObj) {
        try {
            String dataUrl = imageObj.getString("dataUrl");
            String base64 = imageObj.getString("base64");
            String payload = null;
            if (!TextUtils.isEmpty(dataUrl)) {
                int comma = dataUrl.indexOf(',');
                payload = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
            } else if (!TextUtils.isEmpty(base64)) {
                payload = base64;
            }
            if (payload == null) return null;
            byte[] bytes = Base64.decode(payload, Base64.DEFAULT);
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        } catch (Exception e) {
            return null;
        }
    }

    /** Write image to app cache and return a content:// URI via FileProvider. */
    private Uri writeImageToCacheUri(JSObject imageObj, String filenameBase) {
        try {
            Bitmap bitmap = decodeBitmap(imageObj);
            if (bitmap == null) return null;
            File cacheDir = new File(getContext().getCacheDir(), "shared");
            if (!cacheDir.exists()) cacheDir.mkdirs();
            File file = new File(cacheDir, filenameBase + ".png");
            try (FileOutputStream out = new FileOutputStream(file)) {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
            }
            String authority = getContext().getPackageName() + ".richshare.fileprovider";
            return FileProvider.getUriForFile(getContext(), authority, file);
        } catch (Exception e) {
            return null;
        }
    }
}
