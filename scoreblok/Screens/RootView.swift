import AppIntents
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
    case cupboard
    case statsDetail
    /// De statistieken die je vrijspeelt met tien potjes van één spel.
    case insights(String)

    var section: NavSection {
        switch self {
        case .play, .setup, .board, .card, .finish, .cupboard: .play
        case .players, .detail: .players
        case .stats, .statsDetail, .insights: .stats
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
    @State private var cloud = CloudStatus.shared
    @Environment(StoreController.self) private var store
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.spotlight) private var spotlightEnabled = true
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @State private var showingTour = false
    /// Samen bijwerken met iemand anders: open zolang dit niet nil is.
    @State private var samenRequest: SamenRequest?
    /// Voor de actieve tab en zijbalkrij die naar hun nieuwe plek schuiven.
    @Namespace private var navSpace

    /// De rondleiding staat bij de eerste start over alles heen, en is later
    /// terug te halen uit de instellingen.
    private var showsTour: Bool { !onboarded || showingTour }

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
        layout
            .background(M.paper)
            .background { PhotoBookSync() }
            .background {
                OpenMatchWatcher(id: openMatch?.id) {
                    SnapshotWriter.update(from: matches, players: players)
                }
            }
            .modifier(MatchHandoff(match: handoffMatch, onContinue: continueMatch))
            .environment(router)
            .modifier(SettingsHosting(isPresented: $showingSettings))
            .modifier(SamenHosting(request: $samenRequest,
                                   open: { showingSettings = false; samenRequest = .host },
                                   leave: leaveMatchScreens))
            .overlay {
                if showsTour {
                    OnboardingView { exit in
                        onboarded = true
                        showingTour = false
                        AppTips.ready = true
                        switch exit {
                        case .players: router.screen = .players
                        case .games: router.screen = .play
                        case .none: break
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: showsTour) { _, showing in
                if showing { AppTips.ready = false }
            }
            .animation(.snappy(duration: 0.25), value: showsTour)
            .environment(\.openTour) { showingTour = true }
            .modifier(LifecycleActions(
                onScenePhase: { phase in
                    if phase == .active {
                        cloud.refresh()
                    } else {
                        Storage.save(context)
                        SnapshotWriter.update(from: matches, players: players)
                    }
                },
                onAppear: {
                    ArchivoFont.registerIfNeeded()
                    AppTips.configure()
                    AppTips.ready = onboarded
                    store.reroute = { map in reroute(map) }
                    BuiltInGames.seedIfNeeded(in: context)
                    ScoreblokShortcuts.updateAppShortcutParameters()
                },
                onPendingGame: { id in
                    guard let template = templates.first(where: { $0.id == id }) else { return }
                    router.screen = .setup(template)
                    pending.startGameID = nil
                },
                pendingGameID: pending.startGameID,
                matchCount: matches.count,
                onMatchCountChange: {
                    SnapshotWriter.update(from: matches, players: players)
                    if spotlightEnabled {
                        SpotlightIndex.reindex(matches: matches, players: players)
                    }
                    // Selectie opschonen als het geopende potje verdwenen is.
                    switch router.screen {
                    case .board(let m), .card(let m), .finish(let m):
                        if !matches.contains(where: { $0.id == m.id }) { router.screen = .play }
                    default: break
                    }
                },
                onOpen: { url in
                    // Een gescande QR-code om samen bij te werken.
                    if let invite = SamenInvite(url: url) {
                        showingSettings = false
                        samenRequest = SamenRequest(invite: invite)
                        return
                    }
                    // scoreblok://match/<uuid>, scoreblok://setup, of een
                    // Spotlight-treffer op id.
                    if url.host() == "play" {
                        showingSettings = false
                        router.screen = .play
                        return
                    }
                    if url.host() == "setup" || url.lastPathComponent == "setup" {
                        if let template = templates.first { router.screen = .setup(template) }
                        return
                    }
                    guard let id = UUID(uuidString: url.lastPathComponent) else { return }
                    if let match = matches.first(where: { $0.id == id }) {
                        router.screen = match.mode == .scorecard ? .card(match) : .board(match)
                    } else if let player = players.first(where: { $0.id == id }) {
                        router.screen = .detail(player)
                    }
                }
            ))
    }

    /// Het potje dat je nu bijhoudt, om op een ander apparaat verder te gaan.
    private var handoffMatch: Match? {
        switch router.screen {
        case .board(let match), .card(let match): match.isOpen ? match : nil
        default: nil
        }
    }

    /// Verder op dit apparaat met het potje van een ander apparaat. Staat het
    /// hier niet (lokale opslag), dan opent de app gewoon.
    private func continueMatch(_ id: UUID) {
        guard let match = matches.first(where: { $0.id == id }) else { return }
        showingSettings = false
        router.screen = match.mode == .scorecard ? .card(match) : .board(match)
    }

    /// Weg van een scherm dat één potje of speler toont, voordat die wordt
    /// verwijderd, bijvoorbeeld bij ontkoppelen van een speelgroep.
    private func leaveMatchScreens() {
        switch router.screen {
        case .board, .card, .finish, .detail:
            router.screen = .play
        default:
            break
        }
    }

    /// Het opruimen na synchroniseren gaat een kopie verwijderen die dit
    /// scherm misschien toont. Dan eerst naar de versie die blijft; anders
    /// leest het scherm een verwijderd spel en valt de app om.
    private func reroute(_ map: [PersistentIdentifier: any PersistentModel]) {
        func kept<T: PersistentModel>(_ item: T) -> T? { map[item.persistentModelID] as? T }
        switch router.screen {
        case .setup(let template):
            if let survivor = kept(template) { router.screen = .setup(survivor) }
        case .board(let match):
            if let survivor = kept(match) { router.screen = .board(survivor) }
        case .card(let match):
            if let survivor = kept(match) { router.screen = .card(survivor) }
        case .finish(let match):
            if let survivor = kept(match) { router.screen = .finish(survivor) }
        case .detail(let player):
            if let survivor = kept(player) { router.screen = .detail(survivor) }
        case .custom(let template?):
            if let survivor = kept(template) { router.screen = .custom(survivor) }
        default:
            break
        }
    }

    /// Drie maten: een volle zijbalk, een smallere, en onder de 620 pt
    /// helemaal geen kolom meer maar een strook bovenin.
    private var layout: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let stacked = total < 620
            let sidebarWidth: CGFloat = total < 900 ? 168 : M.sidebarWidth
            let contentWidth = stacked ? total : total - sidebarWidth - 2

            Group {
                if stacked {
                    VStack(spacing: 0) {
                        compactHeader
                        Rectangle().fill(M.ruleHeavy).frame(height: 2)
                        workspace
                        tabBar
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
    }

    /// Wat er onderin de zijbalk staat: de opslag als die stuk is, anders
    /// wat iCloud werkelijk doet.
    private var storageTitle: String {
        Storage.mode.isFailed ? Storage.mode.title : cloud.title
    }

    private var storageDetail: String {
        Storage.mode.isFailed ? Storage.mode.detail : cloud.detail
    }

    private var storageIsProblem: Bool {
        Storage.mode.isFailed || (cloud.containerIsCloud && !cloud.isHealthy)
    }

    /// Het werkvlak met, als er een potje loopt, de balk eronder.
    private var workspace: some View {
        VStack(spacing: 0) {
            content
                .id(router.screen)
                .transition(.opacity)
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
        .animation(M.Motion.quick, value: router.screen)
    }

    // MARK: - Strook bovenin, bij een smal venster

    /// Kop op een telefoon: alleen het woordmerk en de ingang naar de
    /// instellingen. De navigatie zit onderin, in duimbereik.
    private var compactHeader: some View {
        HStack {
            Wordmark(size: 18, markSize: 26)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Text("Instellingen")
                    .font(M.font(12, .semiBold))
                    .foregroundStyle(Storage.mode.isFailed ? M.red : M.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(Rectangle().stroke(Storage.mode.isFailed ? M.red : M.ink,
                                                lineWidth: 1.5))
                    .frame(minHeight: M.tap)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .background(M.paperDeep)
    }

    /// De zijbalk wordt een tabbalk met dezelfde bestemmingen. Eigen spel
    /// staat op de telefoon onderin Spelen en heeft hier geen eigen tab.
    private var tabBar: some View {
        let tabs: [NavSection] = [.play, .players, .stats, .history]

        return VStack(spacing: 0) {
            Rectangle().fill(M.ruleHeavy).frame(height: 2)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, section in
                    let isActive = router.screen.section == section
                    Button {
                        withAnimation(M.Motion.settle) { router.go(section) }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Color.clear.frame(width: 16, height: 3)
                                if isActive {
                                    Rectangle()
                                        .fill(M.red)
                                        .frame(width: 16, height: 3)
                                        .matchedGeometryEffect(id: "tab-streep", in: navSpace)
                                }
                            }
                            Text(section.rawValue)
                                .font(M.font(11.5, isActive ? .extraBold : .semiBold))
                                .tracking(em: 0.04, size: 11.5)
                                .foregroundStyle(isActive ? M.paper : M.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background {
                            if isActive {
                                Rectangle()
                                    .fill(M.ink)
                                    .matchedGeometryEffect(id: "tab-vlak", in: navSpace)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if index < tabs.count - 1 {
                                Rectangle().fill(M.hairline).frame(width: 1)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: router.screen.section)
            // Het systeem trekt de achtergrond van het onderste vlak door tot
            // onder de home-indicator. Deze strook zorgt dat dat papier is en
            // niet de inkt van het actieve tabblad.
            Rectangle().fill(M.paperDeep).frame(height: 1)
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
                showingSettings = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Instellingen")
                            .font(M.font(compact ? 13.5 : 14.5, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 4)
                        Text("›")
                            .font(M.font(17, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.45))
                    }
                    SectionLabel(storageTitle,
                                 tint: storageIsProblem ? M.red : M.inkAlpha(0.55))
                        .padding(.top, 6)
                    Text(storageDetail)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(storageIsProblem ? M.red : M.inkAlpha(0.7))
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
            withAnimation(M.Motion.settle) { router.go(section) }
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
            .background {
                if isActive {
                    Rectangle()
                        .fill(M.ink)
                        .matchedGeometryEffect(id: "zijbalk-vlak", in: navSpace)
                }
            }
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
        case .cupboard:
            CupboardScreen()
        case .statsDetail:
            StatsDetailScreen()
        case .insights(let gameName):
            InsightsScreen(gameName: gameName).id(gameName)
        }
    }
}

/// Werkt widgets en Live Activity bij zodra het lopende potje verandert:
/// afgerond, afgebroken of een nieuw potje.
private struct OpenMatchWatcher: View {
    let id: UUID?
    let onChange: () -> Void

    var body: some View {
        Color.clear.onChange(of: id) { onChange() }
    }
}

/// Handoff: het potje dat je op de iPad bijhoudt, gaat op je iPhone verder,
/// en andersom. Werkt als beide apparaten op iCloud staan.
private struct MatchHandoff: ViewModifier {
    static let activityType = "nl.scoreblok.app.potje"

    let match: Match?
    let onContinue: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .userActivity(Self.activityType, isActive: match != nil) { activity in
                guard let match else { return }
                activity.title = "\(match.gameName) bijhouden"
                activity.userInfo = ["potje": match.id.uuidString]
                activity.targetContentIdentifier = match.id.uuidString
                activity.isEligibleForHandoff = true
            }
            .onContinueUserActivity(Self.activityType) { activity in
                guard let raw = activity.userInfo?["potje"] as? String,
                      let id = UUID(uuidString: raw) else { return }
                onContinue(id)
            }
    }
}

/// Houdt de foto's in het geheugen gelijk met de database: na eigen
/// wijzigingen, na ophalen uit iCloud en na terugzetten.
private struct PhotoBookSync: View {
    @Query private var photos: [PlayerPhoto]

    private var signature: [String] {
        photos.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }.sorted()
    }

    var body: some View {
        Color.clear
            .onAppear { PhotoBook.shared.reload(photos) }
            .onChange(of: signature) { PhotoBook.shared.reload(photos) }
    }
}

/// Instellingen bovenop alles, met een zachte entree.
private struct SettingsHosting: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    SettingsPanel { isPresented = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(M.Motion.settle, value: isPresented)
    }
}

/// Het samen-scherm bovenop alles, en de acties om het te openen. Los van het
/// hoofdscherm, zodat de uitdrukking daar klein genoeg blijft.
private struct SamenHosting: ViewModifier {
    @Binding var request: SamenRequest?
    let open: () -> Void
    let leave: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let current = request {
                    SamenView(request: current) { request = nil }
                        .id(current.id)
                        .transition(.opacity)
                }
            }
            .animation(M.Motion.settle, value: request?.id)
            .environment(\.openSamen, open)
            .environment(\.leaveMatchScreens, leave)
    }
}

/// De levenscyclus van het hoofdscherm in één modifier. Los van het scherm
/// zelf, anders wordt de uitdrukking te groot voor de typecontrole.
private struct LifecycleActions: ViewModifier {
    let onScenePhase: (ScenePhase) -> Void
    let onAppear: () -> Void
    let onPendingGame: (UUID) -> Void
    let pendingGameID: UUID?
    let matchCount: Int
    let onMatchCountChange: () -> Void
    let onOpen: (URL) -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in onScenePhase(phase) }
            .task { onAppear() }
            .onChange(of: pendingGameID) { _, id in
                if let id { onPendingGame(id) }
            }
            .task(id: matchCount) { onMatchCountChange() }
            .onChange(of: matchCount) { _, _ in onMatchCountChange() }
            .onOpenURL { url in onOpen(url) }
    }
}
