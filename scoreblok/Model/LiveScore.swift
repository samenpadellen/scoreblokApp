import ActivityKit
import Foundation

/// Houdt de Live Activity gelijk met het blok. Wordt aangeroepen vanuit
/// dezelfde plek die de widgets bijwerkt, zodat toegangsscherm, Dynamic
/// Island en widgets altijd hetzelfde zeggen.
@MainActor
enum LiveScore {
    /// Hoe lang een activiteit zonder nieuwe waarde nog als actueel geldt.
    private static let freshFor: TimeInterval = 4 * 3600
    /// Hoe lang de eindstand na afloop blijft staan.
    private static let finalFor: TimeInterval = 20 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.liveActivity) as? Bool ?? true
    }

    private static var running: [Activity<LiveScoreAttributes>] {
        Activity<LiveScoreAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// `matches` zijn de potjes die de aanroeper kent; daarmee ziet de app of
    /// een potje net is afgerond of juist is afgebroken.
    static func sync(open: WidgetSnapshot.OpenMatch?, matches: [Match]) {
        let activities = running
        guard isEnabled, let open else {
            for activity in activities {
                let id = activity.attributes.matchID
                if isEnabled, let match = matches.first(where: { $0.id == id }), match.counts {
                    finish(activity, with: match)
                } else if !isEnabled || !matches.contains(where: { $0.id == id && $0.isOpen }) {
                    end(activity)
                }
            }
            return
        }

        let state = LiveScoreAttributes.ContentState(
            position: open.position,
            lines: open.standings.prefix(6).map {
                .init(id: $0.id, name: $0.name, initial: $0.initial, total: $0.total,
                      gap: $0.gap, rampIndex: $0.rampIndex, avatarIndex: $0.avatarIndex)
            },
            isFinished: false,
            updatedAt: open.lastPlayed)

        var found = false
        for activity in activities {
            if activity.attributes.matchID == open.id {
                found = true
                guard activity.content.state != state else { continue }
                let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(freshFor))
                Task { await activity.update(content) }
            } else if let match = matches.first(where: { $0.id == activity.attributes.matchID }), match.counts {
                finish(activity, with: match)
            } else {
                end(activity)
            }
        }

        // Pas starten als er iets op het blok staat: een potje dat meteen
        // weer wordt afgebroken hoort niet op je toegangsscherm.
        let started = !open.playedRounds.isEmpty || open.standings.contains { $0.total != 0 }
        guard !found, started, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = LiveScoreAttributes(matchID: open.id, gameName: open.gameName, mono: open.mono,
                                             unitLabel: open.unitLabel, rule: open.rule,
                                             accentHex: open.accentHex)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state,
                                                           staleDate: .now.addingTimeInterval(freshFor)),
                                  pushType: nil)
    }

    /// Alles weg, bijvoorbeeld als je het uitzet.
    static func endAll() {
        for activity in running { end(activity) }
    }

    private static func finish(_ activity: Activity<LiveScoreAttributes>, with match: Match) {
        let standings = match.standings
        let leaderTotal = standings.first?.total ?? 0
        let state = LiveScoreAttributes.ContentState(
            position: "Eindstand",
            lines: standings.prefix(6).map {
                .init(id: $0.player.id, name: $0.player.name, initial: $0.player.initial,
                      total: $0.total, gap: abs($0.total - leaderTotal),
                      rampIndex: $0.player.rampIndex, avatarIndex: $0.player.avatarIndex)
            },
            isFinished: true,
            updatedAt: match.endedAt ?? .now)
        let content = ActivityContent(state: state, staleDate: nil)
        let policy = ActivityUIDismissalPolicy.after(.now.addingTimeInterval(finalFor))
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    private static func end(_ activity: Activity<LiveScoreAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
