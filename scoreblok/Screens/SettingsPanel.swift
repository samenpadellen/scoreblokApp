import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Instellingen en opslag op één plek. Alles wat bij één spel hoort staat in
/// het sjabloon; hier staat alleen wat over de hele app gaat.
struct SettingsPanel: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.isCompact) private var isCompact
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query private var matches: [Match]
    @Query private var templates: [GameTemplate]

    @AppStorage(SettingsKey.confirmRoundEnd) private var confirmRoundEnd = true
    @AppStorage(SettingsKey.showAbandoned) private var showAbandoned = true
    @AppStorage(SettingsKey.spotlight) private var spotlightEnabled = true
    @AppStorage(SettingsKey.statsPeriod) private var statsPeriod = StatsPeriod.days90.rawValue

    @State private var backupURL: URL?
    @State private var cloud = CloudStatus.shared
    @State private var importing = false
    @State private var message: String?
    @State private var isError = false
    @Environment(\.openTour) private var openTour
    @Environment(StoreController.self) private var store
    /// De kant waarnaar je wilt overstappen, zolang je dat nog bevestigt.
    @State private var confirmSwitch: StorageChoice?
    @State private var tipsReset = false

    var body: some View {
        ModalPanel(title: "Instellingen", width: 620, onClose: onClose) {
            ScrollView {
                VStack(spacing: 0) {
                    meSection
                    playSection
                    statsSection
                    cloudSection
                    storageSection
                    searchSection
                    helpSection
                    aboutSection
                    creditsSection
                }
            }
            .frame(maxHeight: 640)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { restore($0) }
        .task { backupURL = try? Backup.write(from: context) }
    }

    // MARK: - Wie ben jij

    private var meSection: some View {
        section("Jij", note: "Bepaalt wiens winstpercentage bovenaan de statistieken staat en tegen wie de onderlinge balans loopt.") {
            if players.isEmpty {
                note("Nog geen spelers.")
            }
            ForEach(players.filter { !$0.isArchived }) { player in
                RowButton(background: player.isMe ? M.inkAlpha(0.045) : .clear,
                          minHeight: 52) {
                    for other in players { other.isMe = (other.id == player.id) }
                    Storage.save(context)
                } content: {
                    HStack(spacing: 13) {
                        HardCheckbox(isOn: player.isMe)
                        PlayerMark(player: player, size: 28)
                        Text(player.name)
                            .font(M.font(14.5, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }
                Hairline()
            }
        }
    }

    // MARK: - Spelen

    private var playSection: some View {
        section("Spelen") {
            RuleRow(title: "Bevestigen bij einde ronde",
                    hint: "Toont de ingevulde ronde voor je doorgaat naar de volgende.",
                    minHeight: 72) {
                HardToggle(isOn: $confirmRoundEnd)
            }
            Hairline()
            RuleRow(title: "Afgebroken potjes tonen",
                    hint: "Ze tellen nergens in mee, maar blijven zichtbaar in de geschiedenis.",
                    minHeight: 72) {
                HardToggle(isOn: $showAbandoned)
            }
            Hairline()
        }
    }

    // MARK: - Statistieken

    private var statsSection: some View {
        section("Statistieken", note: "De periode waarop het scherm opent.") {
            SegmentedBar(options: StatsPeriod.allCases.map { ($0.rawValue, $0.rawValue) },
                         selection: $statsPeriod, fontSize: 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Lokaal of iCloud

    private var cloudSection: some View {
        let current = store.choice ?? .local
        return section("Opslag · \(current.title)",
                       tint: cloud.isHealthy ? M.inkAlpha(0.72) : M.red) {
            VStack(alignment: .leading, spacing: 10) {
                Text(current == .iCloud ? cloud.detail : "Alles staat alleen op dit apparaat.")
                    .font(M.font(14, .semiBold))
                    .foregroundStyle(cloud.isHealthy ? M.ink : M.red)
                    .fixedSize(horizontal: false, vertical: true)

                if current == .iCloud {
                    infoRow("Account", cloud.account.summary)
                    if let sync = cloud.lastSync {
                        infoRow("Laatste \(sync.kind)",
                                "\(sync.at.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
                                + (sync.succeeded ? "" : " · mislukt"))
                    }
                }

                Text(current == .iCloud
                     ? "Wat je invult gaat naar je andere apparaten met hetzelfde iCloud-account zodra ze online zijn. Bewaar toch af en toe een reservekopie: iCloud is een tweede kopie, geen archief."
                     : "Niets verlaat dit apparaat. Wil je je potjes ook op een ander apparaat, stap dan over naar iCloud.")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let target = confirmSwitch {
                    switchConfirmation(to: target)
                } else {
                    // Naast elkaar als het past; op een telefoon onder elkaar,
                    // anders worden beide knoppen afgekapt.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            switchButtons
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            switchButtons
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var switchButtons: some View {
        let current = store.choice ?? .local
        OutlineButton(title: current == .iCloud ? "Overstappen naar lokaal" : "Overstappen naar iCloud") {
            confirmSwitch = current == .iCloud ? .local : .iCloud
        }
        if current == .iCloud {
            OutlineButton(title: "Opnieuw controleren") { cloud.refresh() }
        }
    }

    /// Eerst zeggen wat er gebeurt, dan pas doen.
    private func switchConfirmation(to target: StorageChoice) -> some View {
        let blocked = target == .iCloud && !cloud.account.isAvailable
        return VStack(alignment: .leading, spacing: 10) {
            Text(target == .iCloud ? "Overstappen naar iCloud" : "Overstappen naar lokaal")
                .font(M.font(15, .extraBold))
                .foregroundStyle(M.ink)
            Text(target == .iCloud
                 ? "Je potjes gaan naar iCloud en daarna naar je andere apparaten. Staat daar al iets, dan wordt dat samengevoegd; er gaat niets verloren. De lokale kopie op dit apparaat wordt daarna opgeruimd."
                 : "Je potjes worden naar dit apparaat gekopieerd en dit apparaat stopt met synchroniseren. In iCloud en op je andere apparaten blijft alles staan.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Vooraf maakt de app automatisch een reservekopie.")
                .font(M.font(12, .semiBold))
                .foregroundStyle(M.inkAlpha(0.6))
            if blocked {
                Text("Kan nu niet. \(cloud.account.summary). Log in via de Instellingen-app en probeer het opnieuw.")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                SolidButton(title: "Overstappen", enabled: !blocked) {
                    confirmSwitch = nil
                    onClose()
                    Task { await store.switchTo(target) }
                }
                OutlineButton(title: "Annuleren") { confirmSwitch = nil }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .overlay(Rectangle().stroke(M.ink, lineWidth: 1.5))
        .task { if target == .iCloud { cloud.refresh() } }
    }

    // MARK: - Opslag

    private var storageSection: some View {
        section("Reservekopie",
                tint: Storage.mode.isFailed ? M.red : M.inkAlpha(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                if Storage.mode.isFailed {
                    Text(Storage.mode.detail)
                        .font(M.font(14, .semiBold))
                        .foregroundStyle(M.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(counts)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))

                if let message {
                    Text(message)
                        .font(M.font(12.5, .semiBold))
                        .foregroundStyle(isError ? M.red : M.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Een reservekopie is één bestand met alle spelers, spellen en potjes. Terugzetten voegt toe en werkt bij; er wordt nooit iets gewist.")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Text("Bewaar reservekopie")
                                .font(M.font(12.5, .extraBold))
                                .foregroundStyle(M.paper)
                                .padding(.horizontal, 16)
                                .frame(minHeight: M.tap)
                                .background(M.red)
                        }
                        .buttonStyle(.plain)
                    }
                    OutlineButton(title: "Zet kopie terug") { importing = true }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private var counts: String {
        let rounds = matches.reduce(0) { $0 + $1.rounds.count }
        return "\(matches.count) potjes · \(players.count) spelers · \(templates.count) spellen · \(rounds) rondes · \(Storage.storeDescription)"
    }

    // MARK: - Zoeken

    private var searchSection: some View {
        section("Zoeken") {
            RuleRow(title: "In Spotlight zetten",
                    hint: "Afgeronde potjes en spelers zijn dan te vinden vanuit de zoekfunctie van het systeem.",
                    minHeight: 72) {
                HardToggle(isOn: $spotlightEnabled)
            }
            Hairline()
            HStack(spacing: 10) {
                OutlineButton(title: "Index bijwerken") {
                    SpotlightIndex.reindex(matches: matches, players: players)
                    message = "De zoekindex is bijgewerkt."
                    isError = false
                }
                OutlineButton(title: "Uit de index halen") {
                    SpotlightIndex.removeAll()
                    message = "Alles is uit de zoekindex gehaald."
                    isError = false
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Uitleg

    private var helpSection: some View {
        section("Uitleg") {
            VStack(alignment: .leading, spacing: 12) {
                RuleRow(title: "Rondleiding",
                        hint: "De vijf schermen die je bij de eerste start zag.") {
                    OutlineButton(title: "Opnieuw bekijken") {
                        onClose()
                        openTour()
                    }
                }
                RuleRow(title: "Tips in de app",
                        hint: tipsReset
                            ? "Staan klaar. Ze verschijnen weer zodra je de app opnieuw opent."
                            : "De kleine uitleg die één keer bij een knop verschijnt.") {
                    OutlineButton(title: tipsReset ? "Staat klaar" : "Opnieuw tonen") {
                        AppTips.requestReset()
                        tipsReset = true
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Over

    private var aboutSection: some View {
        section("Over") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Versie", AppInfo.version)
                infoRow("Identifier", AppInfo.bundleID)
                infoRow("Apple Intelligence",
                        GameAssistant().readiness.explanation ?? "Beschikbaar")
                Text("Archivo is van Omnibus-Type en valt onder de SIL Open Font License 1.1.")
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Credits")
            Text("Ontwikkeld door")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
            Link(destination: URL(string: "https://www.wave2lead.com")!) {
                VStack(alignment: .leading, spacing: 6) {
                    Image("Wave2Lead")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 26)
                        .accessibilityLabel("Softwarestudio Wave2Lead")
                    Text("wave2lead.com")
                        .font(M.font(11.5, .semiBold))
                        .foregroundStyle(M.red)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
        .background(M.paperDeep)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(M.font(12.5, .semiBold))
                .foregroundStyle(M.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Vorm

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        note: String? = nil,
                                        tint: Color = M.inkAlpha(0.5),
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title, tint: tint)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: note == nil ? 10 : 6, trailing: 20))
            if let note {
                Text(note)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
            }
            Hairline()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { HeavyRule() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
    }

    private func restore(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let outcome = try Backup.restore(from: url, into: context)
            store.didRestoreBackup()
            message = outcome.summary
            isError = false
            backupURL = try? Backup.write(from: context)
        } catch {
            message = "Terugzetten lukte niet: \(error.localizedDescription)"
            isError = true
        }
    }
}
