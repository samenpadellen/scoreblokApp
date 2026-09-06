import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Zet afgeronde potjes en spelers in de zoekindex van het systeem, zodat je
/// ze vanuit Spotlight terugvindt zonder de app te openen.
enum SpotlightIndex {

    static let matchDomain = "nl.scoreblok.match"
    static let playerDomain = "nl.scoreblok.player"

    @MainActor
    static func reindex(matches: [Match], players: [Player]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        var items: [CSSearchableItem] = []

        for match in matches where match.counts {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = match.gameName
            let winner = match.standings.first.map { "\($0.player.name) won met \($0.total)" }
            let date = (match.endedAt ?? match.startedAt)
                .formatted(.dateTime.day().month(.wide).year())
            attributes.contentDescription = [date, winner]
                .compactMap { $0 }
                .joined(separator: " · ")
            attributes.keywords = match.players.map(\.name) + [match.gameName, "scoreblok"]
            attributes.contentCreationDate = match.startedAt

            items.append(CSSearchableItem(uniqueIdentifier: match.id.uuidString,
                                          domainIdentifier: matchDomain,
                                          attributeSet: attributes))
        }

        for player in players where !player.isArchived {
            let attributes = CSSearchableItemAttributeSet(contentType: .contact)
            attributes.title = player.name
            let played = matches.filter { m in
                m.counts && m.players.contains { $0.id == player.id }
            }
            let wins = played.filter { $0.standings.first?.player.id == player.id }.count
            attributes.contentDescription =
                "\(played.count) potjes · \(wins) gewonnen"
            attributes.keywords = [player.name, "speler", "scoreblok"]

            items.append(CSSearchableItem(uniqueIdentifier: player.id.uuidString,
                                          domainIdentifier: playerDomain,
                                          attributeSet: attributes))
        }

        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    /// Haalt een potje of speler weer uit de index.
    static func remove(ids: [UUID]) {
        guard CSSearchableIndex.isIndexingAvailable(), !ids.isEmpty else { return }
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }
}
