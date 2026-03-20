import Photos
import UIKit

enum PhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    static func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    static func openSettings() {
        // アプリの写真アクセス設定を直接開く
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "写真ライブラリへのアクセスが許可されていません。"
            }
        }
    }
}
