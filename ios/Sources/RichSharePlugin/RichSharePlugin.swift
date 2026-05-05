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
