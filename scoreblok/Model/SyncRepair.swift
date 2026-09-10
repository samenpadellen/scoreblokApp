import Foundation
import SwiftData

/// Ruimt op wat synchronisatie dubbel kan maken.
///
/// Waar dubbelingen vandaan komen:
/// - Elk apparaat zet bij de eerste start de ingebouwde spellen klaar, met
///   eigen id's. Synchroniseren twee apparaten, dan staat elk spel er twee keer.
/// - Twee apparaten beginnen tegelijk dezelfde ronde van hetzelfde potje, of
///   vullen dezelfde cel in.
/// - Een reservekopie of een overstap voegt gegevens samen voordat iCloud klaar
///   is met ophalen; dan komen dezelfde spelers en potjes later nog een keer
///   binnen.
///
/// De hoofdregel: elk apparaat moet dezelfde kopie bewaren. Kiest apparaat A
/// kopie 1 en apparaat B kopie 2, dan verwijdert elk de andere en is na het
/// synchroniseren alles weg. Daarom wordt de winnaar alleen bepaald door wat op
/// beide apparaten gelijk is: een id, een aanmaaktijd, de inhoud zelf.
///
/// Letterlijk gelijke kopieën met hetzelfde id zijn op die manier niet uit
/// elkaar te houden. Die ruimt alleen het apparaat op dat ze zelf veroorzaakte
/// door samen te voegen (`includeSameID`); de rest laat ze staan.
///
/// Er wordt pas aan het eind verwijderd. Eerst krijgt de app de kans om een
/// scherm dat een kopie toont om te zetten naar de bewaarde versie; anders
/// leest dat scherm een verwijderd spel en valt de app om.
@MainActor
enum SyncRepair {

    struct Report: CustomStringConvertible {
        var templates = 0
        var players = 0
        var matches = 0
        var rounds = 0
        var entries = 0
        var cards = 0
        /// Verwijderde kopie → de versie die bleef. Alleen voor spellen,
        /// spelers en potjes: dat is wat schermen vasthouden.
        var replacements: [PersistentIdentifier: any PersistentModel] = [:]

        var total: Int { templates + players + matches + rounds + entries + cards }

        var description: String {
            "spellen \(templates), spelers \(players), potjes \(matches), "
            + "rondes \(rounds), cellen \(entries), kaarten \(cards)"
        }
    }

    /// - Parameters:
    ///   - includeSameID: ook kopieën met hetzelfde id samenvoegen. Alleen op
    ///     het apparaat dat zelf heeft samengevoegd.
    ///   - beforeDeleting: krijgt de vervangingen vlak voordat er iets wordt
    ///     verwijderd, om schermen om te zetten.
    @discardableResult
    static func run(in context: ModelContext,
                    includeSameID: Bool,
                    beforeDeleting: ([PersistentIdentifier: any PersistentModel]) -> Void = { _ in }) -> Report {
        let pass = Pass(context: context)

        pass.mergeBuiltInTemplates()
        if includeSameID {
            pass.mergeSameIDTemplates()
            pass.mergePlayers()
            pass.mergeMatches()
        }
        for match in pass.alive(pass.fetch(Match.self)) {
            pass.mergeRounds(of: match, includeSameID: includeSameID)
            for round in pass.alive(match.rounds) {
                pass.mergeEntries(of: round, includeSameID: includeSameID)
            }
            pass.mergeCards(of: match, includeSameID: includeSameID)
        }

        guard !pass.doomed.isEmpty else { return pass.report }
        if !pass.report.replacements.isEmpty { beforeDeleting(pass.report.replacements) }
        for item in pass.doomed.values { context.delete(item) }
        Storage.save(context)
        return pass.report
    }

    /// Eén opruimronde. Houdt bij wat weg moet zonder het al te verwijderen,
    /// zodat latere stappen de te verwijderen kopieën overslaan.
    @MainActor
    private final class Pass {
        let context: ModelContext
        var report = Report()
        var doomed: [PersistentIdentifier: any PersistentModel] = [:]

        init(context: ModelContext) { self.context = context }

        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            alive((try? context.fetch(FetchDescriptor<T>())) ?? [])
        }

        func isAlive(_ item: some PersistentModel) -> Bool {
            !item.isDeleted && doomed[item.persistentModelID] == nil
        }

        func alive<T: PersistentModel>(_ items: [T]) -> [T] {
            items.filter { isAlive($0) }
        }

        func doom(_ item: some PersistentModel, keeper: (any PersistentModel)? = nil) {
            doomed[item.persistentModelID] = item
            if let keeper { report.replacements[item.persistentModelID] = keeper }
        }

        // MARK: Spellen

        /// Ingebouwde spellen op naam. Het kleinste id wint: dat is op elk
        /// apparaat hetzelfde spel.
        func mergeBuiltInTemplates() {
            let groups = Dictionary(grouping: fetch(GameTemplate.self).filter(\.isBuiltIn), by: \.name)
            for (_, copies) in groups where copies.count > 1 {
                let sorted = copies.sorted { $0.id.uuidString < $1.id.uuidString }
                let keeper = sorted[0]
                for copy in sorted.dropFirst() {
                    // Opgeborgen op één apparaat blijft opgeborgen.
                    if copy.isPutAway { keeper.isPutAway = true }
                    doom(copy, keeper: keeper)
                    report.templates += 1
                }
            }
        }

        func mergeSameIDTemplates() {
            for (_, copies) in Dictionary(grouping: fetch(GameTemplate.self), by: \.id) where copies.count > 1 {
                let sorted = copies.sorted { $0.createdAt < $1.createdAt }
                for copy in sorted.dropFirst() {
                    if copy.isPutAway { sorted[0].isPutAway = true }
                    doom(copy, keeper: sorted[0])
                    report.templates += 1
                }
            }
        }

        // MARK: Spelers

        func mergePlayers() {
            for (_, copies) in Dictionary(grouping: fetch(Player.self), by: \.id) where copies.count > 1 {
                let sorted = copies.sorted {
                    if $0.matches.count != $1.matches.count { return $0.matches.count > $1.matches.count }
                    return $0.createdAt < $1.createdAt
                }
                let keeper = sorted[0]
                for copy in sorted.dropFirst() {
                    // Eerst de potjes omhangen, dan pas de kopie weg. Anders
                    // verliest een potje zijn speler.
                    for match in copy.matches {
                        var seated = match.players.filter { $0.persistentModelID != copy.persistentModelID }
                        if !seated.contains(where: { $0.persistentModelID == keeper.persistentModelID }) {
                            seated.append(keeper)
                        }
                        match.players = seated
                    }
                    if copy.isMe { keeper.isMe = true }
                    if !copy.isArchived { keeper.isArchived = false }
                    doom(copy, keeper: keeper)
                    report.players += 1
                }
            }
        }

        // MARK: Potjes

        func mergeMatches() {
            for (_, copies) in Dictionary(grouping: fetch(Match.self), by: \.id) where copies.count > 1 {
                let sorted = copies.sorted {
                    let a = filledCells($0), b = filledCells($1)
                    if a != b { return a > b }
                    return $0.lastPlayedAt > $1.lastPlayedAt
                }
                let keeper = sorted[0]
                for copy in sorted.dropFirst() {
                    absorb(copy, into: keeper)
                    doom(copy, keeper: keeper)
                    report.matches += 1
                }
            }
        }

        private func filledCells(_ match: Match) -> Int {
            alive(match.rounds).reduce(0) { $0 + alive($1.entries).filter { $0.value != nil }.count }
                + alive(match.cards).count
        }

        /// Neemt over wat de kopie wel heeft en de bewaarde niet.
        private func absorb(_ copy: Match, into keeper: Match) {
            for player in copy.players
            where !keeper.players.contains(where: { $0.persistentModelID == player.persistentModelID }) {
                keeper.players.append(player)
            }
            for id in copy.seatOrder where !keeper.seatOrder.contains(id) {
                keeper.seatOrder.append(id)
            }
            if keeper.endedAt == nil { keeper.endedAt = copy.endedAt }
            keeper.lastPlayedAt = max(keeper.lastPlayedAt, copy.lastPlayedAt)

            for round in alive(copy.rounds) {
                if let target = alive(keeper.rounds).first(where: { $0.index == round.index }) {
                    fill(target, from: round)
                } else {
                    let created = MatchRound(index: round.index)
                    created.createdAt = round.createdAt
                    context.insert(created)
                    created.match = keeper
                    keeper.rounds.append(created)
                    fill(created, from: round)
                }
            }

            for card in alive(copy.cards) where !alive(keeper.cards).contains(where: { $0.playerID == card.playerID }) {
                let created = ScoreCard(playerID: card.playerID)
                created.columnKeys = card.columnKeys
                created.bonusKeys = card.bonusKeys
                created.numbersData = card.numbersData
                created.penaltyCount = card.penaltyCount
                context.insert(created)
                created.match = keeper
                keeper.cards.append(created)
            }
        }

        // MARK: Rondes

        /// Twee rondes met hetzelfde nummer in één potje: twee apparaten
        /// begonnen tegelijk aan dezelfde ronde. De eerst aangemaakte wint en
        /// krijgt de cellen van de ander erbij.
        func mergeRounds(of match: Match, includeSameID: Bool) {
            for (_, copies) in Dictionary(grouping: alive(match.rounds), by: \.index) where copies.count > 1 {
                let sorted = copies.sorted { $0.createdAt < $1.createdAt }
                // Precies dezelfde aanmaaktijd komt alleen uit een reservekopie:
                // een letterlijke kopie, niet uit elkaar te houden.
                if !includeSameID, sorted[0].createdAt == sorted[1].createdAt { continue }
                let keeper = sorted[0]
                for copy in sorted.dropFirst() {
                    fill(keeper, from: copy)
                    doom(copy)
                    report.rounds += 1
                }
            }
        }

        /// Vult lege cellen aan; een ingevulde waarde van de bewaarde ronde blijft.
        private func fill(_ target: MatchRound, from source: MatchRound) {
            for entry in alive(source.entries) {
                if let existing = alive(target.entries).first(where: { $0.playerID == entry.playerID }) {
                    if existing.value == nil, let value = entry.value { existing.value = value }
                    if existing.jokers == 0, entry.jokers > 0 { existing.jokers = entry.jokers }
                } else {
                    let created = ScoreEntry(playerID: entry.playerID, value: entry.value)
                    created.jokers = entry.jokers
                    context.insert(created)
                    target.entries.append(created)
                }
            }
        }

        // MARK: Cellen

        /// Twee cellen voor dezelfde speler in dezelfde ronde. Verschillen ze,
        /// dan wint een ingevulde waarde, daarna de hoogste — willekeurig,
        /// maar op elk apparaat dezelfde. Zijn ze gelijk, dan doet de dubbeling
        /// niets: de app leest toch de eerste.
        func mergeEntries(of round: MatchRound, includeSameID: Bool) {
            for (_, copies) in Dictionary(grouping: alive(round.entries), by: \.playerID) where copies.count > 1 {
                let identical = Set(copies.map { "\($0.value.map(String.init) ?? "-")|\($0.jokers)" }).count == 1
                if identical, !includeSameID { continue }
                let sorted = copies.sorted { a, b in
                    switch (a.value, b.value) {
                    case (nil, nil): return a.jokers > b.jokers
                    case (nil, _): return false
                    case (_, nil): return true
                    case let (x?, y?): return x != y ? x > y : a.jokers > b.jokers
                    }
                }
                for copy in sorted.dropFirst() {
                    doom(copy)
                    report.entries += 1
                }
            }
        }

        // MARK: Scorekaarten

        func mergeCards(of match: Match, includeSameID: Bool) {
            for (_, copies) in Dictionary(grouping: alive(match.cards), by: \.playerID) where copies.count > 1 {
                if Set(copies.map(Self.fingerprint)).count == 1, !includeSameID { continue }
                let sorted = copies.sorted { a, b in
                    let fa = Self.filled(a), fb = Self.filled(b)
                    if fa != fb { return fa > fb }
                    return Self.fingerprint(a) > Self.fingerprint(b)
                }
                for copy in sorted.dropFirst() {
                    doom(copy)
                    report.cards += 1
                }
            }
        }

        private static func filled(_ card: ScoreCard) -> Int {
            card.columnKeys.count + card.bonusKeys.count + card.numbers.count + card.penaltyCount
        }

        private static func fingerprint(_ card: ScoreCard) -> String {
            let numbers = card.numbers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            return [card.columnKeys.sorted().joined(separator: ","),
                    card.bonusKeys.sorted().joined(separator: ","),
                    numbers.joined(separator: ","),
                    String(card.penaltyCount)].joined(separator: "|")
        }
    }
}
