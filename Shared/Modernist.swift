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

    // MARK: - Vlakken
    //
    // Eén regel die je vanzelf leert: wit is waar je iets doet, papier is
    // waar je iets leest. Rijen, knoppen, velden en toetsen liggen op het
    // witte vlak; cijfers, tabellen en uitleg op het papier eronder. Wat
    // gekozen of actief is krijgt een rode waas met een rood randje.

    /// Het werkvlak: alles wat je kunt aantikken of invullen.
    static let surface = Color(hex: 0xFCFBFB)
    /// Gekozen of actief: net genoeg rood om op te vallen tussen wit.
    static let activeWash = Color(hex: 0xFFF1ED)
    /// Breedte van het rode randje links van wat actief is.
    static let activeEdge: CGFloat = 3

    static func inkAlpha(_ a: Double) -> Color { ink.opacity(a) }

    // MARK: - Verlopen voor de widgets

    /// Het accent als vlak, van licht naar diep. Alleen op het beginscherm:
    /// binnen de app blijft alles vlak.
    static let redGradient = LinearGradient(
        colors: [Color(hex: 0xF4481F), Color(hex: 0xC8250A)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// De donkere tegenhanger, voor StandBy op de lader.
    static let inkGradient = LinearGradient(
        colors: [Color(hex: 0x2A2827), Color(hex: 0x0B0A0A)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

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
            guard let url = Bundle.main.url(forResource: weight.fileName, withExtension: "ttf")
            else { continue }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

            // De PostScript-naam uit het bestand halen; die hebben we nodig
            // om er via Font.custom naar te verwijzen.
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                    as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute)
                    as? String
            else { continue }

            registeredNames[weight] = name
        }
    }

    /// De geregistreerde PostScript-naam, voor tekenwerk via CoreText.
    static func postScriptName(_ weight: ArchivoWeight) -> String? {
        registerIfNeeded()
        return registeredNames[weight]
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


extension View {
    /// Letterspatiëring zoals het ontwerp die in em opgeeft.
    func tracking(em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }
}


// MARK: - Opmaak

extension Double {
    /// Nederlands decimaalteken, zoals in het ontwerp ("2,3").
    func dutch(_ places: Int = 1) -> String {
        String(format: "%.\(places)f", self).replacingOccurrences(of: ".", with: ",")
    }

    var percentText: String { "\(Int((self * 100).rounded()))%" }
}

extension Int {
    var signedText: String {
        self > 0 ? "+\(self)" : (self < 0 ? "−\(abs(self))" : "0")
    }

    /// "▲ +2", "▼ −3" of "—" voor een trendregel.
    var trendText: String {
        if self == 0 { return "—" }
        return self > 0 ? "▲ +\(self)" : "▼ −\(abs(self))"
    }
}
