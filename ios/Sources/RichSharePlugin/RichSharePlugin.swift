import Capacitor
import Foundation
import Photos
import UIKit

@objc(RichSharePlugin)
public class RichSharePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RichSharePlugin"
    public let jsName = "RichShare"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveImage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareToInstagramStory", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareToTikTok", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAppInstalled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareTo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "copy", returnType: CAPPluginReturnPromise),
    ]

    // MARK: - share()

    @objc func share(_ call: CAPPluginCall) {
        let title = call.getString("title")
        let text = call.getString("text")
        let url = call.getString("url")
        let filename = call.getString("filename") ?? "share"
        let imageObj = call.getObject("image")

        var items: [Any] = []

        if let imageObj = imageObj, let img = decodeImageInput(imageObj) {
            // Write to temp PNG so AirDrop / IG / Messages all receive a real file
            // (some destinations refuse raw UIImage). Returns nil on disk failure.
            if let fileURL = writeTempImage(img, filename: filename) {
                items.append(fileURL)
            } else {
                items.append(img)
            }
        }
        if let text = text { items.append(text) }
        if let url = url, let u = URL(string: url) { items.append(u) }

        guard !items.isEmpty else {
            call.reject("share() requires at least one of: image, text, url")
            return
        }

        DispatchQueue.main.async {
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let title = title { activity.setValue(title, forKey: "subject") }

            activity.completionWithItemsHandler = { activityType, completed, _, error in
                if let error = error {
                    call.reject("Share error: \(error.localizedDescription)")
                    return
                }
                call.resolve([
                    "completed": completed,
                    "activityType": activityType?.rawValue ?? NSNull(),
                ])
            }

            // iPad — anchor the popover to the centre of the bridge view
            if let popover = activity.popoverPresentationController, let bridgeView = self.bridge?.viewController?.view {
                popover.sourceView = bridgeView
                popover.sourceRect = CGRect(x: bridgeView.bounds.midX, y: bridgeView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            self.bridge?.viewController?.present(activity, animated: true, completion: nil)
        }
    }

    // MARK: - saveImage()

    @objc func saveImage(_ call: CAPPluginCall) {
        guard let imageObj = call.getObject("image"), let img = decodeImageInput(imageObj) else {
            call.reject("saveImage() requires an `image` parameter (dataUrl or base64).")
            return
        }
        let album = call.getString("album")

        ensurePhotoPermission { granted in
            guard granted else {
                call.reject("Photo library permission denied")
                return
            }

            self.savePhoto(image: img, albumName: album) { result in
                switch result {
                case .success(let assetId):
                    call.resolve([
                        "assetId": assetId,
                        "path": NSNull(),
                    ])
                case .failure(let err):
                    call.reject("saveImage failed: \(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: - permissions

    @objc func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["photos": photosPermissionState()])
    }

    @objc func requestPermissions(_ call: CAPPluginCall) {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
                call.resolve(["photos": self.photosPermissionState()])
            }
            return
        }
        call.resolve(["photos": photosPermissionState()])
    }

    private func photosPermissionState() -> String {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized: return "granted"
        case .limited: return "limited"
        case .denied, .restricted: return "denied"
        case .notDetermined: return "prompt"
        @unknown default: return "prompt"
        }
    }

    // MARK: - Instagram Story deep link

    @objc func shareToInstagramStory(_ call: CAPPluginCall) {
        guard let stickerObj = call.getObject("stickerImage"), let sticker = decodeImageInput(stickerObj) else {
            call.reject("shareToInstagramStory() requires `stickerImage`")
            return
        }
        let bgImage = (call.getObject("backgroundImage") as [String: Any]?).flatMap(decodeImageInput)
        let topColor = call.getString("backgroundTopColor")
        let bottomColor = call.getString("backgroundBottomColor")
        let sourceApp = call.getString("sourceApplication") ?? "com.nicoff.app"

        guard let scheme = URL(string: "instagram-stories://share?source_application=\(sourceApp)") else {
            call.reject("Could not build Instagram URL scheme")
            return
        }

        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(scheme) else {
                call.reject("Instagram is not installed")
                return
            }

            // Pasteboard items per Instagram docs
            // https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/
            var pasteboardItems: [String: Any] = [:]
            if let stickerData = sticker.pngData() {
                pasteboardItems["com.instagram.sharedSticker.stickerImage"] = stickerData
            }
            if let bgImage = bgImage, let bgData = bgImage.pngData() {
                pasteboardItems["com.instagram.sharedSticker.backgroundImage"] = bgData
            }
            if let top = topColor { pasteboardItems["com.instagram.sharedSticker.backgroundTopColor"] = top }
            if let bottom = bottomColor { pasteboardItems["com.instagram.sharedSticker.backgroundBottomColor"] = bottom }

            let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
                .expirationDate: Date().addingTimeInterval(60 * 5)
            ]
            UIPasteboard.general.setItems([pasteboardItems], options: pasteboardOptions)

            UIApplication.shared.open(scheme, options: [:]) { opened in
                if opened {
                    call.resolve()
                } else {
                    call.reject("Failed to open Instagram")
                }
            }
        }
    }

    // MARK: - TikTok deep link

    @objc func shareToTikTok(_ call: CAPPluginCall) {
        guard let imageObj = call.getObject("image"), let img = decodeImageInput(imageObj) else {
            call.reject("shareToTikTok() requires `image`")
            return
        }
        // TikTok uses snssdk1233:// for share-to. The Open SDK's full file
        // share is gated behind a developer-portal-issued client key — for
        // the lightweight "open with image attached" deep link, we save the
        // image to the camera roll and let TikTok pick it up.
        ensurePhotoPermission { granted in
            guard granted else {
                call.reject("Photo library permission required for TikTok share")
                return
            }
            self.savePhoto(image: img, albumName: nil) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        guard let scheme = URL(string: "snssdk1233://"), UIApplication.shared.canOpenURL(scheme) else {
                            call.reject("TikTok is not installed")
                            return
                        }
                        UIApplication.shared.open(scheme, options: [:]) { opened in
                            if opened { call.resolve() } else { call.reject("Failed to open TikTok") }
                        }
                    }
                case .failure(let err):
                    call.reject("TikTok share failed: \(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: - isAppInstalled

    @objc func isAppInstalled(_ call: CAPPluginCall) {
        guard let scheme = call.getString("scheme") else {
            call.reject("isAppInstalled() requires a `scheme`")
            return
        }
        // Normalise — accept "instagram" or "instagram://"
        let probe = scheme.contains("://") ? scheme : "\(scheme)://"
        DispatchQueue.main.async {
            if let url = URL(string: probe) {
                call.resolve(["installed": UIApplication.shared.canOpenURL(url)])
            } else {
                call.resolve(["installed": false])
            }
        }
    }

    // MARK: - private helpers

    private func decodeImageInput(_ obj: [String: Any]) -> UIImage? {
        if let dataUrl = obj["dataUrl"] as? String {
            // Strip "data:...;base64," prefix
            let comma = dataUrl.range(of: ",")
            let base64 = comma.map { String(dataUrl[$0.upperBound...]) } ?? dataUrl
            if let data = Data(base64Encoded: base64) { return UIImage(data: data) }
        }
        if let base64 = obj["base64"] as? String, let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        return nil
    }

    private func writeTempImage(_ image: UIImage, filename: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func ensurePhotoPermission(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            completion(true)
            return
        }
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
            return
        }
        completion(false)
    }

    // MARK: - shareTo() — unified router

    @objc func shareTo(_ call: CAPPluginCall) {
        guard let destination = call.getString("destination") else {
            call.reject("shareTo() requires `destination`")
            return
        }

        switch destination {
        case "system":
            // Forward to share()
            self.share(call)
            return

        case "instagram-story":
            self.shareToInstagramStory(call)
            return

        case "facebook-story":
            self.shareToFacebookStory(call)
            return

        case "snapchat-story":
            self.shareToSnapchat(call)
            return

        case "instagram-feed":
            self.shareToInstagramFeed(call)
            return

        case "tiktok":
            self.shareToTikTok(call)
            return

        case "whatsapp":
            self.openWhatsApp(call)
            return

        case "telegram":
            self.openTelegram(call)
            return

        case "twitter":
            self.openTwitter(call)
            return

        case "linkedin":
            self.openLinkedIn(call)
            return

        case "sms":
            self.openSMS(call)
            return

        case "email":
            self.openEmail(call)
            return

        case "clipboard":
            self.copy(call)
            // copy() resolves with no payload — wrap to ShareToResult
            return

        default:
            call.reject("Unknown destination: \(destination)")
            return
        }
    }

    // MARK: - copy()

    @objc func copy(_ call: CAPPluginCall) {
        let text = call.getString("text")
        let imageObj = call.getObject("image")
        var items: [String: Any] = [:]
        if let text = text { items["public.utf8-plain-text"] = text }
        if let imageObj = imageObj, let img = decodeImageInput(imageObj), let data = img.pngData() {
            items["public.png"] = data
        }
        guard !items.isEmpty else {
            call.reject("copy() requires text or image")
            return
        }
        DispatchQueue.main.async {
            UIPasteboard.general.setItems([items])
            call.resolve()
        }
    }

    // MARK: - per-destination openers

    private func openExternalURL(_ urlString: String, scheme: String, call: CAPPluginCall, destinationKey: String) {
        guard let probe = URL(string: scheme), let url = URL(string: urlString) else {
            call.reject("Invalid URL for \(destinationKey)")
            return
        }
        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(probe) else {
                call.reject("\(destinationKey) is not installed or scheme not allowed (LSApplicationQueriesSchemes)")
                return
            }
            UIApplication.shared.open(url, options: [:]) { ok in
                if ok {
                    call.resolve(["completed": true, "destination": destinationKey])
                } else {
                    call.reject("Failed to open \(destinationKey)")
                }
            }
        }
    }

    private func openTwitter(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let url = call.getString("url") ?? ""
        let hashtags = (call.getArray("hashtags") as? [String])?.joined(separator: ",") ?? ""
        var components = URLComponents(string: "twitter://post")
        var query: [URLQueryItem] = []
        if !text.isEmpty || !url.isEmpty {
            let body = "\(text)\(url.isEmpty ? "" : "\n\(url)")"
            query.append(URLQueryItem(name: "message", value: body))
        }
        if !hashtags.isEmpty {
            query.append(URLQueryItem(name: "hashtags", value: hashtags))
        }
        components?.queryItems = query.isEmpty ? nil : query
        let primary = components?.url?.absoluteString ?? "twitter://post"
        // Fallback to web intent if Twitter is not installed
        if let twitter = URL(string: "twitter://"), UIApplication.shared.canOpenURL(twitter) {
            openExternalURL(primary, scheme: "twitter://", call: call, destinationKey: "twitter")
        } else {
            var web = URLComponents(string: "https://x.com/intent/tweet")!
            web.queryItems = query.map { URLQueryItem(name: $0.name == "message" ? "text" : $0.name, value: $0.value) }
            openExternalURL(web.url!.absoluteString, scheme: "https://", call: call, destinationKey: "twitter")
        }
    }

    private func openWhatsApp(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let url = call.getString("url") ?? ""
        let phone = call.getString("phone") ?? ""
        // Image attachment via whatsapp:// is unreliable across versions —
        // route image+text through the system sheet pre-filtered with WA.
        if let imageObj = call.getObject("image"), let img = decodeImageInput(imageObj),
           let fileURL = writeTempImage(img, filename: "wa-share") {
            DispatchQueue.main.async {
                let activity = UIActivityViewController(activityItems: [fileURL, text], applicationActivities: nil)
                activity.excludedActivityTypes = nil
                if let popover = activity.popoverPresentationController, let view = self.bridge?.viewController?.view {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                self.bridge?.viewController?.present(activity, animated: true) {
                    call.resolve(["completed": true, "destination": "whatsapp"])
                }
            }
            return
        }
        let body = "\(text)\(url.isEmpty ? "" : "\n\(url)")"
        let q = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phoneQ = phone.isEmpty ? "" : "phone=\(phone)&"
        let primary = "whatsapp://send?\(phoneQ)text=\(q)"
        openExternalURL(primary, scheme: "whatsapp://", call: call, destinationKey: "whatsapp")
    }

    private func openTelegram(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let url = call.getString("url") ?? ""
        let urlEnc = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let textEnc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let primary = "tg://msg_url?url=\(urlEnc)&text=\(textEnc)"
        openExternalURL(primary, scheme: "tg://", call: call, destinationKey: "telegram")
    }

    private func openLinkedIn(_ call: CAPPluginCall) {
        let url = call.getString("url") ?? ""
        let urlEnc = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let primary = "linkedin://shareArticle?mini=true&url=\(urlEnc)"
        openExternalURL(primary, scheme: "linkedin://", call: call, destinationKey: "linkedin")
    }

    private func openSMS(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let phone = call.getString("phone") ?? ""
        let bodyEnc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let primary = "sms:\(phone)&body=\(bodyEnc)"
        openExternalURL(primary, scheme: "sms:", call: call, destinationKey: "sms")
    }

    private func openEmail(_ call: CAPPluginCall) {
        let to = call.getString("to") ?? ""
        let subject = call.getString("subject") ?? ""
        let body = call.getString("body") ?? ""
        let subjectEnc = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEnc = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let primary = "mailto:\(to)?subject=\(subjectEnc)&body=\(bodyEnc)"
        openExternalURL(primary, scheme: "mailto:", call: call, destinationKey: "email")
    }

    private func shareToFacebookStory(_ call: CAPPluginCall) {
        // Same protocol as IG Story but different scheme + pasteboard prefix
        guard let stickerObj = call.getObject("stickerImage"), let sticker = decodeImageInput(stickerObj) else {
            call.reject("shareToFacebookStory requires `stickerImage`")
            return
        }
        let bgImage = (call.getObject("backgroundImage") as [String: Any]?).flatMap(decodeImageInput)
        let topColor = call.getString("backgroundTopColor")
        let bottomColor = call.getString("backgroundBottomColor")
        let appId = call.getString("sourceApplication") ?? ""

        guard let scheme = URL(string: "facebook-stories://share?app_id=\(appId)") else {
            call.reject("Could not build Facebook URL")
            return
        }

        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(scheme) else {
                call.reject("Facebook is not installed")
                return
            }
            var items: [String: Any] = [:]
            if let stickerData = sticker.pngData() {
                items["com.facebook.sharedSticker.stickerImage"] = stickerData
            }
            if let bgImage = bgImage, let bgData = bgImage.pngData() {
                items["com.facebook.sharedSticker.backgroundImage"] = bgData
            }
            if let top = topColor { items["com.facebook.sharedSticker.backgroundTopColor"] = top }
            if let bottom = bottomColor { items["com.facebook.sharedSticker.backgroundBottomColor"] = bottom }
            let opts: [UIPasteboard.OptionsKey: Any] = [.expirationDate: Date().addingTimeInterval(300)]
            UIPasteboard.general.setItems([items], options: opts)
            UIApplication.shared.open(scheme, options: [:]) { ok in
                if ok {
                    call.resolve(["completed": true, "destination": "facebook-story"])
                } else {
                    call.reject("Failed to open Facebook")
                }
            }
        }
    }

    private func shareToSnapchat(_ call: CAPPluginCall) {
        guard let stickerObj = call.getObject("stickerImage"), let sticker = decodeImageInput(stickerObj),
              let stickerData = sticker.pngData() else {
            call.reject("shareToSnapchat requires `stickerImage`")
            return
        }
        let attachmentUrl = call.getString("attachmentUrl") ?? ""
        DispatchQueue.main.async {
            guard let scheme = URL(string: "snapchat://creativekit/camera/1") else {
                call.reject("Invalid Snapchat URL")
                return
            }
            guard UIApplication.shared.canOpenURL(scheme) else {
                call.reject("Snapchat is not installed")
                return
            }
            var items: [String: Any] = [
                "com.snapchat.creativekit.stickerImage": stickerData,
            ]
            if !attachmentUrl.isEmpty {
                items["com.snapchat.creativekit.attachmentUrl"] = attachmentUrl
            }
            UIPasteboard.general.setItems([items], options: [.expirationDate: Date().addingTimeInterval(300)])
            UIApplication.shared.open(scheme, options: [:]) { ok in
                if ok {
                    call.resolve(["completed": true, "destination": "snapchat-story"])
                } else {
                    call.reject("Failed to open Snapchat")
                }
            }
        }
    }

    private func shareToInstagramFeed(_ call: CAPPluginCall) {
        // iOS has no public deep-link to IG feed compose with image. The
        // closest option is to save image to camera roll then open IG so the
        // user can pick "New Post". Not the cleanest UX but the only path
        // without the deprecated Instagram iOS Hooks.
        guard let imageObj = call.getObject("image"), let img = decodeImageInput(imageObj) else {
            call.reject("shareToInstagramFeed requires `image`")
            return
        }
        ensurePhotoPermission { granted in
            guard granted else {
                call.reject("Photo library permission required")
                return
            }
            self.savePhoto(image: img, albumName: nil) { _ in
                DispatchQueue.main.async {
                    guard let scheme = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(scheme) else {
                        call.reject("Instagram is not installed")
                        return
                    }
                    UIApplication.shared.open(scheme, options: [:]) { ok in
                        if ok { call.resolve(["completed": true, "destination": "instagram-feed"]) }
                        else { call.reject("Failed to open Instagram") }
                    }
                }
            }
        }
    }

    // MARK: - photo save helper

    private func savePhoto(
        image: UIImage,
        albumName: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var localId: String?

        let performSave: (PHAssetCollection?) -> Void = { collection in
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetChangeRequest.creationRequestForAsset(from: image)
                localId = req.placeholderForCreatedAsset?.localIdentifier
                if let collection = collection, let placeholder = req.placeholderForCreatedAsset {
                    let albumChange = PHAssetCollectionChangeRequest(for: collection)
                    albumChange?.addAssets([placeholder] as NSArray)
                }
            }, completionHandler: { success, error in
                if success, let id = localId {
                    completion(.success(id))
                } else if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.failure(NSError(domain: "RichShare", code: 500, userInfo: [
                        NSLocalizedDescriptionKey: "Photos save failed"
                    ])))
                }
            })
        }

        guard let albumName = albumName else {
            performSave(nil)
            return
        }

        // Find or create album
        let fetch = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        var found: PHAssetCollection?
        fetch.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == albumName {
                found = collection
                stop.pointee = true
            }
        }
        if let found = found {
            performSave(found)
            return
        }
        // Create
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            placeholder = req.placeholderForCreatedAssetCollection
        }, completionHandler: { success, error in
            if success, let placeholder = placeholder {
                let collections = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [placeholder.localIdentifier],
                    options: nil
                )
                performSave(collections.firstObject)
            } else if let error = error {
                completion(.failure(error))
            } else {
                completion(.failure(NSError(domain: "RichShare", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Album creation failed"
                ])))
            }
        })
    }
}
