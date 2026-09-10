import SwiftUI

/// De keuze bij de eerste start: waar staan je potjes. Eén van de twee,
/// nooit allebei.
struct StorageChoiceView: View {
    let store: StoreController

    @State private var selection: StorageChoice?
    @State private var cloud = CloudStatus.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            VStack(spacing: 0) {
                HStack {
                    Wordmark(size: 15, markSize: 24)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                HeavyRule()

                ScrollView {
                    content(wide: wide)
                        .frame(maxWidth: 820, alignment: .leading)
                        .padding(.horizontal, wide ? 40 : 20)
                        .padding(.vertical, wide ? 36 : 24)
                        .frame(maxWidth: .infinity)
                }

                HeavyRule()
                footer
            }
            .background(M.paper)
        }
        .onAppear { cloud.refresh() }
        // Wie tussendoor in de Instellingen-app inlogt, ziet iCloud meteen
        // beschikbaar worden.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cloud.refresh() }
        }
    }

    private func content(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPSLAG")
                .font(M.font(10, .semiBold))
                .tracking(em: 0.14, size: 10)
                .foregroundStyle(M.red)
                .padding(.bottom, 14)

            Text("Waar bewaar je\njouw potjes?")
                .font(M.font(wide ? 36 : 28, .extraBold))
                .tracking(em: -0.025, size: wide ? 36 : 28)
                .foregroundStyle(M.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Text("Kies één plek. De app gebruikt nooit allebei tegelijk, zodat je altijd weet waar je potjes staan.")
                .font(M.font(15, .regular))
                .foregroundStyle(M.inkAlpha(0.72))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, store.hasExistingData ? 16 : 24)

            if store.hasExistingData {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(M.red).frame(width: 3)
                    Text("Er staan al potjes op dit apparaat. Die gaan mee naar wat je kiest; er wordt niets gewist.")
                        .font(M.font(13.5, .semiBold))
                        .foregroundStyle(M.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            }

            AnyLayout(wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                           : AnyLayout(VStackLayout(spacing: 12))) {
                option(.local)
                option(.iCloud)
            }

            if !cloud.account.isAvailable {
                AnyLayout(wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                               : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))) {
                    Text(cloudHint)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    if wide { Spacer(minLength: 8) }
                    OutlineButton(title: "Opnieuw controleren") { cloud.refresh() }
                }
                .padding(.top, 14)
            }

            Text("Je kunt later overstappen in Instellingen. Je potjes gaan dan mee, en vooraf maakt de app een reservekopie.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
        }
    }

    private var cloudHint: String {
        switch cloud.account {
        case .unknown:
            "iCloud wordt gecontroleerd…"
        case .noAccount:
            "Voor iCloud moet dit apparaat ingelogd zijn bij iCloud. Log in via de Instellingen-app en kom terug."
        case .restricted:
            "iCloud is op dit apparaat geblokkeerd, bijvoorbeeld door Schermtijd of een beheerprofiel."
        default:
            cloud.account.summary
        }
    }

    private func option(_ choice: StorageChoice) -> some View {
        let isOn = selection == choice
        let available = choice == .local || cloud.account.isAvailable

        return Button {
            guard available else { return }
            withAnimation(M.Motion.quick) { selection = choice }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    HardCheckbox(isOn: isOn)
                    Text(choice.title)
                        .font(M.font(20, .extraBold))
                        .tracking(em: -0.015, size: 20)
                        .foregroundStyle(available ? M.ink : M.inkAlpha(0.4))
                    Spacer(minLength: 0)
                    if choice == .iCloud {
                        Text(available ? "INGELOGD" : "NIET BESCHIKBAAR")
                            .font(M.font(9.5, .extraBold))
                            .tracking(em: 0.1, size: 9.5)
                            .foregroundStyle(available ? M.inkAlpha(0.6) : M.red)
                    }
                }
                .padding(.bottom, 12)

                Text(choice.pitch)
                    .font(M.font(14.5, .semiBold))
                    .foregroundStyle(available ? M.ink : M.inkAlpha(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(choice.points.enumerated()), id: \.offset) { spot, point in
                        if spot > 0 { Hairline() }
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(available ? M.red : M.inkAlpha(0.3))
                                .frame(width: 7, height: 2)
                                .padding(.top, 8)
                            Text(point)
                                .font(M.font(12.5, .regular))
                                .foregroundStyle(available ? M.inkAlpha(0.78) : M.inkAlpha(0.4))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isOn ? M.redTint : Color.clear)
            .overlay(Rectangle().stroke(isOn ? M.red : M.ruleHeavy, lineWidth: isOn ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(available ? "" : cloudHint)
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            SolidButton(title: selection.map { "Doorgaan met \($0.title)" } ?? "Kies waar je potjes staan",
                        enabled: canContinue) {
                guard let selection else { return }
                Task { await store.choose(selection) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var canContinue: Bool {
        guard let selection else { return false }
        return selection == .local || cloud.account.isAvailable
    }
}

extension StorageChoice {
    var pitch: String {
        switch self {
        case .local: "Alles blijft op dit apparaat."
        case .iCloud: "Je potjes op al je apparaten met hetzelfde iCloud-account."
        }
    }

    var points: [String] {
        switch self {
        case .local:
            ["Niets verlaat dit apparaat",
             "Werkt zonder account",
             "Maak zelf af en toe een reservekopie"]
        case .iCloud:
            ["Werkt ook zonder verbinding; bijwerken zodra je online bent",
             "Een nieuw apparaat krijgt alles vanzelf",
             "Gebruikt het iCloud-account van dit apparaat"]
        }
    }
}

/// Terwijl de potjes van de ene naar de andere kant gaan.
struct StorageWorkingView: View {
    let step: String

    var body: some View {
        VStack(spacing: 18) {
            Wordmark(size: 18, markSize: 26)
                .padding(.bottom, 8)
            ProgressView()
                .tint(M.ink)
            Text(step)
                .font(M.font(16, .extraBold))
                .foregroundStyle(M.ink)
                .multilineTextAlignment(.center)
            Text("Sluit de app niet. Er wordt niets opgeruimd voordat alles veilig aan de andere kant staat.")
                .font(M.font(13, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(M.paper)
        .accessibilityElement(children: .combine)
    }
}

/// Uitkomst van een keuze of overstap, bovenin het scherm.
struct StorageNoticeBanner: View {
    let notice: StoreController.Notice
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(notice.text)
                .font(M.font(13.5, .semiBold))
                .foregroundStyle(M.paper)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Text("OK")
                    .font(M.font(12.5, .extraBold))
                    .foregroundStyle(M.paper)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .overlay(Rectangle().stroke(M.paper.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(notice.isError ? M.red : M.ink)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Een foutmelding blijft staan tot je hem wegtikt.
        .task(id: notice.id) {
            guard !notice.isError else { return }
            try? await Task.sleep(for: .seconds(8))
            onClose()
        }
    }
}
