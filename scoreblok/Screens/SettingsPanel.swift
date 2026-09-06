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
    @State private var importing = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ModalPanel(title: "Instellingen",
                   width: isCompact ? 340 : 620,
                   onClose: onClose) {
            ScrollView {
                VStack(spacing: 0) {
                    meSection
                    playSection
                    statsSection
                    storageSection
                    searchSection
                    aboutSection
                    creditsSection
                }
            }
            .frame(maxHeight: 620)
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

    // MARK: - Opslag

    private var storageSection: some View {
        section(Storage.mode.title,
                tint: Storage.mode.isFailed ? M.red : M.inkAlpha(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Storage.mode.detail)
                    .font(M.font(14, .semiBold))
                    .foregroundStyle(Storage.mode.isFailed ? M.red : M.ink)
                    .fixedSize(horizontal: false, vertical: true)
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
            Text("Ontwikkeld door Softwarestudio Wave2Lead")
                .font(M.font(13, .semiBold))
                .foregroundStyle(M.ink)
            Link(destination: URL(string: "https://www.wave2lead.com")!) {
                Text("wave2lead.com")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.red)
            }
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
            message = outcome.summary
            isError = false
            backupURL = try? Backup.write(from: context)
        } catch {
            message = "Terugzetten lukte niet: \(error.localizedDescription)"
            isError = true
        }
    }
}
