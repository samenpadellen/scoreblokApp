import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Een kort verslag van een afgerond potje, geschreven door het model op het
/// apparaat zelf. De app rekent de feiten uit; het model maakt er alleen
/// zinnen van. Er gaat niets naar internet.
@MainActor
@Observable
final class MatchReporter {

    enum State: Equatable {
        case idle
        case writing
        case done
        case failed
    }

    private(set) var text = ""
    private(set) var state: State = .idle

    /// Een verslag schrijf je één keer; terug naar dit scherm toont hetzelfde.
    private static var written: [UUID: String] = [:]

    /// Alleen met Apple Intelligence aan, en als het model Nederlands kan.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportedLanguages.contains { $0.languageCode?.identifier == "nl" }
        #else
        return false
        #endif
    }

    private static let instructions = """
    Je schrijft een kort verslag van een potje dat net aan tafel gespeeld is, \
    in de toon van een droge, licht geestige sportverslaggever op de lokale radio.

    Regels:
    - Nederlands, twee of drie zinnen, samen hooguit zestig woorden.
    - Gebruik alleen de feiten die je krijgt. Verzin geen gebeurtenissen, \
    citaten, spelregels of emoties.
    - Noem de winnaar. Een spannende wisseling van de leiding of een grote \
    ronde mag je uitlichten.
    - Geen emoji, geen hashtags, geen opsomming, geen aanhalingstekens.
    """

    func write(for match: Match, again: Bool = false) async {
        if !again, let known = Self.written[match.id] {
            text = known
            state = .done
            return
        }
        guard Self.isAvailable, state != .writing else { return }

        #if canImport(FoundationModels)
        state = .writing
        text = ""
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let stream = session.streamResponse(to: Self.facts(for: match),
                                                options: GenerationOptions(temperature: again ? 1.0 : 0.8))
            for try await snapshot in stream {
                text = snapshot.content
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.written[match.id] = text
            state = text.isEmpty ? .failed : .done
        } catch {
            text = ""
            state = .failed
        }
        #endif
    }

    /// De feiten, uitgerekend door de app en niet door het model.
    static func facts(for match: Match) -> String {
        let standings = match.standings
        let unit = match.unitLabel
        var lines: [String] = ["Spel: \(match.gameName)"]

        switch match.mode {
        case .winnerOnly:
            lines.append("Er telt alleen de volgorde waarin spelers klaar waren.")
        case .elimination:
            lines.append("Wie \(match.eliminationLimit) \(unit) haalt, valt af.")
        case .scorecard:
            lines.append("Geteld op een scorekaart.")
        default:
            lines.append(match.winsByLowest ? "De laagste stand wint." : "De hoogste stand wint.")
        }

        lines.append("Eindstand:")
        for standing in standings {
            var line = "\(standing.rank). \(standing.player.name)"
            if match.mode != .winnerOnly { line += ": \(standing.total) \(unit)" }
            if match.tracksJokers {
                let jokers = match.totalJokers(for: standing.player)
                if jokers > 0 { line += ", \(jokers) jokers" }
            }
            if standing.isEliminated { line += " (afgevallen)" }
            lines.append(line)
        }

        let rounds = match.orderedRounds.filter { !$0.entries.isEmpty }
        if match.mode == .roundsCumulative || match.mode == .elimination, rounds.count > 1 {
            let players = match.orderedPlayers
            let lower = match.winsByLowest
            var totals: [UUID: Int] = [:]
            var leaders: [String] = []
            var best: (name: String, value: Int, round: Int)?

            for (index, round) in rounds.enumerated() {
                for player in players {
                    guard let value = round.value(for: player.id) else { continue }
                    totals[player.id, default: 0] += value
                    if best == nil || (lower ? value < best!.value : value > best!.value) {
                        best = (player.name, value, index + 1)
                    }
                }
                let leader = players.min { a, b in
                    let left = totals[a.id] ?? 0, right = totals[b.id] ?? 0
                    return lower ? left < right : left > right
                }
                leaders.append(leader?.name ?? "")
            }

            lines.append("Gespeelde rondes: \(rounds.count)")
            let changes = zip(leaders, leaders.dropFirst()).filter { $0 != $1 }.count
            lines.append("Aantal keer dat de leiding wisselde: \(changes)")
            lines.append("Leider halverwege: \(leaders[max(0, leaders.count / 2 - 1)])")
            if let best {
                lines.append("Opvallendste ronde: \(best.name) met \(best.value) \(unit) in ronde \(best.round)")
            }
        }

        if standings.count > 1, match.mode != .winnerOnly {
            lines.append("Verschil tussen de nummers 1 en 2: \(abs(standings[0].total - standings[1].total)) \(unit)")
        }
        lines.append("Speelduur: \(match.durationText)")
        return lines.joined(separator: "\n")
    }
}
