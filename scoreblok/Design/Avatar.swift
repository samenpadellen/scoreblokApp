import SwiftUI

/// De markering van één speler: vorm in de inktkleur op het vlak van de speler.
struct PlayerMark: View {
    let player: Player
    var size: CGFloat = 34

    var body: some View {
        AvatarShape(index: player.avatarIndex)
            .fill(player.inkColor)
            .frame(width: size, height: size)
            .background(player.color)
            .accessibilityLabel(player.name)
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

/// Kiezer voor de markering van een speler: elke vorm en elke kleur uit de
/// neutrale ramp staan er los in, met een worp-knop voor wie niet wil kiezen.
struct AvatarPicker: View {
    @Binding var avatarIndex: Int
    @Binding var rampIndex: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                AvatarSwatch(avatarIndex: avatarIndex, rampIndex: rampIndex, size: 64)
                Text("Vorm en kleur samen maken de speler herkenbaar, ook op de kleinste maat.")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                OutlineButton(title: "Gooi opnieuw") { roll() }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Vorm")
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<AvatarShape.count, id: \.self) { index in
                        Button { avatarIndex = index } label: {
                            AvatarShape(index: index)
                                .fill(avatarIndex == index ? M.paper : M.ink)
                                .padding(2)
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(avatarIndex == index ? M.ink : M.paperDeep)
                                .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Kleur")
                HStack(spacing: 6) {
                    ForEach(0..<M.playerRamp.count, id: \.self) { index in
                        Button { rampIndex = index } label: {
                            Rectangle()
                                .fill(Color(hex: M.playerRamp[index].bg))
                                .frame(height: 32)
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    Rectangle().stroke(M.ink,
                                                       lineWidth: rampIndex == index ? 3 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func roll() {
        var shape = Int.random(in: 0..<AvatarShape.count)
        if shape == avatarIndex { shape = (shape + 1) % AvatarShape.count }
        avatarIndex = shape
        rampIndex = Int.random(in: 0..<M.playerRamp.count)
    }
}
