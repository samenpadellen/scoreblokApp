import SwiftUI
import UIKit

/// De accentkleur van een spel, gehaald uit zijn afbeelding. Een lopend potje
/// draagt die kleur als rand, streep en waas, zodat je aan de kleur al ziet
/// welk potje het is. Rood blijft voor wat actief is en voor de actieknop.
/// Zonder afbeelding, of bij een grijze afbeelding, is het accent rood.
struct GameAccent: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    /// De kleur zelf, voor randen en strepen.
    var base: Color { Color(uiColor: baseUIColor) }

    /// Licht genoeg om op inkt te lezen: de "potje open"-kaart, de balk
    /// onderin en het Dynamic Island.
    var onInk: Color { Color(uiColor: onInkUIColor) }

    /// Donker genoeg om op papier te lezen, ook als vlak onder witte tekst.
    var onPaper: Color {
        // Geel en groen ogen bij dezelfde helderheid veel lichter dan blauw of rood.
        let light = (0.09...0.47).contains(hue)
        return Color(hue: hue, saturation: max(saturation, 0.6),
                     brightness: min(brightness, light ? 0.42 : 0.6))
    }

    /// Een zweem voor een vlak, zoals de kolom van de leider.
    var wash: Color { base.opacity(0.13) }

    /// Voor de widgets en de Live Activity, die de afbeeldingen niet hebben.
    var onInkHex: Int { Self.hex(onInkUIColor) }

    private var baseUIColor: UIColor {
        UIColor(hue: hue, saturation: saturation, brightness: min(max(brightness, 0.35), 0.95), alpha: 1)
    }

    /// Blauw en paars blijven op inkt donker, ook op volle helderheid; die
    /// worden dan bleker gemaakt tot ze even goed leesbaar zijn als geel of rood.
    private var onInkUIColor: UIColor {
        let dark = (0.55...0.88).contains(hue)
        return UIColor(hue: hue, saturation: min(saturation, dark ? 0.45 : 0.75),
                       brightness: max(brightness, dark ? 1 : 0.92), alpha: 1)
    }

    // MARK: - Uit de afbeelding

    static var fallback: GameAccent {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(M.red).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return GameAccent(hue: h, saturation: s, brightness: b)
    }

    @MainActor private static var cache: [String: GameAccent] = [:]

    @MainActor
    static func of(_ gameName: String) -> GameAccent {
        let key = GameArtwork.fileName(for: gameName)
        if let known = cache[key] { return known }
        let found = GameArtwork.image(for: gameName).flatMap(extract) ?? fallback
        cache[key] = found
        return found
    }

    /// De kleur die de afbeelding draagt: de pixels worden per tint in
    /// twaalf bakjes verdeeld, gewogen naar verzadiging en helderheid. Grijs,
    /// wit en zwart tellen niet mee, zodat een witte rand of zwarte letters
    /// het accent niet bepalen.
    private static func extract(_ image: UIImage) -> GameAccent? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 40
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var weight = [Double](repeating: 0, count: 12)
        var hues = [Double](repeating: 0, count: 12)
        var sats = [Double](repeating: 0, count: 12)
        var brights = [Double](repeating: 0, count: 12)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            let saturation = high == 0 ? 0 : delta / high
            guard saturation > 0.28, high > 0.25, delta > 0 else { continue }

            var hue: Double
            if high == r {
                hue = (g - b) / delta
            } else if high == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }

            let bucket = min(Int(hue * 12), 11)
            let w = saturation * saturation * high
            weight[bucket] += w
            hues[bucket] += hue * w
            sats[bucket] += saturation * w
            brights[bucket] += high * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > Double(side * side) * 0.02 else { return nil }
        let w = weight[best]
        return GameAccent(hue: hues[best] / w, saturation: sats[best] / w, brightness: brights[best] / w)
    }

    private static func hex(_ color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }
}
