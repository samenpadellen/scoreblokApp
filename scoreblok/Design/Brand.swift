import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

/// Het app-merk: één cijfer in Archivo 800, zo groot gezet dat de tegel het
/// afsnijdt. Geen symbool van scoren maar een fragment van het scorebord —
/// hetzelfde grote totaal dat boven elke spelerskolom staat.
///
/// Maten uit blok 05, herleid tot verhoudingen van de tegel:
/// korps 430/300, links −22/300, onder −104/300. Onder 60 pt vervalt de
/// uitsnede en staat het cijfer heel en gecentreerd.
struct FiveMark: View {
    /// Vlak achter het cijfer; `nil` laat de ondergrond doorlopen.
    var field: Color? = M.red
    var ink: Color = M.paper

    private static let sizeRatio: CGFloat = 430.0 / 300.0
    private static let leftRatio: CGFloat = -22.0 / 300.0
    private static let bottomRatio: CGFloat = -104.0 / 300.0
    private static let smallSizeRatio: CGFloat = 52.0 / 40.0
    private static let smallTopRatio: CGFloat = -6.0 / 40.0

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            if let field {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(field))
            }
            context.withCGContext { cg in
                draw(in: cg, side: side, height: size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    private func draw(in cg: CGContext, side: CGFloat, height: CGFloat) {
        guard let name = ArchivoFont.postScriptName(.extraBold) else { return }
        let cropped = side >= 60
        let fontSize = side * (cropped ? Self.sizeRatio : Self.smallSizeRatio)
        let font = CTFontCreateWithName(name as CFString, fontSize, nil)

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: cgColor(ink)
        ]
        guard let attributed = CFAttributedStringCreate(nil, "5" as CFString,
                                                        attributes as CFDictionary)
        else { return }
        let line = CTLineCreateWithAttributedString(attributed)

        // CSS line-height:1 zet het regelvak op de korpsgrootte; het cijfer
        // staat daarin met halve interlinie boven en onder.
        let halfLeading = (fontSize - (CTFontGetAscent(font) + CTFontGetDescent(font))) / 2
        let baselineInBox = halfLeading + CTFontGetAscent(font)

        let x: CGFloat
        let baselineFromTop: CGFloat
        if cropped {
            baselineFromTop = (side - (Self.bottomRatio * side) - fontSize) + baselineInBox
            x = Self.leftRatio * side
        } else {
            baselineFromTop = (Self.smallTopRatio * side) + baselineInBox
            x = (side - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) / 2
        }

        cg.textPosition = CGPoint(x: x, y: height - baselineFromTop)
        CTLineDraw(line, cg)
    }

    private func cgColor(_ color: Color) -> CGColor {
        #if canImport(UIKit)
        return UIColor(color).cgColor
        #else
        return NSColor(color).cgColor
        #endif
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
            // Binnen de app loopt rood nooit als vlak: het cijfer staat in
            // rood op de ondergrond, niet op een rood veld.
            FiveMark(field: nil, ink: onInk ? M.paper : M.red)
                .frame(width: markSize, height: markSize)
            Text("Scoreblok")
                .font(M.font(size, .extraBold))
                .tracking(em: size >= 48 ? -0.038 : (size >= 24 ? -0.03 : -0.02), size: size)
                .foregroundStyle(onInk ? M.paper : M.ink)
                .fixedSize()
        }
    }
}
