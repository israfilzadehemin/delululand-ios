import DLDesignSystem
import PhotosUI
import SwiftUI
import UIKit

/// The edge of the square JPEG a cropped picture becomes (doc "Delululand — Menu, Profile & Settings" P2).
public let avatarPixels: CGFloat = 384

/// Picks a picture for a citizen (canvas F-Photo-source, F-Crop): Choose photo (the system picker, no
/// permission), Take photo (camera, when there is one) and, when a picture exists, Remove photo; then
/// "Move and Scale" over a round window. Hands back a 384 px square JPEG.
public struct DLPhotoChooser: ViewModifier {
    @Binding var isPresented: Bool
    let hasPhoto: Bool
    let onPhoto: (Data) -> Void
    let onRemove: (() -> Void)?

    @State private var library = false
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    @State private var cropping: CropSource?
    @State private var confirmRemove = false

    struct CropSource: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    public func body(content: Content) -> some View {
        content
            .confirmationDialog("Your photo", isPresented: $isPresented, titleVisibility: .hidden) {
                Button("Choose photo") { library = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo") { camera = true }
                }
                if hasPhoto, onRemove != nil {
                    Button("Remove photo", role: .destructive) { confirmRemove = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Remove your photo?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) { onRemove?() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your initials show instead.")
            }
            .photosPicker(isPresented: $library, selection: $item, matching: .images)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        cropping = CropSource(image: image)
                    }
                    item = nil
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in
                    camera = false
                    if let image { cropping = CropSource(image: image) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $cropping) { source in
                DLAvatarCrop(image: source.image) { jpeg in
                    cropping = nil
                    if let jpeg { onPhoto(jpeg) }
                }
            }
    }
}

public extension View {
    func dlPhotoChooser(isPresented: Binding<Bool>, hasPhoto: Bool, onPhoto: @escaping (Data) -> Void, onRemove: (() -> Void)? = nil) -> some View {
        modifier(DLPhotoChooser(isPresented: isPresented, hasPhoto: hasPhoto, onPhoto: onPhoto, onRemove: onRemove))
    }
}

/// The camera (system UI; the camera permission prompt is the system's, canvas X-Camera).
struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void

        init(onDone: @escaping (UIImage?) -> Void) {
            self.onDone = onDone
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
        }
    }
}

/// "Move and Scale" (canvas F-Crop; web P2, P3): the picture under a round window over a square crop;
/// drag to move, pinch to zoom 1–4×. Choose hands back the 384 px JPEG; the picture never leaves the
/// phone uncropped.
public struct DLAvatarCrop: View {
    let image: UIImage
    let onDone: (Data?) -> Void

    private let window: CGFloat = 300
    private let maxZoom: CGFloat = 4
    @State private var zoom: CGFloat = 1
    @State private var origin: CGPoint = .zero
    @State private var startZoom: CGFloat = 1
    @State private var startOrigin: CGPoint?

    public init(image: UIImage, onDone: @escaping (Data?) -> Void) {
        self.image = image.normalizedOrientation()
        self.onDone = onDone
    }

    private var base: CGFloat { max(window / image.size.width, window / image.size.height) }
    private var scale: CGFloat { base * zoom }
    private var shown: CGSize { CGSize(width: image.size.width * scale, height: image.size.height * scale) }

    private func clamp(_ p: CGPoint, scale s: CGFloat) -> CGPoint {
        CGPoint(
            x: min(0, max(window - image.size.width * s, p.x)),
            y: min(0, max(window - image.size.height * s, p.y))
        )
    }

    public var body: some View {
        ZStack {
            Color(red: 0x14 / 255, green: 0x17 / 255, blue: 0x1F / 255).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Move and Scale")
                    .dlText(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                Spacer()
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(x: origin.x, y: origin.y)
                }
                .frame(width: window, height: window, alignment: .topLeading)
                .clipped()
                .overlay {
                    // The round window: everything outside the circle is dimmed.
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .mask {
                            Rectangle()
                                .overlay(Circle().blendMode(.destinationOut))
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1).allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(drag.simultaneously(with: pinch))
                .accessibilityLabel("Photo position: drag to move, pinch to zoom")
                Spacer()
                HStack {
                    Button("Cancel") { onDone(nil) }
                        .buttonStyle(.dlText)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Choose") { onDone(crop()) }
                        .buttonStyle(.dlFilled)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            zoom = 1
            origin = clamp(CGPoint(x: (window - shown.width) / 2, y: (window - shown.height) / 2), scale: base)
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = startOrigin ?? origin
                if startOrigin == nil { startOrigin = origin }
                origin = clamp(CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height), scale: scale)
            }
            .onEnded { _ in startOrigin = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = min(maxZoom, max(1, startZoom * value.magnification))
                // Zoom about the window's centre.
                let oldScale = scale
                let cx = (window / 2 - origin.x) / oldScale
                let cy = (window / 2 - origin.y) / oldScale
                zoom = next
                origin = clamp(CGPoint(x: window / 2 - cx * scale, y: window / 2 - cy * scale), scale: scale)
            }
            .onEnded { _ in startZoom = zoom }
    }

    private func crop() -> Data? {
        let s = scale
        let rect = CGRect(x: -origin.x / s, y: -origin.y / s, width: window / s, height: window / s)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let out = UIGraphicsImageRenderer(size: CGSize(width: avatarPixels, height: avatarPixels), format: format).image { _ in
            let k = avatarPixels / rect.width
            image.draw(in: CGRect(x: -rect.minX * k, y: -rect.minY * k, width: image.size.width * k, height: image.size.height * k))
        }
        return out.jpegData(compressionQuality: 0.86)
    }
}

extension UIImage {
    /// Draws the picture upright so crops and uploads match what is shown.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }
    }
}
