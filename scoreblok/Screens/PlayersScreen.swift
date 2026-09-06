import SwiftUI
import SwiftData

struct PlayersScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query private var matches: [Match]

    @State private var addingPlayer = false
    @State private var newName = ""
    @State private var newAvatar = 0
    @State private var newRamp = 0
    @Environment(\.isNarrow) private var isNarrow

    private var counted: [Match] { matches.filter(\.counts) }
    private var visible: [Player] { players.filter { !$0.isArchived } }
    private var archived: [Player] { players.filter(\.isArchived) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()

                if visible.isEmpty {
                    empty
                } else {
                    Hairline()
                    GridRows(items: visible, columns: isNarrow ? 2 : 3) { player in
                        card(player)
                    }
                }

                if !archived.isEmpty {
                    SectionLabel("Gearchiveerd")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 22, leading: 28, bottom: 8, trailing: 28))
                    Hairline()
                    ForEach(archived) { player in
                        RowButton(minHeight: 56) {
                            router.screen = .detail(player)
                        } content: {
                            HStack(spacing: 13) {
                                PlayerMark(player: player, size: 28)
                                Text(player.name)
                                    .font(M.font(14.5, .semiBold))
                                    .foregroundStyle(M.inkAlpha(0.6))
                                Spacer(minLength: 0)
                                Text("uit de keuzelijsten")
                                    .font(M.font(11.5, .regular))
                                    .foregroundStyle(M.inkAlpha(0.45))
                            }
                            .padding(.horizontal, 28)
                        }
                        Hairline()
                    }
                }

                Text("Verwijderen bestaat niet. Archiveren wel: de speler verdwijnt uit keuzelijsten en blijft in de historie staan.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(5)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
            }
        }
        .overlay { if addingPlayer { newPlayerPanel } }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            ScreenTitle("Spelers")
            Spacer()
            SolidButton(title: "Nieuw profiel") { beginNewPlayer() }
        }
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nog geen spelers. Voeg je vaste medespelers toe, dan staat een potje in twee tikken klaar.")
                .font(M.font(13, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .frame(maxWidth: 560, alignment: .leading)
            SolidButton(title: "Nieuw profiel") { beginNewPlayer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
    }

    private func card(_ player: Player) -> some View {
        let results = StatsEngine.results(for: player, in: counted)
        let wins = results.filter(\.isWin).count
        let streak = StatsEngine.streak(for: player, in: counted)

        return RowButton(minHeight: 172) {
            router.screen = .detail(player)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    PlayerMark(player: player, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(player.name)
                            .font(M.font(18, .extraBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        Text(player.isMe ? "DAT BEN JIJ" : "MEDESPELER")
                            .font(M.font(9.5, .semiBold))
                            .tracking(em: 0.12, size: 9.5)
                            .foregroundStyle(M.inkAlpha(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 16)

                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 22) {
                    metric("\(results.count)", "potjes")
                    metric(results.isEmpty ? "—"
                           : (Double(wins) / Double(results.count)).percentText, "winst")
                    metric(streak.short, "reeks")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(M.font(22, .extraBold))
                .foregroundStyle(M.ink)
            Text(label)
                .font(M.font(11, .regular))
                .foregroundStyle(M.inkAlpha(0.5))
        }
    }

    private func beginNewPlayer() {
        newName = ""
        newAvatar = Int.random(in: 0..<AvatarShape.count)
        newRamp = players.count % M.playerRamp.count
        addingPlayer = true
    }

    private var newPlayerPanel: some View {
        ModalPanel(title: "Nieuw profiel", onClose: { addingPlayer = false }) {
            VStack(alignment: .leading, spacing: 16) {
                AvatarPicker(avatarIndex: $newAvatar, rampIndex: $newRamp)
                HardTextField(placeholder: "Naam", text: $newName)
                HStack(spacing: 10) {
                    Spacer()
                    OutlineButton(title: "Annuleer") { addingPlayer = false }
                    SolidButton(title: "Toevoegen",
                                enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        context.insert(Player(name: name,
                                              rampIndex: newRamp,
                                              avatarIndex: newAvatar,
                                              isMe: players.isEmpty))
                        addingPlayer = false
                    }
                }
            }
            .padding(20)
        }
    }
}
