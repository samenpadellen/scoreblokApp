import Foundation
import SwiftData

/// De ingebouwde sjablonen. Ze zijn met dezelfde editor gemaakt als eigen
/// spellen: alle puntwaarden staan hier als data, niet in de scorelogica.
enum BuiltInGames {

    static func keerOpKeer() -> ScorecardSpec {
        let values: [(String, Int)] = [
            ("A", 5), ("B", 3), ("C", 3), ("D", 3), ("E", 2), ("F", 2), ("G", 2),
            ("H", 1), ("I", 5), ("J", 3), ("K", 3), ("L", 3), ("M", 2), ("N", 1), ("O", 5)
        ]
        return ScorecardSpec(
            columnsTitle: "Kolommen A–O — tik een volle kolom aan",
            columns: values.map {
                ScoreColumn(key: $0.0, label: $0.0, kind: .toggle, value: $0.1, section: "kolommen")
            },
            bonusesTitle: "Kleurbonussen — 5 punten per volle kleur",
            bonuses: ["Geel", "Groen", "Blauw", "Oranje", "Paars"].map {
                ScoreBonus(key: $0.lowercased(), label: "\($0) compleet", value: 5)
            },
            penaltyTitle: "Jokers — ×−1",
            penaltyLabel: "ongebruikte jokers",
            penaltyPerUnit: -1,
            penaltyMax: 8,
            sectionBonus: nil
        )
    }

    static func yahtzee() -> ScorecardSpec {
        let upper = ["Enen", "Tweeën", "Drieën", "Vieren", "Vijven", "Zessen"]
        let lower = ["Drie gelijk", "Vier gelijk", "Full house",
                     "Kleine straat", "Grote straat", "Yahtzee", "Chance"]
        var columns = upper.map {
            ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "boven")
        }
        columns += lower.map {
            ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "onder")
        }
        return ScorecardSpec(
            columnsTitle: "13 categorieën — tik een vak en vul het aantal in",
            columns: columns,
            bonusesTitle: "Bonussen",
            bonuses: [],
            penaltyTitle: nil,
            penaltyLabel: nil,
            penaltyPerUnit: 0,
            penaltyMax: 0,
            sectionBonus: SectionBonus(section: "boven", threshold: 63, bonus: 35,
                                       label: "Bovenste helft ≥ 63 → +35")
        )
    }

    static func qwixx() -> ScorecardSpec {
        ScorecardSpec(
            columnsTitle: "Vier rijen — vul de behaalde punten per rij in",
            columns: ["Rood", "Geel", "Groen", "Blauw"].map {
                ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "rijen")
            },
            bonusesTitle: "Bonussen",
            bonuses: [],
            penaltyTitle: "Missers — ×−5",
            penaltyLabel: "gemiste worpen",
            penaltyPerUnit: -5,
            penaltyMax: 4,
            sectionBonus: nil
        )
    }

    /// De opdrachten van Jokeren, in speelvolgorde. Elke ronde vraagt een
    /// andere combinatie; wie niet uitkomt houdt zijn kaarten. Aan het eind
    /// wint wie de minste kaarten overhield.
    static let jokerenRounds = [
        "Drie op een rij",
        "Drie dezelfde",
        "Vier op een rij",
        "Vier dezelfde",
        "Vijf op een rij",
        "In één keer uit"
    ]

    /// De lijst zoals hij op het Spelen-scherm staat, in deze volgorde.
    static func all() -> [GameTemplate] {
        var index = 0
        func next() -> Int { defer { index += 1 }; return index }

        return [
            GameTemplate(name: "Jokeren", mono: "JO", mode: .roundsCumulative,
                         roundCount: jokerenRounds.count, winsByLowest: true,
                         roundLabels: jokerenRounds,
                         supportsJokers: true,
                         // Je telt de kaarten die je overhoudt, niet punten.
                         unitLabel: "kaarten",
                         isBuiltIn: true, sortIndex: next()),

            GameTemplate(name: "Keer op Keer", mono: "KK", mode: .scorecard,
                         winsByLowest: false, minPlayers: 1, maxPlayers: 6,
                         scorecard: keerOpKeer(), isBuiltIn: true,
                         subtitleNote: "scorekaart · 15 kolommen", sortIndex: next()),

            GameTemplate(name: "Rummikub", mono: "RU", mode: .roundsCumulative,
                         roundCount: 0, winsByLowest: true,
                         isBuiltIn: true, sortIndex: next()),

            GameTemplate(name: "Pesten", mono: "PE", mode: .winnerOnly,
                         isBuiltIn: true, sortIndex: next()),

            GameTemplate(name: "Yahtzee", mono: "YA", mode: .scorecard,
                         winsByLowest: false, minPlayers: 1, maxPlayers: 6,
                         scorecard: yahtzee(), isBuiltIn: true,
                         subtitleNote: "13 categorieën", sortIndex: next()),

            GameTemplate(name: "Toepen", mono: "TO", mode: .elimination,
                         eliminationLimit: 10, isBuiltIn: true, sortIndex: next()),

            GameTemplate(name: "Klaverjassen", mono: "KL", mode: .roundsCumulative,
                         roundCount: 16, winsByLowest: false, minPlayers: 4, maxPlayers: 4,
                         isBuiltIn: true, subtitleNote: "16 spellen · roem apart",
                         sortIndex: next()),

            GameTemplate(name: "Qwixx", mono: "QX", mode: .scorecard,
                         winsByLowest: false, minPlayers: 2, maxPlayers: 5,
                         scorecard: qwixx(), isBuiltIn: true,
                         subtitleNote: "4 rijen · missers ×−5", sortIndex: next()),

            GameTemplate(name: "Kolonisten", mono: "KO", mode: .finalScore,
                         winsByLowest: false, minPlayers: 3, maxPlayers: 6,
                         isBuiltIn: true, sortIndex: next()),

            GameTemplate(name: "30 Seconds", mono: "30", mode: .roundsCumulative,
                         roundCount: 0, winsByLowest: false, minPlayers: 4,
                         isBuiltIn: true, subtitleNote: "teams in v2", sortIndex: next())
        ]
    }

    /// Zet de sjablonen klaar bij een lege database.
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<GameTemplate>())) ?? []
        guard existing.isEmpty else { return }
        for template in all() { context.insert(template) }
    }
}
