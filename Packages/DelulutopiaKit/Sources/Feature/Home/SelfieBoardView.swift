import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI
import UIKit

private let hour: TimeInterval = 3600

private enum Polaroid {
    static let paper = Color(red: 0.984, green: 0.980, blue: 0.965)
    static let paperDark = Color(red: 0.914, green: 0.898, blue: 0.855)
    static let ink = Color(red: 0.200, green: 0.196, blue: 0.231)
    static let inkQuiet = Color(red: 0.333, green: 0.325, blue: 0.373)
    static let navy = Color(red: 0.125, green: 0.169, blue: 0.271)
    static let pinA = Color(red: 0.788, green: 0.435, blue: 0.322)
    static let pinB = Color(red: 0.373, green: 0.541, blue: 0.490)
    static let pinNone = Color(red: 0.549, green: 0.541, blue: 0.576)
}

private func alive(_ s: Selfie?, now: Date) -> Selfie? {
    guard let s, let end = DLTime.date(s.expiresAt), end > now else { return nil }
    return s
}

private func hoursLeft(_ iso: String, now: Date) -> Int {
    max(1, Int(ceil((DLTime.date(iso).map { $0.timeIntervalSince(now) } ?? 0) / hour)))
}

private func blurImage(_ dataURI: String?) -> UIImage? {
    guard let dataURI, let comma = dataURI.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])).flatMap(UIImage.init(data:))
}

private struct Shown: Identifiable {
    let selfie: Selfie
    let mine: Bool
    let name: String
    var id: PublicID { selfie.id }
}

private struct Viewing: Identifiable {
    let id: PublicID
}

private struct ReviewShot: Identifiable {
    let image: UIImage
    let id = UUID()
}

/// Daily selfies (web selfies/SelfieBoard.tsx, doc "Delululand — Selfies"): a cork board in a light
/// wood frame under the Board with my polaroid on the left and the friend's on the right (DS1, DS2).
/// My empty frame opens the camera on the front lens (Q1: the system camera, the citizen may still
/// flip), then Your selfie with Retake / Use (DS4). Nothing is ever changed or removed (DS3); a
/// selfie leaves at `expiresAt` (DS7). The friend's stays blurred until mine is up (Q2) and carries
/// NEW until shown unlocked (Q3). Folds like the Board (DS1).
struct SelfieBoardView: View {
    let home: Home
    let now: Date
    let actions: HomeActions

    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @Environment(\.colorScheme) private var scheme
    @State private var camera = false
    @State private var review: ReviewShot?
    @State private var pending: UIImage?
    @State private var viewing: Viewing?
    @State private var ribbon: PublicID?

    private var board: SelfieBoard? { home.selfies }
    private var mine: Selfie? { alive(board?.mine, now: now) }
    private var theirs: Selfie? { alive(board?.theirs, now: now) }
    private var locked: Bool { theirs.map { $0.locked || mine == nil || $0.url == nil } ?? false }
    private var friend: String { home.friendName }
    private var mini: Bool { backend.settings.selfieMini }
    private var dark: Bool { scheme == .dark }

    private var gallery: [Shown] {
        var out: [Shown] = []
        if let mine { out.append(Shown(selfie: mine, mine: true, name: home.me.nickname)) }
        if let theirs, !locked { out.append(Shown(selfie: theirs, mine: false, name: friend)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mini {
                strip.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                cork.transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top)))
                HStack(spacing: 10) {
                    (Text(t("selfie.todays")).font(DLTextStyle.footnoteStrong.spec.dynamicFont).foregroundColor(.dlInk)
                        + Text(" · " + meta).font(DLTextStyle.footnote.spec.dynamicFont))
                        .foregroundStyle(.dlInkQuiet)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(DLMotion.easeOut(0.32)) { backend.settings.setSelfieMini(true) }
                    } label: {
                        Image(systemName: "chevron.up").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.dlInk)
                    .accessibilityLabel(t("selfie.fold"))
                }
                .padding(.leading, 2)
            }
        }
        .animation(DLMotion.easeOut(0.32), value: mini)
        .onAppear { markRibbon() }
        .onChange(of: theirs?.id) { _, _ in markRibbon() }
        .onChange(of: mini) { _, _ in markRibbon() }
        .onChange(of: locked) { _, _ in markRibbon() }
        .fullScreenCover(isPresented: $camera) {
            FrontCameraPicker { image in
                camera = false
                if let image { review = ReviewShot(image: image) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $review) { shot in
            SelfieReview(
                image: shot.image,
                name: home.me.nickname,
                time: DLTime.time(of: now),
                until: DLTime.clock(DLTime.iso(now.addingTimeInterval(TimeInterval(board?.ttlHours ?? 24) * hour)), now: now),
                onRetake: {
                    review = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        camera = true
                    }
                },
                onUse: { use(shot.image) },
                onClose: { review = nil }
            )
        }
        .fullScreenCover(item: $viewing) { v in
            SelfieViewer(items: gallery, start: gallery.firstIndex { $0.id == v.id } ?? 0, now: now) { viewing = nil }
                .environment(backend)
        }
    }

    private var meta: String {
        if pending != nil { return t("selfie.metaPinning") }
        if let mine { return tn("selfie.metaYoursFades", hoursLeft(mine.expiresAt, now: now)) }
        if theirs != nil { return t("selfie.metaAddYours", ["friend": friend]) }
        return tn("selfie.metaStays", board?.ttlHours ?? 24)
    }

    private func markRibbon() {
        guard let theirs, home.selfieNew else { return }
        if ribbon != theirs.id { ribbon = theirs.id }
        if !mini, !locked { actions.selfieSeen(theirs.id) }
    }

    private func capture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            notice(.text(t("media.cameraOff")))
            return
        }
        camera = true
    }

    private func use(_ image: UIImage) {
        review = nil
        pending = image
        Task {
            let text: String? = if let jpeg = image.jpegData(compressionQuality: 0.9) {
                await actions.postSelfie(jpeg: jpeg)
            } else {
                t("selfie.notPinned")
            }
            pending = nil
            if let text { notice(.text(text)) }
        }
    }

    // MARK: Board

    private var woodColors: [Color] {
        dark
            ? [Color(red: 0.478, green: 0.337, blue: 0.220), Color(red: 0.369, green: 0.255, blue: 0.165), Color(red: 0.451, green: 0.322, blue: 0.227)]
            : [Color(red: 0.737, green: 0.553, blue: 0.376), Color(red: 0.624, green: 0.439, blue: 0.282), Color(red: 0.710, green: 0.525, blue: 0.345)]
    }

    private var corkColor: Color { dark ? Color(red: 0.612, green: 0.478, blue: 0.345) : Color(red: 0.788, green: 0.635, blue: 0.478) }

    private var cork: some View {
        ZStack {
            corkColor
            CorkSpecks()
            HStack(spacing: 20) {
                left
                right
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 232)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(10)
        .background(LinearGradient(colors: woodColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .dlShade.opacity(0.3), radius: 6, y: 4)
    }

    @ViewBuilder private var left: some View {
        if let pending {
            PolaroidFrame(tilt: -3, pin: Polaroid.pinA, name: home.me.nickname, time: DLTime.time(of: now), dark: dark) {
                Image(uiImage: pending).resizable().scaledToFill().opacity(0.55).saturation(0.4)
                    .overlay(alignment: .bottomTrailing) {
                        Text(t("selfie.pinning")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.6), in: Capsule()).padding(6)
                    }
            }
        } else if let mine {
            Button { viewing = Viewing(id: mine.id) } label: {
                PolaroidFrame(tilt: -3, pin: Polaroid.pinA, name: home.me.nickname, time: DLTime.time(mine.createdAt), dark: dark) {
                    RemoteImage(mine.url, contentMode: .fill, maxPixel: 600) { Color.dlPlaceholder }
                }
            }
            .buttonStyle(DLPressStyle(scale: 0.98))
            .accessibilityLabel(t("selfie.yourSelfieOpen", ["time": DLTime.time(mine.createdAt)]))
        } else {
            EmptyFrame(tilt: -3, name: home.me.nickname) {
                Button(action: capture) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Polaroid.navy, in: Circle())
                        Text(t("selfie.addYourSelfie")).font(.system(size: 13, weight: .bold)).foregroundStyle(Polaroid.navy).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.6))
                }
                .buttonStyle(DLPressStyle(scale: 0.97))
            }
        }
    }

    @ViewBuilder private var right: some View {
        if home.friend == nil {
            EmptyFrame(tilt: 2.5, name: "?") { QuietWords(t("selfie.waiting")) }
        } else if let theirs {
            if locked {
                Button(action: { if pending == nil { capture() } }) {
                    PolaroidFrame(tilt: 2.5, pin: Polaroid.pinB, name: friend, time: DLTime.time(theirs.createdAt), dark: dark, isNew: ribbon == theirs.id) {
                        ZStack {
                            if let image = blurImage(theirs.blurPreview) {
                                Image(uiImage: image).resizable().scaledToFill().blur(radius: 10).scaleEffect(1.2)
                            }
                            VStack(spacing: 6) {
                                Image(systemName: "lock").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 34, height: 34).background(Color.black.opacity(0.55), in: Circle())
                                Text(t("selfie.addYoursToSeeIt")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
                                    .multilineTextAlignment(.center).shadow(radius: 2)
                            }
                            .padding(8)
                        }
                    }
                }
                .buttonStyle(DLPressStyle(scale: 0.98))
                .accessibilityLabel(t("selfie.lockedLabel", ["friend": friend]))
            } else {
                Button { viewing = Viewing(id: theirs.id) } label: {
                    PolaroidFrame(tilt: 2.5, pin: Polaroid.pinB, name: friend, time: DLTime.time(theirs.createdAt), dark: dark, isNew: ribbon == theirs.id) {
                        RemoteImage(theirs.url, contentMode: .fill, maxPixel: 600) { Color.dlPlaceholder }
                    }
                }
                .buttonStyle(DLPressStyle(scale: 0.98))
                .accessibilityLabel(t("selfie.friendsSelfieOpen", ["friend": friend, "time": DLTime.time(theirs.createdAt)]))
            }
        } else {
            EmptyFrame(tilt: 2.5, name: friend) { QuietWords(t("selfie.noSelfieYet", ["friend": friend])) }
        }
    }

    // MARK: Folded strip

    private var strip: some View {
        Button { withAnimation(DLMotion.easeOut(0.32)) { backend.settings.setSelfieMini(false) } } label: {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    MiniPolaroid(tilt: -5, url: mine?.url, image: nil)
                    MiniPolaroid(tilt: 4, url: locked ? nil : theirs?.url, image: locked ? blurImage(theirs?.blurPreview) : nil, present: theirs != nil, blurred: locked)
                }
                .frame(width: 72, height: 54)
                .background(corkColor, in: RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(t("selfie.selfies")).font(.custom(DLFontName.manropeExtraBold.name, size: 15, relativeTo: .subheadline))
                        if home.selfieNew, theirs != nil { NewChip(paper: false) }
                    }
                    Text(stripLine).font(DLTextStyle.footnote.spec.dynamicFont).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
            .background(LinearGradient(colors: woodColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .dlShade.opacity(0.18), radius: 1.5, y: 1)
        }
        .buttonStyle(DLPressStyle(scale: 0.99))
        .accessibilityHint(t("selfie.unfold"))
    }

    private var stripLine: String {
        if let theirs { return t("selfie.strip.friend", ["friend": friend, "age": ageWords(theirs.createdAt, now: now)]) }
        if let mine { return t("selfie.strip.mine", ["age": ageWords(mine.createdAt, now: now)]) }
        return t("selfie.strip.none")
    }
}

// MARK: - Pieces

private struct CorkSpecks: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 7)
            for i in 0 ..< 420 {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let kind = i % 3
                let r: CGFloat = kind == 2 ? 1.6 : 1
                let color: Color = switch kind {
                case 0: Color(red: 0.39, green: 0.22, blue: 0.10).opacity(0.38)
                case 1: Color(red: 1, green: 0.94, blue: 0.84).opacity(0.35)
                default: Color(red: 0.47, green: 0.29, blue: 0.14).opacity(0.28)
                }
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small deterministic generator, so the cork looks the same on every redraw.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

private struct Pin: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.75), color], center: UnitPoint(x: 0.34, y: 0.3), startRadius: 0, endRadius: 6))
            .frame(width: 15, height: 15)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 2)
            .accessibilityHidden(true)
    }
}

private struct Caption: View {
    let name: String
    let time: String
    var quiet = false
    var big = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.custom(DLFontName.caveatSemiBold.name, size: big ? 34 : 21)).foregroundStyle(quiet ? Polaroid.inkQuiet : Polaroid.ink).lineLimit(1)
            Spacer(minLength: 4)
            if !time.isEmpty { Text(time).font(.custom(DLFontName.caveatSemiBold.name, size: big ? 24 : 16)).foregroundStyle(Polaroid.inkQuiet) }
        }
        .padding(.horizontal, 2)
        .padding(.top, big ? 12 : 5)
        .frame(height: big ? 68 : 36, alignment: .top)
    }
}

private struct PolaroidFrame<Photo: View>: View {
    let tilt: Double
    let pin: Color
    let name: String
    let time: String
    let dark: Bool
    var isNew = false
    @ViewBuilder let photo: () -> Photo

    var body: some View {
        VStack(spacing: 0) {
            photo().frame(width: 122, height: 122).clipped().background(Color(red: 0.227, green: 0.220, blue: 0.251))
            Caption(name: name, time: time)
        }
        .padding([.top, .horizontal], 8)
        .frame(width: 138)
        .background(dark ? Polaroid.paperDark : Polaroid.paper)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 5)
        .overlay(alignment: .topLeading) { if isNew { NewChip(paper: false).padding(13) } }
        .overlay(alignment: .top) { Pin(color: pin).offset(y: -6) }
        .rotationEffect(.degrees(tilt))
    }
}

private struct EmptyFrame<Inside: View>: View {
    let tilt: Double
    let name: String
    @ViewBuilder let inside: () -> Inside

    var body: some View {
        VStack(spacing: 0) {
            inside().frame(width: 122, height: 122)
            Caption(name: name, time: "", quiet: true)
        }
        .padding([.top, .horizontal], 8)
        .frame(width: 138)
        .background(Polaroid.paper.opacity(0.62))
        .overlay(Rectangle().strokeBorder(Polaroid.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .overlay(alignment: .top) { Pin(color: Polaroid.pinNone).offset(y: -6) }
        .rotationEffect(.degrees(tilt))
    }
}

private struct QuietWords: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.282, green: 0.325, blue: 0.424))
            .multilineTextAlignment(.center).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.35))
    }
}

private struct MiniPolaroid: View {
    let tilt: Double
    let url: String?
    let image: UIImage?
    var present = true
    var blurred = false
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: blurred ? 3 : 0)
            } else if let url {
                RemoteImage(url, contentMode: .fill, maxPixel: 120) { Color.dlPlaceholder }
            }
        }
        .frame(width: 21, height: 21).clipped()
        .padding(.horizontal, 2).padding(.top, 2).padding(.bottom, 7)
        .background(url == nil && image == nil && !present ? Polaroid.paper.opacity(0.5) : Polaroid.paper)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        .rotationEffect(.degrees(tilt))
        .accessibilityHidden(true)
    }
}

private struct BigPolaroid<Photo: View>: View {
    let tilt: Double
    let name: String
    let time: String
    @ViewBuilder let photo: () -> Photo
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            photo().frame(width: 278, height: 278).clipped().background(Color(red: 0.227, green: 0.220, blue: 0.251))
            Caption(name: name, time: time, big: true)
        }
        .padding([.top, .horizontal], 16)
        .frame(width: 310)
        .background(scheme == .dark ? Polaroid.paperDark : Polaroid.paper)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
        .rotationEffect(.degrees(tilt))
    }
}

/// DS4: the shot as its polaroid, before it is pinned for good.
private struct SelfieReview: View {
    let image: UIImage
    let name: String
    let time: String
    let until: String
    let onRetake: () -> Void
    let onUse: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DLGlassIconButton("xmark", label: t("selfie.close"), action: onClose)
                Text(t("selfie.reviewTitle")).dlText(.headline).foregroundStyle(.dlInk)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8)
            Spacer()
            BigPolaroid(tilt: -1.5, name: name, time: time) {
                Image(uiImage: image).resizable().scaledToFill().accessibilityLabel(t("selfie.alt.mine"))
            }
            VStack(spacing: 10) {
                Label(t("selfie.reviewStaysUntil", ["when": until]), systemImage: "hourglass")
                Label(t("selfie.reviewFinal"), systemImage: "lock")
            }
            .dlText(.footnote)
            .foregroundStyle(.dlInkQuiet)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            Spacer()
            HStack(spacing: 12) {
                Button(action: onRetake) { Label(t("selfie.retake"), systemImage: "camera") }
                    .buttonStyle(DLButtonStyle(.outline, fullWidth: true))
                Button(t("selfie.use"), action: onUse)
                    .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.dlPaper.ignoresSafeArea())
    }
}

/// DS8: full screen, swipe between the two; who, when, and how long it stays. No actions.
private struct SelfieViewer: View {
    let items: [Shown]
    let start: Int
    let now: Date
    let onClose: () -> Void
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                DLGlassIconButton("xmark", label: t("selfie.close"), action: onClose)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    BigPolaroid(tilt: -1, name: item.name, time: DLTime.time(item.selfie.createdAt)) {
                        RemoteImage(item.selfie.url, contentMode: .fill, maxPixel: 1200) { Color.dlPlaceholder }
                            .accessibilityLabel(item.mine ? t("selfie.alt.mine") : t("selfie.alt.friends", ["friend": item.name]))
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
            if items.indices.contains(index) {
                let item = items[index]
                VStack(spacing: 6) {
                    Text((item.mine ? t("selfie.you") : item.name) + " · " + t("selfie.taken", ["time": DLTime.time(item.selfie.createdAt)]))
                        .dlText(.callout).foregroundStyle(.dlOnLightbox)
                    Label(gone(item.selfie), systemImage: "hourglass").dlText(.footnote).foregroundStyle(.dlOnLightboxQuiet)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.dlLightbox.ignoresSafeArea())
        .onAppear { index = start }
        .accessibilityLabel(t("selfie.viewerLabel", ["n": index + 1, "total": items.count]))
    }

    private func gone(_ s: Selfie) -> String {
        let left = DLTime.date(s.expiresAt).map { $0.timeIntervalSince(now) } ?? 0
        return left >= hour ? tn("selfie.goneIn", Int(ceil(left / hour))) : tn("selfie.goneInMinutes", max(1, Int(ceil(left / 60))))
    }
}

/// Q1: the system camera, opened on the front lens; the citizen may still flip it (decided 21 Nov 2026).
private struct FrontCameraPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
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
