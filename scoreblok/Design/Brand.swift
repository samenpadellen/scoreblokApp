import SwiftUI

/// Het merkteken: vier staven op oplopende hoogte, doorgehaald door één regel.
/// Van dichtbij een ranglijst, van een afstand de turf van de keukentafel.
/// Alle maten liggen op een raster van 100 × 100, precies zoals het ontwerp.
struct ScoreblokMark: View {
    /// Kleur van de staven.
    var bars: Color = M.ink
    /// Kleur van de doorhaling.
    var rule: Color = M.red
    /// Vult het hele vierkant; alleen het app-icoon gebruikt dit.
    var field: Color?
    /// Staafbreedte op het raster van 100. Zwaarder bij kleine maten.
    var stroke: CGFloat = 12
    /// Hoogte van de doorhaling op het raster.
    var ruleY: CGFloat = 56

    /// Onder 32 pt valt het rood weg en wordt de doorhaling inkt;
    /// onder 24 pt hoort alleen het woordmerk te staan.
    static func forSize(_ size: CGFloat, onInk: Bool = false) -> ScoreblokMark {
        if onInk {
            return ScoreblokMark(bars: M.paper,
                                 rule: size < 32 ? M.paper : Color(hex: 0xFF563C))
        }
        return ScoreblokMark(bars: M.ink, rule: size < 32 ? M.ink : M.red)
    }

    private let barX: [CGFloat] = [9, 31, 53, 75]
    private let barTop: [CGFloat] = [50, 38, 26, 12]
    private let barBase: CGFloat = 82

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 100

            ZStack(alignment: .topLeading) {
                if let field {
                    Rectangle().fill(field)
                }
                ForEach(barX.indices, id: \.self) { index in
                    Rectangle()
                        .fill(bars)
                        .frame(width: stroke * unit,
                               height: (barBase - barTop[index]) * unit)
                        .offset(x: barX[index] * unit, y: barTop[index] * unit)
                }
                Rectangle()
                    .fill(rule)
                    .frame(width: 96 * unit, height: stroke * unit)
                    .offset(x: 2 * unit, y: ruleY * unit)
            }
            .frame(width: 100 * unit, height: 100 * unit)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Merkteken plus woordmerk, met de spatiëring uit de specificatie.
struct Wordmark: View {
    var size: CGFloat = 22
    var onInk: Bool = false
    /// Maat van het teken; het woordmerk schaalt mee.
    var markSize: CGFloat = 38

    var body: some View {
        HStack(spacing: markSize * 0.26) {
            ScoreblokMark.forSize(markSize, onInk: onInk)
                .frame(width: markSize, height: markSize)
            Text("Scoreblok")
                .font(M.font(size, .extraBold))
                .tracking(em: size >= 48 ? -0.038 : (size >= 24 ? -0.03 : -0.02), size: size)
                .foregroundStyle(onInk ? M.paper : M.ink)
                .fixedSize()
        }
    }
}
