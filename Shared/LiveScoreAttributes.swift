import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Het lopende potje op het toegangsscherm en in het Dynamic Island. De app
/// start het zodra er iets op het blok staat, werkt het bij bij elke
/// ingevulde waarde, en laat na afloop nog even de eindstand staan.
nonisolated struct LiveScoreAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "ronde 4 van 9", of "Eindstand" na afloop.
        var position: String
        /// De stand, de leider eerst.
        var lines: [Line]
        var isFinished: Bool
        var updatedAt: Date
    }

    struct Line: Codable, Hashable, Identifiable {
        var id: UUID
        var name: String
        var initial: String
        var total: Int
        /// Verschil met de leider; 0 voor de leider zelf.
        var gap: Int
        var rampIndex: Int
        var avatarIndex: Int
    }

    var matchID: UUID
    var gameName: String
    var mono: String
    var unitLabel: String
    /// "laagste totaal wint"
    var rule: String
    /// Accentkleur van het spel, licht genoeg voor het donkere eiland.
    var accentHex: Int?
}
#endif
