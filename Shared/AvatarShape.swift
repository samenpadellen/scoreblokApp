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

