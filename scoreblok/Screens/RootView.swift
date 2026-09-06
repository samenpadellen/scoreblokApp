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
    @Query private var players: [Player]
    @State private var router = Router()
    @State private var pending = PendingAction.shared
    @State private var showingStorage = false
    @Environment(\.scenePhase) private var scenePhase

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
        GeometryReader { proxy in
            // Drie maten: een volle zijbalk, een smallere, en onder de
            // 620 pt helemaal geen kolom meer maar een strook bovenin.
            let total = proxy.size.width
            let stacked = total < 620
            let sidebarWidth: CGFloat = total < 900 ? 168 : M.sidebarWidth
            let contentWidth = stacked ? total : total - sidebarWidth - 2

            Group {
                if stacked {
                    VStack(spacing: 0) {
                        topBar
                        Rectangle().fill(M.ruleHeavy).frame(width: nil, height: 2)
                        workspace
                    }
                } else {
                    HStack(spacing: 0) {
                        sidebar(width: sidebarWidth)
                        Rectangle().fill(M.ruleHeavy).frame(width: 2)
                        workspace
                    }
                }
            }
            .environment(\.contentWidth, contentWidth)
        }
        .background(M.paper)
        .environment(router)
        .overlay { if showingStorage { StoragePanel { showingStorage = false } } }
        .onChange(of: scenePhase) { _, phase in
            // Naar de achtergrond: eerst zeker wegschrijven.
            if phase != .active { Storage.save(context) }
        }
        .task {
            ArchivoFont.registerIfNeeded()
            BuiltInGames.seedIfNeeded(in: context)
        }
        .onChange(of: pending.startGameID) { _, id in
            // Siri of Shortcuts heeft een spel gekozen.
            guard let id, let template = templates.first(where: { $0.id == id }) else { return }
            router.screen = .setup(template)
            pending.startGameID = nil
        }
        .task(id: matches.count) {
            SpotlightIndex.reindex(matches: matches, players: players)
        }
        .onOpenURL { url in
            // Vanuit Spotlight of een deeplink: open het potje of de speler.
            guard let id = UUID(uuidString: url.lastPathComponent) else { return }
            if let match = matches.first(where: { $0.id == id }) {
                router.screen = match.mode == .scorecard ? .card(match) : .board(match)
            } else if let player = players.first(where: { $0.id == id }) {
                router.screen = .detail(player)
            }
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

    /// Het werkvlak met, als er een potje loopt, de balk eronder.
    private var workspace: some View {
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

    // MARK: - Strook bovenin, bij een smal venster

    /// Dezelfde vorm als de periodefilters op het statistiekenscherm: één rij
    /// segmenten met haarlijnen ertussen en het actieve vak in inkt.
    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark(size: 18, markSize: 26)
                Spacer()
                Button {
                    showingStorage = true
                } label: {
                    Text(Storage.mode.title.uppercased())
                        .font(M.font(10, .semiBold))
                        .tracking(em: 0.12, size: 10)
                        .foregroundStyle(Storage.mode.isFailed ? M.red : M.inkAlpha(0.5))
                        .frame(minHeight: M.tap)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            Hairline()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(NavSection.allCases) { section in
                        let isActive = router.screen.section == section
                        Button {
                            router.go(section)
                        } label: {
                            Text(section.rawValue)
                                .font(M.font(12.5, .extraBold))
                                .foregroundStyle(isActive ? M.paper : M.ink)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 46)
                                .background(isActive ? M.ink : .clear)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(M.hairline).frame(width: 1, height: 46)
                    }
                }
            }
        }
        .background(M.paperDeep)
    }

    // MARK: - Zijbalk

    private func sidebar(width: CGFloat) -> some View {
        let compact = width < M.sidebarWidth
        return VStack(spacing: 0) {
            Wordmark(size: compact ? 19 : 22, markSize: compact ? 28 : 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: compact ? 16 : 20,
                                    bottom: 16, trailing: 12))
            Hairline()

            ForEach(NavSection.allCases) { section in
                navRow(section, compact: compact)
                Hairline()
            }

            Spacer(minLength: 0)

            Rectangle().fill(M.ruleHeavy).frame(height: 2)
            Button {
                showingStorage = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(Storage.mode.title,
                                 tint: Storage.mode.isFailed ? M.red : M.inkAlpha(0.5))
                    Text(Storage.mode.detail)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(Storage.mode.isFailed ? M.red : M.inkAlpha(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? 16 : 20)
                .padding(.vertical, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width)
        .background(M.paperDeep)
    }

    private func navRow(_ section: NavSection, compact: Bool = false) -> some View {
        let isActive = router.screen.section == section
        return Button {
            router.go(section)
        } label: {
            HStack(spacing: 0) {
                Text(section.rawValue)
                    .font(M.font(compact ? 13.5 : 14.5, isActive ? .extraBold : .semiBold))
                    .tracking(em: 0.02, size: compact ? 13.5 : 14.5)
                    .foregroundStyle(isActive ? M.paper : M.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text(isActive ? "●" : "")
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.paper.opacity(0.5))
            }
            .padding(.horizontal, compact ? 16 : 20)
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
