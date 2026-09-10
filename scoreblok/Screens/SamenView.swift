import SwiftData
import SwiftUI
import Vision
import VisionKit

/// Samen bijwerken aan dezelfde tafel. De een laat een QR-code zien, de ander
/// scant hem; beide kiezen wie er van hun kant meedoet, bevestigen wie wie is,
/// en voegen samen.
struct SamenView: View {
    let request: SamenRequest
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query(sort: \PlayGroup.createdAt) private var groups: [PlayGroup]
    @Query private var matches: [Match]

    @State private var model: SamenModel?
    @State private var scanning = false

    private var activePlayers: [Player] { players.filter { !$0.isArchived } }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            ZStack {
                M.ink.opacity(0.35).ignoresSafeArea()
                panel(wide: wide)
                    .frame(maxWidth: wide ? 760 : .infinity,
                           maxHeight: wide ? min(proxy.size.height - 40, 860) : .infinity)
                    .padding(wide ? 20 : 0)
            }
        }
        .task { if model == nil { start(role: request.invite == nil ? .host : .guest, invite: request.invite) } }
        .onDisappear { model?.stop() }
        .onChange(of: model?.receivedCount ?? 0) { _, count in
            if count > 0 { prepareReview() }
        }
        .sheet(isPresented: $scanning) { scannerSheet }
    }

    // MARK: - Paneel

    private func panel(wide: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Samen bijwerken")
                    .font(M.font(17, .extraBold))
                    .foregroundStyle(M.ink)
                Spacer()
                Button(action: close) {
                    Text("✕")
                        .font(M.font(15, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .frame(width: M.tap, height: M.tap)
                }
                .buttonStyle(.plain)
                .help("Sluiten")
                .accessibilityLabel("Sluiten")
            }
            .padding(.leading, 20)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            HeavyRule()

            if let model {
                ScrollView {
                    content(model, wide: wide)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HeavyRule()
                footer(model)
            } else {
                Spacer()
            }
        }
        .background(M.paper)
        .overlay(Rectangle().stroke(M.ink, lineWidth: wide ? 2 : 0))
    }

    @ViewBuilder
    private func content(_ model: SamenModel, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            connectionBlock(model, wide: wide)
            HeavyRule()
            switch model.step {
            case .review, .merging:
                reviewBlock(model)
            case .done(let outcome):
                doneBlock(model, outcome: outcome)
            default:
                membersBlock(model)
            }
        }
    }

    // MARK: - Verbinden

    private func connectionBlock(_ model: SamenModel, wide: Bool) -> some View {
        let showsCode = model.role == .host && model.peerName == nil
        return AnyLayout(wide && showsCode
                         ? AnyLayout(HStackLayout(alignment: .center, spacing: 26))
                         : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))) {
            if showsCode, let image = model.qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: wide ? 220 : 200, height: wide ? 220 : 200)
                    .padding(12)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                    .accessibilityLabel("QR-code om samen bij te werken")
                    .frame(maxWidth: wide ? nil : .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(kicker(model))
                    .font(M.font(10, .semiBold))
                    .tracking(em: 0.14, size: 10)
                    .foregroundStyle(M.red)
                HStack(spacing: 10) {
                    if model.peerName != nil, !isFailed(model) {
                        Rectangle().fill(M.red).frame(width: 10, height: 10)
                    } else if !isFailed(model), !isDone(model) {
                        ProgressView().tint(M.ink)
                    }
                    Text(title(model))
                        .font(M.font(20, .extraBold))
                        .foregroundStyle(isFailed(model) ? M.red : M.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail(model))
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.inkAlpha(0.65))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if isFailed(model) {
                    OutlineButton(title: "Opnieuw proberen") {
                        start(role: model.role, invite: model.role == .guest ? model.invite : nil)
                    }
                    .padding(.top, 4)
                }
                if showsCode {
                    OutlineButton(title: "Zelf een code scannen") { scanning = true }
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    /// "1 potje", "3 potjes".
    private func aantal(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    private func isFailed(_ model: SamenModel) -> Bool {
        if case .failed = model.step { return true }
        return false
    }

    private func isDone(_ model: SamenModel) -> Bool {
        if case .done = model.step { return true }
        return false
    }

    private func kicker(_ model: SamenModel) -> String {
        switch model.step {
        case .connecting: "STAP 1 · KOPPELEN"
        case .connected, .waitingForOther: "STAP 2 · WIE DOET MEE"
        case .review, .merging: "STAP 3 · WIE IS WIE"
        case .done: "KLAAR"
        case .failed: "NIET GELUKT"
        }
    }

    private func title(_ model: SamenModel) -> String {
        let peer = model.peerName ?? "de ander"
        switch model.step {
        case .connecting:
            return model.role == .host ? "Laat de ander deze code scannen" : "Verbinden met \(model.invite.hostName)…"
        case .connected:
            return "Verbonden met \(peer)"
        case .waitingForOther:
            return "Verstuurd"
        case .review:
            return "Wie is wie?"
        case .merging:
            return "Samenvoegen…"
        case .done:
            return "Klaar"
        case .failed:
            return "Het lukte niet"
        }
    }

    private func detail(_ model: SamenModel) -> String {
        let peer = model.peerName ?? "de ander"
        switch model.step {
        case .connecting:
            return model.role == .host
                ? "Met Scoreblok of met de camera van de andere iPhone of iPad. Jullie moeten bij elkaar in de buurt zijn; er gaat niets via internet."
                : "Houd de apparaten bij elkaar in de buurt."
        case .connected:
            if model.received != nil {
                return "\(peer) is al klaar. Kies wie er van jouw kant meedoet en tik op Verder."
            }
            return "Zoals vroeger met de linkkabel, maar dan zonder kabel. Kies wie er van jouw kant meedoet en tik op Verder."
        case .waitingForOther:
            return "Wachten tot \(peer) op Verder tikt."
        case .review, .merging:
            guard let payload = model.received else { return "" }
            let preview = SamenExchange.preview(payload, choices: model.choices, context: context)
            return "\(aantal(payload.matches.count, "potje", "potjes")) van \(peer): \(preview.newMatches) nieuw · \(preview.updatedMatches) bijgewerkt · \(aantal(preview.newPlayers, "nieuwe speler", "nieuwe spelers")). Controleer wie wie is en voeg samen."
        case .done(let outcome):
            return "\(aantal(outcome.newMatches, "potje", "potjes")) toegevoegd, \(outcome.updatedMatches) bijgewerkt en \(aantal(outcome.newPlayers, "speler", "spelers")) erbij. Vooraf is er een reservekopie gemaakt."
        case .failed(let message):
            return message
        }
    }

    // MARK: - Wie doet mee

    private func membersBlock(_ model: SamenModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.role == .host, model.peerName == nil, !groups.isEmpty {
                groupPicker(model)
                Hairline()
            }
            SectionLabel("Van jouw kant doen mee")
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 6, trailing: 20))
            Text("Alleen afgeronde potjes waarin uitsluitend deze spelers zaten, gaan mee. Nu \(aantal(sharedCount(model), "potje", "potjes")).")
                .font(M.font(12, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            ForEach(activePlayers) { player in
                Hairline()
                let isOn = model.members.contains(player.id)
                RowButton(isActive: isOn, minHeight: 52) {
                    guard !model.sent else { return }
                    if isOn { model.members.remove(player.id) } else { model.members.insert(player.id) }
                } content: {
                    HStack(spacing: 12) {
                        HardCheckbox(isOn: isOn)
                        PlayerMark(player: player, size: 28)
                        Text(player.isMe ? "\(player.name) · jij" : player.name)
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }
                .disabled(model.sent)
            }
            Hairline()
        }
    }

    private func sharedCount(_ model: SamenModel) -> Int {
        matches.filter { SamenExchange.isShared($0, members: model.members) }.count
    }

    private func groupPicker(_ model: SamenModel) -> some View {
        Menu {
            Button("Nieuwe speelgroep") {
                model.changeGroup(to: UUID())
                model.members = SamenExchange.defaultMembers(group: nil, players: players)
            }
            ForEach(groups) { group in
                Button(group.name) {
                    model.changeGroup(to: group.id)
                    model.members = SamenExchange.defaultMembers(group: group, players: players)
                }
            }
        } label: {
            HStack {
                Text("Speelgroep")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                Spacer(minLength: 8)
                Text("\(groups.first { $0.id == model.invite.groupID }?.name ?? "Nieuwe speelgroep") ▾")
                    .font(M.font(12.5, .extraBold))
                    .foregroundStyle(M.ink)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(M.surface)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Wie is wie

    private func reviewBlock(_ model: SamenModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Spelers van \(model.peerName ?? "de ander")")
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            if let payload = model.received {
                ForEach(payload.members, id: \.id) { member in
                    Hairline()
                    HStack(spacing: 12) {
                        AvatarSwatch(avatarIndex: member.avatarIndex, rampIndex: member.rampIndex, size: 28)
                        Text(member.name)
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("is")
                            .font(M.font(12, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                        Menu {
                            Button("Nieuw profiel: \(member.name)") { model.choices[member.id] = .new }
                            ForEach(activePlayers) { player in
                                Button(player.name) { model.choices[member.id] = .existing(player.id) }
                            }
                        } label: {
                            Text("\(choiceLabel(model.choices[member.id])) ▾")
                                .font(M.font(13, .extraBold))
                                .foregroundStyle(M.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(M.surface)
                                .overlay(Rectangle().stroke(M.ink, lineWidth: 1.5))
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(model.step == .merging)
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 58)
                }
                Hairline()
                if SamenExchange.hasConflict(model.choices) {
                    Text("Twee spelers wijzen naar dezelfde persoon. Kies voor één van beide een ander profiel.")
                        .font(M.font(12.5, .semiBold))
                        .foregroundStyle(M.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Naam van de speelgroep")
                    HardTextField(placeholder: "Bijvoorbeeld Utrecht", text: Bindable(model).groupName)
                }
                .padding(20)
            }
        }
    }

    private func choiceLabel(_ choice: SamenExchange.Choice?) -> String {
        switch choice {
        case .existing(let id): players.first { $0.id == id }?.name ?? "Onbekend"
        case .new, nil: "Nieuw profiel"
        }
    }

    // MARK: - Klaar

    private func doneBlock(_ model: SamenModel, outcome: SamenExchange.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In Statistieken kies je bij Speelgroep voor \(model.groupName) om alleen jullie potjes samen te zien.")
                .font(M.font(14, .semiBold))
                .foregroundStyle(M.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Volgende keer herkennen jullie apparaten elkaar: scan de code opnieuw en alleen wat nieuw is komt erbij.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: - Voet

    private func footer(_ model: SamenModel) -> some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            switch model.step {
            case .review, .merging:
                SolidButton(title: model.step == .merging ? "Bezig…" : "Samenvoegen",
                            enabled: model.step == .review && !SamenExchange.hasConflict(model.choices)
                                && !model.groupName.trimmingCharacters(in: .whitespaces).isEmpty) {
                    merge()
                }
            case .done, .failed:
                SolidButton(title: "Sluiten") { close() }
            default:
                SolidButton(title: model.sent ? "Verstuurd" : "Verder",
                            enabled: !model.sent && !model.members.isEmpty) {
                    proceed()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Acties

    private func start(role: SamenModel.Role, invite incoming: SamenInvite?) {
        model?.stop()
        let me = players.first(where: \.isMe)
        let deviceName = "\(me?.name ?? "Scoreblok") · \(UIDevice.current.model)"
        let recent = groups.max { ($0.lastSyncAt ?? .distantPast) < ($1.lastSyncAt ?? .distantPast) }
        let invite = incoming ?? SamenInvite(token: SamenInvite.newToken(),
                                             groupID: recent?.id ?? UUID(),
                                             hostName: deviceName)
        let created = SamenModel(role: role, invite: invite, deviceName: deviceName)
        created.members = SamenExchange.defaultMembers(group: groups.first { $0.id == invite.groupID },
                                                       players: players)
        created.start()
        model = created
    }

    private func proceed() {
        guard let model else { return }
        do {
            let group = groups.first { $0.id == model.invite.groupID }
            let payload = try SamenExchange.payload(context: context, groupID: model.invite.groupID,
                                                    group: group, members: model.members,
                                                    senderName: model.deviceName)
            model.proceed(with: payload)
        } catch {
            model.fail("Klaarzetten lukte niet: \(error.localizedDescription)")
        }
    }

    private func prepareReview() {
        guard let model, let payload = model.received else { return }
        let group = groups.first { $0.id == model.invite.groupID }
        model.choices = SamenExchange.suggestions(for: payload, group: group, players: players)
        if model.groupName.isEmpty { model.groupName = group?.name ?? payload.senderName }
    }

    private func merge() {
        guard let model, let payload = model.received else { return }
        model.beginMerge()
        do {
            let outcome = try SamenExchange.apply(
                payload, choices: model.choices, localMembers: model.members,
                groupID: model.invite.groupID,
                groupName: model.groupName.trimmingCharacters(in: .whitespaces),
                context: context)
            model.finish(outcome)
        } catch {
            model.fail("Samenvoegen lukte niet: \(error.localizedDescription) Er is niets gewist.")
        }
    }

    private func close() {
        model?.stop()
        onClose()
    }

    // MARK: - Scannen

    @ViewBuilder
    private var scannerSheet: some View {
        if QRScanner.isAvailable {
            QRScanner { code in
                scanning = false
                if let url = URL(string: code), let invite = SamenInvite(url: url) {
                    start(role: .guest, invite: invite)
                }
            }
            .ignoresSafeArea()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scannen in de app kan hier niet")
                    .font(M.font(18, .extraBold))
                    .foregroundStyle(M.ink)
                Text("Open de Camera-app en richt die op de code van de ander. Scoreblok opent dan vanzelf.")
                    .font(M.font(14, .regular))
                    .foregroundStyle(M.inkAlpha(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                OutlineButton(title: "Sluiten") { scanning = false }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(M.paper)
        }
    }
}

/// De camera van VisionKit, alleen voor QR-codes.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                   isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var handled = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
                   value.hasPrefix("scoreblok://samen") {
                    handled = true
                    onCode(value)
                    return
                }
            }
        }
    }
}

