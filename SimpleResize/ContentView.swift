import PhotosUI
import SwiftUI

private let scalePercentages = stride(from: 20, through: 100, by: 20).map { $0 }
private let qualityLevels = stride(from: 20, through: 100, by: 20).map { $0 }

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var originalDataSize: Int = 0
    @State private var resizedImage: UIImage?
    @State private var resizedDataSize: Int = 0

    @State private var selectedScale: Int?
    @State private var selectedQuality: Int = 80
    @State private var previewImage: UIImage?
    @State private var previewDataSize: Int = 0
    @State private var isProcessing = false
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showSettingsAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Image Picker
                Section {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("写真を選択", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showCamera = true
                    } label: {
                        Label("カメラで撮影", systemImage: "camera")
                    }

                    if let originalImage {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)

                        Text("元のサイズ: \(Int(originalImage.size.width)) × \(Int(originalImage.size.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("容量: \(formattedSize(originalDataSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("元の画像")
                }

                // MARK: - Resize Settings
                if originalImage != nil {
                    Section {
                        Picker("スケール", selection: $selectedScale) {
                            Text("選択してください").tag(nil as Int?)
                            ForEach(scalePercentages, id: \.self) { pct in
                                Text("\(pct)% - \(scaledDimensionsText(pct))")
                                    .tag(pct as Int?)
                            }
                        }

                        Picker("品質", selection: $selectedQuality) {
                            ForEach(qualityLevels, id: \.self) { q in
                                Text("\(q)%").tag(q)
                            }
                        }
                    } header: {
                        Text("リサイズ設定")
                    }

                    // MARK: - Preview
                    if let previewImage {
                        Section {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)

                            Text("サイズ: \(Int(previewImage.size.width)) × \(Int(previewImage.size.height))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("容量: \(formattedSize(previewDataSize))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("写真ライブラリに保存") {
                                saveToPhotoLibrary()
                            }

                            Button {
                                shareImage()
                            } label: {
                                Label("共有", systemImage: "square.and.arrow.up")
                            }
                        } header: {
                            Text("プレビュー")
                        }
                    }
                }
            }
            .navigationTitle("SimpleResize")
            .onChange(of: selectedItem) {
                loadImage()
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $cameraImage)
            }
            .onChange(of: cameraImage) {
                loadCameraImage()
            }
            .onChange(of: selectedScale) {
                updatePreview()
            }
            .onChange(of: selectedQuality) {
                updatePreview()
            }
            .alert("通知", isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
            .alert("写真ライブラリへのアクセス", isPresented: $showSettingsAlert) {
                Button("設定を開く") {
                    PhotoLibrarySaver.openSettings()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("写真ライブラリへのアクセスが許可されていません。設定を開いて「写真」の項目から許可してください。")
            }
        }
    }

    private func scaledSize(_ percentage: Int) -> CGSize {
        guard let original = originalImage else { return .zero }
        let scale = CGFloat(percentage) / 100.0
        return CGSize(
            width: original.size.width * scale,
            height: original.size.height * scale
        )
    }

    private func scaledDimensionsText(_ percentage: Int) -> String {
        let size = scaledSize(percentage)
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func setOriginalImage(_ image: UIImage, dataSize: Int) {
        originalImage = image
        originalDataSize = dataSize
        previewImage = nil
        previewDataSize = 0
        selectedScale = nil
        selectedQuality = 80
    }

    private func loadCameraImage() {
        guard let cameraImage else { return }
        let dataSize = cameraImage.jpegData(compressionQuality: 1.0)?.count ?? 0
        setOriginalImage(cameraImage, dataSize: dataSize)
    }

    private func loadImage() {
        guard let selectedItem else { return }
        Task {
            if let data = try? await selectedItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                setOriginalImage(image, dataSize: data.count)
            }
        }
    }

    private func updatePreview() {
        guard let originalImage, let percentage = selectedScale else {
            previewImage = nil
            previewDataSize = 0
            return
        }
        isProcessing = true
        let size = scaledSize(percentage)
        let quality = CGFloat(selectedQuality) / 100.0

        Task.detached {
            let resized = ImageResizer.resize(originalImage, to: size)
            let jpegData = resized.jpegData(compressionQuality: quality)
            let preview = jpegData.flatMap { UIImage(data: $0) } ?? resized
            let dataSize = jpegData?.count ?? 0
            await MainActor.run {
                previewImage = preview
                previewDataSize = dataSize
                isProcessing = false
            }
        }
    }

    private func saveToPhotoLibrary() {
        let status = PhotoLibrarySaver.authorizationStatus()
        if status == .denied || status == .restricted {
            showSettingsAlert = true
            return
        }

        guard let originalImage, let percentage = selectedScale else { return }
        let size = scaledSize(percentage)
        let quality = CGFloat(selectedQuality) / 100.0

        Task {
            do {
                let resized = ImageResizer.resize(originalImage, to: size)
                guard let jpegData = resized.jpegData(compressionQuality: quality),
                      let finalImage = UIImage(data: jpegData) else { return }
                try await PhotoLibrarySaver.save(finalImage)
                alertMessage = "保存しました！"
            } catch is PhotoLibrarySaver.SaveError {
                showSettingsAlert = true
                return
            } catch {
                alertMessage = error.localizedDescription
            }
            showAlert = true
        }
    }

    private func shareImage() {
        guard let originalImage, let percentage = selectedScale else { return }
        let size = scaledSize(percentage)
        let quality = CGFloat(selectedQuality) / 100.0

        let resized = ImageResizer.resize(originalImage, to: size)
        guard let jpegData = resized.jpegData(compressionQuality: quality) else { return }

        let activityVC = UIActivityViewController(activityItems: [jpegData], applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }

        // iPad対応
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootVC.present(activityVC, animated: true)
    }
}

#Preview {
    ContentView()
}
