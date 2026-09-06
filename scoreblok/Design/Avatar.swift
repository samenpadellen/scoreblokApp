import SwiftUI

/// Meetkundige spelersmarkeringen. Geen plaatjes: harde vormen in de inkt- en
/// papierkleuren van de speler, leesbaar op 16pt én op 64pt. De vorm is een
/// tweede signaal naast de kleur, zodat twee spelers met dezelfde beginletter
/// nooit op elkaar lijken.
struct AvatarShape: Shape {
    let index: Int

    static let count = 12

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        // Alles binnen een vierkant met marge, zodat elke vorm optisch even
        // zwaar oogt.
        let inset = size * 0.24
        let box = CGRect(x: rect.midX - size / 2 + inset,
                         y: rect.midY - size / 2 + inset,
                         width: size - inset * 2,
                         height: size - inset * 2)
        var path = Path()

        switch ((index % Self.count) + Self.count) % Self.count {
        case 0:
            path.addEllipse(in: box)
        case 1:
            path.addEllipse(in: box)
            path.addEllipse(in: box.insetBy(dx: box.width * 0.28, dy: box.height * 0.28))
        case 2:
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
            path.closeSubpath()
        case 3:
            path.move(to: CGPoint(x: box.minX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
            path.closeSubpath()
        case 4:
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.midY))
            path.closeSubpath()
        case 5:
            let arm = box.width * 0.3
            path.addRect(CGRect(x: box.midX - arm / 2, y: box.minY, width: arm, height: box.height))
            path.addRect(CGRect(x: box.minX, y: box.midY - arm / 2, width: box.width, height: arm))
        case 6:
            let thickness = box.height * 0.3
            path.move(to: CGPoint(x: box.minX, y: box.minY))
            path.addLine(to: CGPoint(x: box.midX, y: box.midY - thickness / 2))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY + thickness))
            path.addLine(to: CGPoint(x: box.midX, y: box.midY + thickness / 2))
            path.addLine(to: CGPoint(x: box.minX, y: box.minY + thickness))
            path.closeSubpath()
            path.addRect(CGRect(x: box.minX, y: box.maxY - thickness,
                                width: box.width, height: thickness))
        case 7:
            path.addArc(center: CGPoint(x: box.midX, y: box.midY),
                        radius: box.width / 2,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.closeSubpath()
        case 8:
            path.move(to: CGPoint(x: box.midX, y: box.midY))
            path.addArc(center: CGPoint(x: box.midX, y: box.midY),
                        radius: box.width / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.closeSubpath()
            path.addArc(center: CGPoint(x: box.midX, y: box.midY),
                        radius: box.width / 2,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: box.midX, y: box.midY))
            path.closeSubpath()
        case 9:
            let bar = box.height * 0.26
            path.addRect(CGRect(x: box.minX, y: box.minY, width: box.width, height: bar))
            path.addRect(CGRect(x: box.minX, y: box.maxY - bar, width: box.width, height: bar))
        case 10:
            let dot = box.width * 0.26
            for column in 0..<2 {
                for row in 0..<2 where !(column == 1 && row == 1) {
                    path.addEllipse(in: CGRect(x: box.minX + CGFloat(column) * (box.width - dot),
                                               y: box.minY + CGFloat(row) * (box.height - dot),
                                               width: dot, height: dot))
                }
            }
        default:
            path.move(to: CGPoint(x: box.minX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// De markering van één speler: vorm in de inktkleur op het vlak van de speler.
struct PlayerMark: View {
    let player: Player
    var size: CGFloat = 34

    var body: some View {
        AvatarShape(index: player.avatarIndex)
            .fill(player.inkColor)
            .frame(width: size, height: size)
            .background(player.color)
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
