import SwiftUI
import CoreGraphics
import CoreText

/// De vormtaal uit het ontwerp: Archivo, 0px radius, harde scheidslijnen,
/// rood uitsluitend voor de primaire actie en de leider.
enum M {

    // MARK: - Kleuren

    /// Inkt — bijna zwart, de basiskleur voor tekst en zware randen.
    static let ink = Color(hex: 0x201E1D)
    /// Papier — de achtergrond van het werkvlak.
    static let paper = Color(hex: 0xF3F2F2)
    /// Iets dieper papier, voor zijbalk, banden en gemarkeerde rijen.
    static let paperDeep = Color(hex: 0xEAE9E9)
    /// De rand van het toetsenblok en gedempte vlakken.
    static let paperKey = Color(hex: 0xE0DEDD)
    /// Haarlijn tussen rijen en kolommen.
    static let hairline = Color(hex: 0xD7D3D3)
    /// Rood — alleen primaire actie, leider en accent. Nooit decoratief.
    static let red = Color(hex: 0xEC3013)
    static let redPressed = Color(hex: 0xDD2B0F)
    /// Zacht rood vlak achter de geselecteerde cel.
    static let redWash = Color(hex: 0xFFE0D9)
    static let redTint = Color(hex: 0xEC3013).opacity(0.05)

    static func inkAlpha(_ a: Double) -> Color { ink.opacity(a) }
    static func paperAlpha(_ a: Double) -> Color { paper.opacity(a) }

    /// De zware scheidslijn (2px in het ontwerp) tussen hoofdgebieden.
    static let ruleHeavy = ink.opacity(0.4)

    /// Neutrale ramp voor spelers. Kleur is nooit het enige signaal —
    /// de initiaal staat er altijd bij.
    static let playerRamp: [(bg: Int, ink: Int)] = [
        (0xEC3013, 0xF3F2F2),
        (0x2D2B2B, 0xF3F2F2),
        (0x605D5D, 0xF3F2F2),
        (0x9B9797, 0x201E1D),
        (0xD7D3D3, 0x201E1D),
        (0x444141, 0xF3F2F2),
        (0x7D7979, 0xF3F2F2),
        (0xBAB6B6, 0x201E1D)
    ]

    // MARK: - Maatvoering

    /// Minimale tikdoelmaat; het ontwerp houdt overal 44pt aan.
    static let tap: CGFloat = 44
    static let sidebarWidth: CGFloat = 214
    static let roundColumnWidth: CGFloat = 72

    // MARK: - Typografie

    /// Vaste schaal uit het ontwerp. `font:` waarden zijn 1-op-1 overgenomen.
    static func font(_ size: CGFloat, _ weight: ArchivoWeight) -> Font {
        ArchivoFont.font(size: size, weight: weight)
    }

    static func display(_ size: CGFloat) -> Font { font(size, .extraBold) }
}

enum ArchivoWeight {
    case regular, semiBold, extraBold

    var fileName: String {
        switch self {
        case .regular: "Archivo-400"
        case .semiBold: "Archivo-600"
        case .extraBold: "Archivo-800"
        }
    }

    /// Terugval als de bundel het lettertype niet kan registreren.
    var systemWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .semiBold: .semibold
        case .extraBold: .heavy
        }
    }
}

/// Registreert de meegeleverde Archivo-bestanden bij CoreText, zodat er geen
/// UIAppFonts-sleutel in de Info.plist nodig is.
enum ArchivoFont {
    private static var registeredNames: [ArchivoWeight: String] = [:]
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        for weight in [ArchivoWeight.regular, .semiBold, .extraBold] {
            guard let url = Bundle.main.url(forResource: weight.fileName, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url),
                  let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider) else { continue }

            CTFontManagerRegisterGraphicsFont(font, nil)
            if let name = font.postScriptName as String? {
                registeredNames[weight] = name
            }
        }
    }

    static func font(size: CGFloat, weight: ArchivoWeight) -> Font {
        registerIfNeeded()
        if let name = registeredNames[weight] {
            return .custom(name, size: size)
        }
        // Condensed komt van de systeemfonts het dichtst bij Archivo.
        return .system(size: size, weight: weight.systemWeight).width(.condensed)
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
