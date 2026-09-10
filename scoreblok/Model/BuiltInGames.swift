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

    /// Wingspan telt aan het eind zes soorten punten op, zoals op het
    /// scoreblok in de doos.
    static func wingspan() -> ScorecardSpec {
        let categories = ["Vogels", "Bonuskaarten", "Rondedoelen",
                          "Eieren", "Voedsel op kaarten", "Weggestopte kaarten"]
        return ScorecardSpec(
            columnsTitle: "Zes categorieën — vul de punten per categorie in",
            columns: categories.map {
                ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "punten")
            },
            bonusesTitle: "Bonussen",
            bonuses: [],
            penaltyTitle: nil,
            penaltyLabel: nil,
            penaltyPerUnit: 0,
            penaltyMax: 0,
            sectionBonus: nil
        )
    }

    /// Cascadia: punten per dier volgens de scoringskaarten, punten per
    /// grootste habitat, de bonus voor de grootste habitats en de
    /// overgebleven natuurfiches.
    static func cascadia() -> ScorecardSpec {
        var columns = ["Beren", "Wapiti's", "Zalmen", "Haviken", "Vossen"].map {
            ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "dieren")
        }
        columns += ["Bergen", "Bossen", "Prairies", "Moerassen", "Rivieren"].map {
            ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "habitats")
        }
        columns += ["Habitatbonus", "Natuurfiches"].map {
            ScoreColumn(key: $0, label: $0, kind: .number, value: 0, section: "overig")
        }
        return ScorecardSpec(
            columnsTitle: "Dieren, habitats en bonussen — vul de punten in",
            columns: columns,
            bonusesTitle: "Bonussen",
            bonuses: [],
            penaltyTitle: nil,
            penaltyLabel: nil,
            penaltyPerUnit: 0,
            penaltyMax: 0,
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
        /// In de spellenkast: beschikbaar, maar niet in het overzicht tot je
        /// het eruit haalt.
        func inCupboard(_ template: GameTemplate) -> GameTemplate {
            template.isPutAway = true
            return template
        }

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
                         isBuiltIn: true, subtitleNote: "teams in v2", sortIndex: next()),

            // Per ronde imiteert iedereen één geluid; de hoogste score wint de
            // kaart van die ronde. Je telt dus kaarten, geen punten, en de
            // groep spreekt vooraf af wanneer het klaar is — vandaar open einde.
            GameTemplate(name: "Golden GOAT", mono: "GG", mode: .roundsCumulative,
                         roundCount: 0, winsByLowest: false,
                         minPlayers: 2, maxPlayers: 10,
                         unitLabel: "kaarten",
                         isBuiltIn: true,
                         subtitleNote: "open einde · meeste kaarten wint",
                         sortIndex: next()),

            // MARK: In de kast
            //
            // Populaire bord- en gezelschapsspellen. Ze staan klaar maar
            // niet in beeld: wie ze speelt haalt ze uit de spellenkast.
            // Rummikub, 30 Seconds en Catan (Kolonisten) staan hierboven al.

            inCupboard(GameTemplate(
                name: "Monopoly", mono: "MO", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 8, isBuiltIn: true,
                subtitleNote: "wie overblijft wint", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Ticket to Ride Europe", mono: "TR", mode: .finalScore,
                winsByLowest: false, minPlayers: 2, maxPlayers: 5, isBuiltIn: true,
                subtitleNote: "eindscore · routes, kaarten en stations", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Mens Erger Je Niet", mono: "ME", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 6, isBuiltIn: true,
                subtitleNote: "eerst alle pionnen thuis", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Risk", mono: "RI", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 6, isBuiltIn: true,
                subtitleNote: "verover de wereld", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Codenames", mono: "CN", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 8, isBuiltIn: true,
                subtitleNote: "twee teams · alleen winnaar", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Stratego", mono: "ST", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 2, isBuiltIn: true,
                subtitleNote: "vlag veroverd · twee spelers", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Wingspan", mono: "WS", mode: .scorecard,
                winsByLowest: false, minPlayers: 1, maxPlayers: 5,
                scorecard: wingspan(), isBuiltIn: true,
                subtitleNote: "scorekaart · 6 categorieën", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Cluedo", mono: "CL", mode: .winnerOnly,
                minPlayers: 3, maxPlayers: 6, isBuiltIn: true,
                subtitleNote: "wie de zaak oplost", sortIndex: next())),

            // Per ronde krijgt iedereen punten; het spel eindigt zodra
            // iemand 30 punten heeft.
            inCupboard(GameTemplate(
                name: "Dixit", mono: "DX", mode: .roundsCumulative,
                roundCount: 0, winsByLowest: false, minPlayers: 3, maxPlayers: 8,
                isBuiltIn: true, subtitleNote: "tot iemand 30 punten heeft", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Azul", mono: "AZ", mode: .finalScore,
                winsByLowest: false, minPlayers: 2, maxPlayers: 4, isBuiltIn: true,
                subtitleNote: "eindscore · muur en bonussen", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Carcassonne", mono: "CA", mode: .finalScore,
                winsByLowest: false, minPlayers: 2, maxPlayers: 5, isBuiltIn: true,
                subtitleNote: "eindscore · wegen, steden en kloosters", sortIndex: next())),

            // Samenwerken: iedereen wint of verliest samen. De app kent nog
            // geen samenspelmodus, dus dit telt als een gewoon potje.
            inCupboard(GameTemplate(
                name: "Pandemic", mono: "PA", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 4, isBuiltIn: true,
                subtitleNote: "samen winnen of verliezen", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Exploding Kittens", mono: "EK", mode: .winnerOnly,
                minPlayers: 2, maxPlayers: 5, isBuiltIn: true,
                subtitleNote: "wie niet ontploft wint", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Ark Nova", mono: "AN", mode: .finalScore,
                winsByLowest: false, minPlayers: 1, maxPlayers: 4, isBuiltIn: true,
                subtitleNote: "eindscore · aantrekking en natuurbehoud", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Cascadia", mono: "CS", mode: .scorecard,
                winsByLowest: false, minPlayers: 1, maxPlayers: 4,
                scorecard: cascadia(), isBuiltIn: true,
                subtitleNote: "scorekaart · dieren en habitats", sortIndex: next())),

            // Rondes tellen op tot iemand 100 punten haalt; wie dan het
            // minst heeft wint. Een ronde kan negatief uitvallen.
            inCupboard(GameTemplate(
                name: "Skyjo", mono: "SK", mode: .roundsCumulative,
                roundCount: 0, winsByLowest: true, allowNegative: true,
                minPlayers: 2, maxPlayers: 8, isBuiltIn: true,
                subtitleNote: "tot iemand 100 haalt · laagste wint", sortIndex: next())),

            inCupboard(GameTemplate(
                name: "Hitster", mono: "HI", mode: .finalScore,
                winsByLowest: false, minPlayers: 2, maxPlayers: 10,
                unitLabel: "kaarten", isBuiltIn: true,
                subtitleNote: "eerst 10 kaarten op volgorde", sortIndex: next()))
        ]
    }

    /// Zet de sjablonen klaar, en vult later toegevoegde ingebouwde spellen
    /// aan bij een blok dat er al is. Bestaande sjablonen worden met rust
    /// gelaten: je eigen aanpassingen blijven staan.
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<GameTemplate>())) ?? []
        let known = Set(existing.map(\.name))
        let highest = existing.map(\.sortIndex).max() ?? -1

        for template in all() where !known.contains(template.name) {
            if !existing.isEmpty {
                // Nieuwkomers achteraan, zodat de volgorde niet omgooit.
                template.sortIndex += highest + 1
            }
            context.insert(template)
        }
    }
}
