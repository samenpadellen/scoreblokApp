import SwiftUI
import SwiftData

/// De vijf hoofdsecties uit de zijbalk.
enum NavSection: String, CaseIterable, Identifiable {
    case play = "Spelen"
    case players = "Spelers"
    case stats = "Statistieken"
    case history = "Geschiedenis"
    case custom = "Eigen spel"

    var id: String { rawValue }
}

/// Waar we zijn. Subschermen houden hun sectie in de zijbalk gemarkeerd.
enum Screen: Hashable {
    case play
    case setup(GameTemplate)
    case board(Match)
    case card(Match)
    case finish(Match)
    case players
    case detail(Player)
    case stats
    case history
    case custom(GameTemplate?)

    var section: NavSection {
        switch self {
        case .play, .setup, .board, .card, .finish: .play
        case .players, .detail: .players
        case .stats: .stats
        case .history: .history
        case .custom: .custom
        }
    }
}

@Observable
final class Router {
    var screen: Screen = .play

    func go(_ section: NavSection) {
        switch section {
        case .play: screen = .play
        case .players: screen = .players
        case .stats: screen = .stats
        case .history: screen = .history
        case .custom: screen = .custom(nil)
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var templates: [GameTemplate]
    @Query private var matches: [Match]
    @State private var router = Router()

    /// Het lopende potje, als er een is.
    private var openMatch: Match? {
        matches
            .filter { !$0.isFinished && !$0.isAbandoned }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Op Spelen staat de grote kaart al, en op de schermen van het potje zelf
    /// is de balk overbodig.
    private var showsNowPlaying: Bool {
        switch router.screen {
        case .play, .setup, .board, .card, .finish: false
        default: true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(M.ruleHeavy).frame(width: 2)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsNowPlaying, let openMatch {
                    NowPlayingBar(match: openMatch) {
                        router.screen = openMatch.mode == .scorecard
                            ? .card(openMatch) : .board(openMatch)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(M.paper)
            .animation(.snappy(duration: 0.22), value: showsNowPlaying)
        }
        .background(M.paper)
        .environment(router)
        .task {
            ArchivoFont.registerIfNeeded()
            BuiltInGames.seedIfNeeded(in: context)
        }
        .onChange(of: matches.count) { _, _ in
            // Selectie opschonen als het geopende potje verdwenen is.
            switch router.screen {
            case .board(let m), .card(let m), .finish(let m):
                if !matches.contains(where: { $0.id == m.id }) { router.screen = .play }
            default: break
            }
        }
    }

    // MARK: - Zijbalk

    private var sidebar: some View {
        VStack(spacing: 0) {
            Wordmark(size: 22, markSize: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))
            Hairline()

            ForEach(NavSection.allCases) { section in
                navRow(section)
                Hairline()
            }

            Spacer(minLength: 0)

            Rectangle().fill(M.ruleHeavy).frame(height: 2)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(Storage.mode.title)
                Text(Storage.mode.detail)
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: M.sidebarWidth)
        .background(M.paperDeep)
    }

    private func navRow(_ section: NavSection) -> some View {
        let isActive = router.screen.section == section
        return Button {
            router.go(section)
        } label: {
            HStack(spacing: 0) {
                Text(section.rawValue)
                    .font(M.font(14.5, isActive ? .extraBold : .semiBold))
                    .tracking(em: 0.02, size: 14.5)
                    .foregroundStyle(isActive ? M.paper : M.ink)
                Spacer(minLength: 8)
                Text(isActive ? "●" : "")
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.paper.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(isActive ? M.ink : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inhoud

    @ViewBuilder
    private var content: some View {
        switch router.screen {
        case .play:
            PlayScreen()
        case .setup(let template):
            SetupScreen(template: template)
        case .board(let match):
            BoardScreen(match: match).id(match.id)
        case .card(let match):
            ScorecardScreen(match: match).id(match.id)
        case .finish(let match):
            FinishScreen(match: match).id(match.id)
        case .players:
            PlayersScreen()
        case .detail(let player):
            PlayerDetailScreen(player: player).id(player.id)
        case .stats:
            StatsScreen()
        case .history:
            HistoryScreen()
        case .custom(let template):
            CustomGameScreen(existing: template)
        }
    }
}
