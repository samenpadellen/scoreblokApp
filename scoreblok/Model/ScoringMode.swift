import Foundation

/// De vijf scoremodi uit de spel-editor. De modus bepaalt hoe een potje
/// gespeeld en geteld wordt; puntwaarden staan in het sjabloon, niet in code.
enum ScoringMode: String, CaseIterable, Codable, Identifiable {
    case roundsCumulative
    case winnerOnly
    case scorecard
    case finalScore
    case elimination

    var id: String { rawValue }

    var name: String {
        switch self {
        case .roundsCumulative: "Rondes optellen"
        case .winnerOnly: "Alleen winnaar"
        case .scorecard: "Scorekaart"
        case .finalScore: "Eén eindscore"
        case .elimination: "Afvallen"
        }
    }

    var explanation: String {
        switch self {
        case .roundsCumulative:
            "Per ronde één getal per speler; het totaal telt op. Winnaar is hoogste óf laagste."
        case .winnerOnly:
            "Geen punten. Je legt alleen de eindvolgorde vast, of enkel wie won."
        case .scorecard:
            "Vaste categorieën met eigen invoerregels; de eindscore volgt uit een formule."
        case .finalScore:
            "Eén getal per speler aan het eind van het potje."
        case .elimination:
            "Strafpunten tellen op; wie de grens raakt ligt eruit. Laatste over wint."
        }
    }

    /// Voorbeeldspellen, zoals de editor ze rechts toont.
    var examples: String {
        switch self {
        case .roundsCumulative: "Jokeren · Rummikub · Klaverjassen"
        case .winnerOnly: "Pesten · Mens erger je niet"
        case .scorecard: "Keer op Keer · Yahtzee · Qwixx"
        case .finalScore: "Kolonisten"
        case .elimination: "Toepen"
        }
    }
}

// MARK: - Scorekaart-sjabloon

/// Eén invulbare categorie op een scorekaart.
struct ScoreColumn: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        /// Aan of uit; levert `value` punten op.
        case toggle
        /// Een getal dat de speler zelf intikt.
        case number
    }

    var key: String
    var label: String
    var kind: Kind
    var value: Int
    /// Groepeert kolommen voor de sectiebonus (bijv. Yahtzee's bovenste helft).
    var section: String

    var id: String { key }
}

/// Een bonus die je aanvinkt, bijvoorbeeld "Geel compleet · 5 punten".
struct ScoreBonus: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var value: Int

    var id: String { key }
}

/// Sectiebonus: haal je in een sectie de drempel, dan komt er een bonus bij.
struct SectionBonus: Codable, Hashable {
    var section: String
    var threshold: Int
    var bonus: Int
    var label: String
}

/// Alles wat een scorekaart-spel definieert. Bevroren in het potje bij de start.
struct ScorecardSpec: Codable, Hashable {
    var columnsTitle: String
    var columns: [ScoreColumn]
    var bonusesTitle: String
    var bonuses: [ScoreBonus]
    /// Aftrekpost met een teller, zoals ongebruikte jokers (×−1).
    var penaltyTitle: String?
    var penaltyLabel: String?
    var penaltyPerUnit: Int
    var penaltyMax: Int
    var sectionBonus: SectionBonus?

    static let empty = ScorecardSpec(columnsTitle: "CATEGORIEËN",
                                     columns: [],
                                     bonusesTitle: "BONUSSEN",
                                     bonuses: [],
                                     penaltyTitle: nil,
                                     penaltyLabel: nil,
                                     penaltyPerUnit: 0,
                                     penaltyMax: 0,
                                     sectionBonus: nil)

    var hasPenalty: Bool { penaltyTitle != nil && penaltyPerUnit != 0 }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> ScorecardSpec? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ScorecardSpec.self, from: data)
    }
}
