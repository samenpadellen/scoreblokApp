import ImagePlayground
import PhotosUI
import SwiftUI
import UIKit

/// De markering van één speler: een profielfoto als die er is, anders de vorm
/// in de inktkleur op het vlak van de speler. Op een foto blijft de kleur van
/// de speler als streep onderlangs, zodat kleur en beeld samen blijven werken.
struct PlayerMark: View {
    let player: Player
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let image = PhotoBook.shared.image(for: player.id) {
                PhotoSquare(image: image, stripe: player.color, size: size)
            } else {
                AvatarShape(index: player.avatarIndex)
                    .fill(player.inkColor)
                    .frame(width: size, height: size)
                    .background(player.color)
            }
        }
        .accessibilityLabel(player.name)
    }
}

/// Een foto als vierkant, met de spelerkleur als streep.
struct PhotoSquare: View {
    let image: UIImage
    let stripe: Color
    var size: CGFloat = 34

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(stripe).frame(height: max(2, (size * 0.1).rounded()))
            }
    }
}

/// Losse markering zonder speler, voor voorbeelden in kiezers.
struct AvatarSwatch: View {
    let avatarIndex: Int
    let rampIndex: Int
    var size: CGFloat = 34

    private var ramp: (bg: Int, ink: Int) {
        M.playerRamp[((rampIndex % M.playerRamp.count) + M.playerRamp.count) % M.playerRamp.count]
    }

    var body: some View {
        AvatarShape(index: avatarIndex)
            .fill(Color(hex: ramp.ink))
            .frame(width: size, height: size)
            .background(Color(hex: ramp.bg))
    }
}

/// Kiezer voor de markering van een speler: een foto (camera, fotorol of
/// Image Playground), en elke vorm en kleur uit de neutrale ramp, met een
/// worp-knop voor wie niet wil kiezen.
struct AvatarPicker: View {
    @Binding var avatarIndex: Int
    @Binding var rampIndex: Int
    /// Zonder binding geen fotodeel, bijvoorbeeld waar geen speler bij hoort.
    var photo: Binding<Data?>? = nil
    /// Voor Image Playground: van wie het portret is.
    var name: String = ""

    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var libraryItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingPlayground = false
    @State private var working = false
    @State private var failed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let photoColumns = [GridItem(.adaptive(minimum: 128), spacing: 6)]

    private var ramp: (bg: Int, ink: Int) {
        M.playerRamp[((rampIndex % M.playerRamp.count) + M.playerRamp.count) % M.playerRamp.count]
    }

    private var currentImage: UIImage? {
        photo?.wrappedValue.flatMap(PhotoProcessing.thumbnail(from:))
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                preview
                Text(photo?.wrappedValue == nil
                     ? "Vorm en kleur samen maken de speler herkenbaar, ook op de kleinste maat."
                     : "De foto staat voorop. De kleur blijft als streep onderlangs.")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                OutlineButton(title: "Gooi opnieuw") { roll() }
            }

            if photo != nil { photoSection }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Vorm")
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<AvatarShape.count, id: \.self) { index in
                        Button {
                            withAnimation(M.Motion.quick) { avatarIndex = index }
                        } label: {
                            AvatarShape(index: index)
                                .fill(avatarIndex == index ? M.paper : M.ink)
                                .padding(2)
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(avatarIndex == index ? M.ink : M.paperDeep)
                                .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                    }
                }
            }
            .opacity(photo?.wrappedValue == nil ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Kleur")
                HStack(spacing: 6) {
                    ForEach(0..<M.playerRamp.count, id: \.self) { index in
                        Button {
                            withAnimation(M.Motion.quick) { rampIndex = index }
                        } label: {
                            Rectangle()
                                .fill(Color(hex: M.playerRamp[index].bg))
                                .frame(height: 32)
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    Rectangle().stroke(M.ink,
                                                       lineWidth: rampIndex == index ? 3 : 1)
                                )
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: avatarIndex)
        .sensoryFeedback(.selection, trigger: rampIndex)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            process {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                return await PhotoProcessing.portrait(from: data)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                guard let image else { return }
                process { await PhotoProcessing.portrait(from: image) }
            }
            .ignoresSafeArea()
        }
        .imagePlaygroundSheet(isPresented: $showingPlayground,
                              concept: name.isEmpty ? "Portret van een speler" : "Portret van \(name)",
                              sourceImage: currentImage.map { Image(uiImage: $0) }) { url in
            process {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return await PhotoProcessing.portrait(from: data)
            }
        }
    }

    private var preview: some View {
        ZStack {
            if let image = currentImage {
                PhotoSquare(image: image, stripe: Color(hex: ramp.bg), size: 64)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.9)))
            } else {
                AvatarSwatch(avatarIndex: avatarIndex, rampIndex: rampIndex, size: 64)
                    .transition(.opacity)
            }
            if working {
                M.ink.opacity(0.55)
                ProgressView().tint(M.paper)
            }
        }
        .frame(width: 64, height: 64)
        .animation(M.Motion.settle, value: photo?.wrappedValue)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Foto")
            LazyVGrid(columns: photoColumns, alignment: .leading, spacing: 6) {
                if cameraAvailable {
                    Button { showingCamera = true } label: { PhotoActionLabel(title: "Maak een foto") }
                        .buttonStyle(PressableStyle())
                }
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    PhotoActionLabel(title: "Uit fotorol")
                }
                .buttonStyle(PressableStyle())
                if supportsImagePlayground {
                    Button { showingPlayground = true } label: { PhotoActionLabel(title: "Image Playground") }
                        .buttonStyle(PressableStyle())
                }
                if photo?.wrappedValue != nil {
                    Button {
                        withAnimation(M.Motion.settle) { photo?.wrappedValue = nil }
                    } label: {
                        PhotoActionLabel(title: "Verwijder foto", tint: M.red)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .disabled(working)
            if failed {
                Text("Die foto lukte niet. Probeer een andere.")
                    .font(M.font(12, .semiBold))
                    .foregroundStyle(M.red)
            }
        }
    }

    private func process(_ work: @escaping () async -> Data?) {
        working = true
        failed = false
        Task {
            let data = await work()
            withAnimation(M.Motion.settle) {
                if let data { photo?.wrappedValue = data } else { failed = true }
                working = false
            }
        }
    }

    private func roll() {
        var shape = Int.random(in: 0..<AvatarShape.count)
        if shape == avatarIndex { shape = (shape + 1) % AvatarShape.count }
        withAnimation(M.Motion.quick) {
            avatarIndex = shape
            rampIndex = Int.random(in: 0..<M.playerRamp.count)
        }
    }
}

/// Knoplabel in de stijl van de omlijnde knop, ook bruikbaar in een PhotosPicker.
private struct PhotoActionLabel: View {
    let title: String
    var tint: Color = M.ink

    var body: some View {
        Text(title)
            .font(M.font(13, .extraBold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(M.surface)
            .overlay(Rectangle().stroke(tint, lineWidth: 1.5))
            .contentShape(.rect)
    }
}

/// De systeemcamera, met de voorcamera als die er is: een profielfoto maak
/// je meestal van jezelf of van wie tegenover je zit.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}
