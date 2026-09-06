import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Wat er met je blok gebeurt, in gewone taal: waar het staat, hoeveel erin
/// zit, en de twee knoppen die ertoe doen — een kopie maken en er een
/// terugzetten.
struct StoragePanel: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var matches: [Match]
    @Query private var players: [Player]
    @Query private var templates: [GameTemplate]

    @State private var backupURL: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ModalPanel(title: "Opslag", width: 520, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                statusRow
                Hairline()
                countsRow
                Hairline()
                actions
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            restore(result)
        }
        .task { backupURL = try? Backup.write(from: context) }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(Storage.mode.title,
                         tint: Storage.mode.isFailed ? M.red : M.inkAlpha(0.5))
            Text(Storage.mode.detail)
                .font(M.font(14, .semiBold))
                .foregroundStyle(Storage.mode.isFailed ? M.red : M.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(footnote)
                .font(M.font(12, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Storage.mode.isFailed ? M.redWash : M.paperDeep)
    }

    private var footnote: String {
        var parts = ["Bestand \(Storage.storeDescription)"]
        if let saved = Storage.lastSaved {
            parts.append("laatst bewaard \(saved.formatted(.dateTime.hour().minute()))")
        }
        if Storage.mode.isCloud {
            parts.append("iCloud werkt op de achtergrond bij")
        }
        return parts.joined(separator: " · ")
    }

    private var countsRow: some View {
        HStack(spacing: 0) {
            count("\(matches.count)", matches.count == 1 ? "potje" : "potjes")
            count("\(players.count)", players.count == 1 ? "speler" : "spelers")
            count("\(templates.count)", "spellen")
            count("\(matches.reduce(0) { $0 + $1.rounds.count })", "rondes")
        }
    }

    private func count(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(M.font(24, .extraBold))
                .foregroundStyle(M.ink)
            Text(label)
                .font(M.font(11, .regular))
                .foregroundStyle(M.inkAlpha(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Een reservekopie is één bestand met alle spelers, spellen en potjes. Terugzetten voegt toe en werkt bij; er wordt nooit iets gewist.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(isError ? M.red : M.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Text("Bewaar reservekopie")
                            .font(M.font(13, .extraBold))
                            .foregroundStyle(M.paper)
                            .padding(.horizontal, 18)
                            .frame(minHeight: M.tap)
                            .background(M.red)
                    }
                    .buttonStyle(.plain)
                }
                OutlineButton(title: "Zet kopie terug") { importing = true }
                Spacer()
                OutlineButton(title: "Klaar") { onClose() }
            }
        }
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
