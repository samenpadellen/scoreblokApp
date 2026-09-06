import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Een sjabloon zoals het model het voorstelt. Alles is een voorstel: de
/// editor vult de velden in, jij houdt het laatste woord.
struct GameSuggestion {
    var name: String
    var mono: String
    var mode: ScoringMode
    var roundCount: Int
    var winsByLowest: Bool
    var allowNegative: Bool
    var unitLabel: String
    var minPlayers: Int
    var maxPlayers: Int
    var eliminationLimit: Int
    var roundLabels: [String]
    var supportsJokers: Bool
}

#if canImport(FoundationModels)

/// De vorm waarin het model antwoordt. Elke beschrijving stuurt de generatie,
/// zodat er geen vrije tekst uitkomt maar een ingevuld sjabloon.
@Generable(description: "Een sjabloon voor een gezelschapsspel dat je met pen en papier bijhoudt")
struct GeneratedGame {
    @Guide(description: "Korte Nederlandse naam van het spel, zonder aanhalingstekens")
    var name: String

    @Guide(description: "Monogram van precies twee hoofdletters, afgeleid van de naam")
    var mono: String

    @Guide(description: "De manier van tellen", .anyOf([
        "rondes optellen", "alleen winnaar", "scorekaart", "een eindscore", "afvallen"
    ]))
    var mode: String

    @Guide(description: "Vast aantal rondes; 0 als het spel doorloopt tot iemand wint",
           .range(0...30))
    var roundCount: Int

    @Guide(description: "true als de laagste eindstand wint, false als de hoogste wint")
    var winsByLowest: Bool

    @Guide(description: "true als een speler in een ronde onder nul kan komen")
    var allowNegative: Bool

    @Guide(description: "Wat je per ronde noteert, in meervoud: punten, kaarten, slagen of fiches")
    var unitLabel: String

    @Guide(description: "Kleinste aantal spelers", .range(1...12))
    var minPlayers: Int

    @Guide(description: "Grootste aantal spelers", .range(1...12))
    var maxPlayers: Int

    @Guide(description: "Aantal strafpunten waarbij een speler afvalt; 0 als het spel geen afvalgrens kent",
           .range(0...200))
    var eliminationLimit: Int

    @Guide(description: "De opdracht per ronde als elke ronde een eigen opgave heeft, in speelvolgorde. Leeg als alle rondes gelijk zijn.",
           .count(0...30))
    var roundLabels: [String]

    @Guide(description: "true als er met jokers gespeeld wordt en het zinvol is die apart te tellen")
    var usesJokers: Bool
}

#endif

/// Stelt een spelsjabloon voor uit een beschrijving in gewone taal, met het
/// model dat op het apparaat zelf draait. Zonder Apple Intelligence blijft de
/// editor gewoon met de hand te bedienen.
@Observable
final class GameAssistant {

    enum State: Equatable {
        case idle
        case thinking
        case failed(String)
    }

    /// Waarom de knop er niet is, in gewone taal.
    enum Readiness: Equatable {
        case ready
        case unsupportedDevice
        case notEnabled
        case downloading
        case unavailable

        var explanation: String? {
            switch self {
            case .ready: nil
            case .unsupportedDevice: "Dit apparaat ondersteunt Apple Intelligence niet."
            case .notEnabled: "Zet Apple Intelligence aan in Instellingen om dit te gebruiken."
            case .downloading: "Het model wordt nog gedownload."
            case .unavailable: "Apple Intelligence is hier niet beschikbaar."
            }
        }
    }

    private(set) var state: State = .idle

    var readiness: Readiness {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unsupportedDevice
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .downloading
            @unknown default: return .unavailable
            }
        }
        #else
        return .unavailable
        #endif
    }

    var isReady: Bool { readiness == .ready }

    private static let instructions = """
    Je helpt bij het opzetten van een scoreblok voor gezelschapsspellen.
    Uit een korte beschrijving leid je af hoe het spel geteld wordt.

    Houd je aan wat er staat. Verzin geen rondes als er geen aantal genoemd is;
    kies dan 0. Verzin geen opdrachten per ronde als het spel die niet kent.
    Bij spellen waar je overgebleven kaarten telt, is de eenheid "kaarten" en
    wint de laagste stand. Antwoord in het Nederlands.
    """

    func suggest(from description: String) async -> GameSuggestion? {
        #if canImport(FoundationModels)
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isReady else { return nil }

        state = .thinking
        defer { if state == .thinking { state = .idle } }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: "Zet dit om in een sjabloon: \(trimmed)",
                generating: GeneratedGame.self,
                options: GenerationOptions(temperature: 0.3)
            )
            state = .idle
            return Self.convert(response.content)
        } catch {
            state = .failed("Het voorstel lukte niet. Probeer het korter te omschrijven.")
            return nil
        }
        #else
        return nil
        #endif
    }

    func clearError() {
        if case .failed = state { state = .idle }
    }

    #if canImport(FoundationModels)
    /// Vertaalt het antwoord naar de begrippen van de app en snijdt bij waar
    /// het model buiten de perken gaat.
    private static func convert(_ generated: GeneratedGame) -> GameSuggestion {
        let mode: ScoringMode = switch generated.mode.lowercased() {
        case let value where value.contains("winnaar"): .winnerOnly
        case let value where value.contains("scorekaart"): .scorecard
        case let value where value.contains("eindscore"): .finalScore
        case let value where value.contains("afvallen"): .elimination
        default: .roundsCumulative
        }

        let mono = generated.mono
            .filter(\.isLetter)
            .uppercased()
        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackMono = String(name.filter(\.isLetter).prefix(2)).uppercased()

        let labels = generated.roundLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let minimum = max(1, min(generated.minPlayers, 12))
        let maximum = max(minimum, min(generated.maxPlayers, 12))

        return GameSuggestion(
            name: name,
            mono: mono.count == 2 ? mono : (fallbackMono.count == 2 ? fallbackMono : "XX"),
            mode: mode,
            // Kent het spel een opdracht per ronde, dan bepaalt die het aantal.
            roundCount: labels.isEmpty ? max(0, min(generated.roundCount, 30)) : labels.count,
            winsByLowest: generated.winsByLowest,
            allowNegative: generated.allowNegative,
            unitLabel: generated.unitLabel.isEmpty ? "punten" : generated.unitLabel.lowercased(),
            minPlayers: minimum,
            maxPlayers: maximum,
            eliminationLimit: mode == .elimination ? max(1, generated.eliminationLimit) : 10,
            roundLabels: mode == .roundsCumulative ? labels : [],
            supportsJokers: mode == .roundsCumulative && generated.usesJokers
        )
    }
    #endif
}
