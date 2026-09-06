import SwiftUI
import WidgetKit

struct StandingsWidgetView: View {
    let snapshot: WidgetSnapshot?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    /// StandBy: liggend op de lader, op anderhalve meter. De enige maat waar
    /// het rood als vlak loopt en de schaal ruim boven de rest uitkomt.
    private var isStandBy: Bool {
        family == .systemMedium && !showsBackground
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemSmall: small
            case .systemMedium: isStandBy ? AnyView(standBy) : AnyView(medium)
            default: large
            }
        }
        .widgetURL(snapshot?.destination)
        .containerBackground(for: .widget) {
            if isStandBy { Color(hex: 0x0D0C0C) } else { M.paper }
        }
    }

    // MARK: - Klein · wie leidt

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let open = snapshot?.open, let leader = open.leader {
                smallLive(open, leader: leader)
            } else {
                smallRanking
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func smallLive(_ open: WidgetSnapshot.OpenMatch,
                           leader: WidgetSnapshot.Entry) -> some View {
        // Op 170 px past "van 9" er niet meer bij zonder af te kappen.
        Kicker("\(open.gameName) · \(open.shortPosition)".uppercased())
        Spacer(minLength: 0)
        Text("\(leader.total)")
            .font(M.font(42, .extraBold))
            .tracking(em: -0.04, size: 42)
            .foregroundStyle(M.red)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        Text("\(leader.name) leidt")
            .font(M.font(15, .extraBold))
            .tracking(em: -0.01, size: 15)
            .foregroundStyle(M.ink)
            .lineLimit(1)
            .padding(.top, 8)
        Spacer(minLength: 0)
        Footnote(gapText(open))
    }

    @ViewBuilder
    private var smallRanking: some View {
        let rows: [WidgetSnapshot.RankEntry] = Array((snapshot?.ranking ?? []).prefix(4))
        Kicker("Ranglijst · \(snapshot?.period ?? "90 dagen")".uppercased())
        Spacer(minLength: 0)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(M.font(12, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.winRate.percentText)
                        .font(M.font(14, .extraBold))
                        .foregroundStyle(index == 0 ? M.red : M.ink)
                }
                .padding(.top, 6)
                .frame(minHeight: 23, alignment: .top)
                .overlay(alignment: .top) { Rule(1) }
            }
        }
        Spacer(minLength: 0)
        Footnote("Tik om een potje te starten")
    }

    private func gapText(_ open: WidgetSnapshot.OpenMatch) -> String {
        guard open.standings.count > 1 else { return open.rule }
        return "\(open.gap) \(open.unitLabel) voor op \(open.standings[1].name)"
    }

    // MARK: - Middel · de stand

    private var medium: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(snapshot?.open?.gameName ?? "Ranglijst")
                    .font(M.font(16, .extraBold))
                    .tracking(em: -0.01, size: 16)
                    .foregroundStyle(M.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Kicker(mediumKicker)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 10, trailing: 16))
            Rule(2)

            HStack(spacing: 0) {
                ForEach(Array(mediumColumns.enumerated()), id: \.offset) { index, column in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Color(hex: M.playerRamp[column.ramp % M.playerRamp.count].bg))
                                .frame(width: 5, height: 5)
                            Text(column.name)
                                .font(M.font(11, .semiBold))
                                .foregroundStyle(M.ink)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(column.value)
                            .font(M.font(30, .extraBold))
                            .tracking(em: -0.035, size: 30)
                            .foregroundStyle(index == 0 ? M.red : M.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(column.sub)
                            .font(M.font(9.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.6))
                            .padding(.top, 6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 11, leading: 12, bottom: 12, trailing: 12))
                    .background(index == 0 ? M.paperDeep : .clear)
                    .overlay(alignment: .trailing) { Rule(1, vertical: true) }
                }
            }

            Rule(1)
            HStack {
                Footnote(mediumFoot)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 9, trailing: 16))
        }
    }

    private struct Column {
        var name: String
        var value: String
        var sub: String
        var ramp: Int
    }

    private var mediumColumns: [Column] {
        if let open = snapshot?.open {
            return open.standings.prefix(4).enumerated().map { index, entry in
                Column(name: entry.name, value: "\(entry.total)",
                       sub: index == 0 ? "leidt" : "+\(entry.gap)", ramp: entry.rampIndex)
            }
        }
        let rows: [WidgetSnapshot.RankEntry] = Array((snapshot?.ranking ?? []).prefix(4))
        return rows.enumerated().map { index, row in
            Column(name: row.name, value: row.winRate.percentText,
                   sub: index == 0 ? "bovenaan" : "winst%", ramp: row.rampIndex)
        }
    }

    private var mediumKicker: String {
        if let open = snapshot?.open { return open.position.uppercased() }
        return "\(snapshot?.period ?? "90 dagen") · \(snapshot?.totalMatches ?? 0) potjes".uppercased()
    }

    private var mediumFoot: String {
        if let open = snapshot?.open {
            return "\(open.rule) · begonnen \(open.startedAt.formatted(.dateTime.hour().minute()))"
        }
        return "Tik om een potje te starten"
    }

    // MARK: - Groot · stand en verloop

    private var large: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Kicker(snapshot?.open == nil ? "GEEN POTJE OPEN" : "POTJE OPEN")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(snapshot?.open?.gameName ?? "Ranglijst")
                        .font(M.font(23, .extraBold))
                        .tracking(em: -0.02, size: 23)
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(snapshot?.open?.position ?? (snapshot?.period ?? "90 dagen"))
                        .font(M.font(11, .regular))
                        .foregroundStyle(M.inkAlpha(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 13, leading: 18, bottom: 11, trailing: 18))
            Rule(2)

            ForEach(Array(largeRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 11) {
                    Text("\(index + 1)")
                        .font(M.font(11, .extraBold))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .frame(width: 12, alignment: .leading)
                    AvatarShape(index: row.avatar)
                        .fill(Color(hex: M.playerRamp[row.ramp % M.playerRamp.count].ink))
                        .frame(width: 26, height: 26)
                        .background(Color(hex: M.playerRamp[row.ramp % M.playerRamp.count].bg))
                    Text(row.name)
                        .font(M.font(14, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.sub)
                        .font(M.font(10.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.6))
                    Text(row.value)
                        .font(M.font(20, .extraBold))
                        .tracking(em: -0.02, size: 20)
                        .foregroundStyle(M.ink)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(index == 0 ? M.paperDeep : .clear)
                .overlay(alignment: .bottom) { Rule(1) }
            }

            if let open = snapshot?.open, !open.playedRounds.isEmpty {
                Kicker("GESPEELDE RONDES")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 9, leading: 18, bottom: 7, trailing: 18))
                Rule(1)
                ForEach(open.playedRounds) { round in
                    HStack(spacing: 0) {
                        Text(round.label)
                            .font(M.font(11, .regular))
                            .foregroundStyle(M.inkAlpha(0.6))
                            .frame(width: 40)
                            .padding(.vertical, 7)
                            .overlay(alignment: .trailing) { Rule(1, vertical: true) }
                        ForEach(Array(round.cells.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(M.font(12.5, .semiBold))
                                .foregroundStyle(M.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .overlay(alignment: .trailing) { Rule(1, vertical: true) }
                        }
                    }
                    .overlay(alignment: .top) { Rule(1) }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private struct Row {
        var name: String
        var value: String
        var sub: String
        var ramp: Int
        var avatar: Int
    }

    private var largeRows: [Row] {
        if let open = snapshot?.open {
            return open.standings.prefix(5).enumerated().map { index, entry in
                Row(name: entry.name, value: "\(entry.total)",
                    sub: index == 0 ? "leidt" : "+\(entry.gap)",
                    ramp: entry.rampIndex, avatar: entry.avatarIndex)
            }
        }
        let rows: [WidgetSnapshot.RankEntry] = Array((snapshot?.ranking ?? []).prefix(5))
        return rows.map { row in
            Row(name: row.name, value: row.winRate.percentText,
                sub: "\(row.played) potjes", ramp: row.rampIndex, avatar: row.avatarIndex)
        }
    }

    // MARK: - StandBy · de tafelweergave

    private var standBy: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(standByKicker)
                    .font(M.font(9, .semiBold))
                    .tracking(em: 0.12, size: 9)
                    .foregroundStyle(M.paper)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(standByBig)
                    .font(M.font(52, .extraBold))
                    .tracking(em: -0.04, size: 52)
                    .foregroundStyle(M.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(standByName)
                    .font(M.font(15, .extraBold))
                    .foregroundStyle(M.paper)
                    .padding(.top, 8)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .padding(16)
            .background(M.red)

            VStack(alignment: .leading, spacing: 0) {
                Text(standBySub)
                    .font(M.font(9, .semiBold))
                    .tracking(em: 0.12, size: 9)
                    .foregroundStyle(Color(hex: 0xC8C4C4))
                    .padding(.bottom, 12)
                ForEach(Array(standByRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        Text(row.0)
                            .font(M.font(13, .semiBold))
                            .foregroundStyle(M.paper)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(row.1)
                            .font(M.font(17, .extraBold))
                            .foregroundStyle(M.paper)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(hex: 0x2D2B2B)).frame(height: 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        }
    }

    private var standByKicker: String {
        if let open = snapshot?.open {
            return "\(open.gameName) · \(open.position)".uppercased()
        }
        return "RANGLIJST · \(snapshot?.period ?? "90 dagen")".uppercased()
    }

    private var standByBig: String {
        if let leader = snapshot?.open?.leader { return "\(leader.total)" }
        return snapshot?.ranking.first?.winRate.percentText ?? "—"
    }

    private var standByName: String {
        if let leader = snapshot?.open?.leader { return "\(leader.name) leidt" }
        guard let top = snapshot?.ranking.first else { return "Geen potjes" }
        return "\(top.name) bovenaan"
    }

    private var standBySub: String {
        if let open = snapshot?.open { return open.rule.uppercased() }
        return "WINSTPERCENTAGE PER SPELER"
    }

    private var standByRows: [(String, String)] {
        if let open = snapshot?.open {
            return open.standings.dropFirst().prefix(3).map { ($0.name, "\($0.total)") }
        }
        let rows: [WidgetSnapshot.RankEntry] = Array((snapshot?.ranking ?? []).dropFirst().prefix(3))
        return rows.map {
            ($0.name, $0.winRate.percentText)
        }
    }

    // MARK: - Toegangsscherm · één kleur, geen vulling

    /// De cirkel toont het verschil met de eerstvolgende speler, niet het
    /// totaal: een getal zonder context is op 72 px waardeloos.
    private var circular: some View {
        VStack(spacing: 3) {
            Text(circularBig)
                .font(M.font(26, .extraBold))
                .tracking(em: -0.03, size: 26)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(circularSub)
                .font(M.font(8, .semiBold))
                .tracking(em: 0.1, size: 8)
        }
        .padding(4)
    }

    private var circularBig: String {
        if let open = snapshot?.open, open.standings.count > 1 { return "+\(open.gap)" }
        if let top = snapshot?.ranking.first { return "\(Int((top.winRate * 100).rounded()))" }
        return "—"
    }

    private var circularSub: String {
        snapshot?.open != nil ? "VOOR" : "WINST%"
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rectangularKicker)
                .font(M.font(8, .semiBold))
                .tracking(em: 0.11, size: 8)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(standByBig)
                    .font(M.font(21, .extraBold))
                    .tracking(em: -0.02, size: 21)
                Text(rectangularName)
                    .font(M.font(11, .semiBold))
                    .lineLimit(1)
            }
            Text(rectangularFoot)
                .font(M.font(9, .regular))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rectangularKicker: String {
        if let open = snapshot?.open { return "\(open.gameName) · \(open.position)".uppercased() }
        return "RANGLIJST · \(snapshot?.period ?? "90 dagen")".uppercased()
    }

    private var rectangularName: String {
        snapshot?.open?.leader?.name ?? snapshot?.ranking.first?.name ?? ""
    }

    private var rectangularFoot: String {
        if let open = snapshot?.open, open.standings.count > 1 {
            return "\(open.rule) · \(open.gap) voor op \(open.standings[1].name)"
        }
        return "\(snapshot?.totalMatches ?? 0) potjes · geen potje open"
    }

    private var inline: some View {
        if let open = snapshot?.open, let leader = open.leader {
            Text("\(open.gameName) · \(leader.name) leidt met \(leader.total)")
        } else if let top = snapshot?.ranking.first {
            Text("Geen potje open · \(top.name) bovenaan")
        } else {
            Text("Scoreblok")
        }
    }
}

// MARK: - Kleine bouwstenen

private struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(M.font(9, .semiBold))
            .tracking(em: 0.12, size: 9)
            .foregroundStyle(M.inkAlpha(0.65))
            .lineLimit(1)
    }
}

private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(M.font(10.5, .regular))
            .foregroundStyle(M.inkAlpha(0.7))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 9)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(hex: 0xC9C5C5)).frame(height: 1)
            }
    }
}

private struct Rule: View {
    let weight: CGFloat
    var vertical = false
    init(_ weight: CGFloat, vertical: Bool = false) {
        self.weight = weight
        self.vertical = vertical
    }

    var body: some View {
        Rectangle()
            .fill(weight >= 2 ? M.ruleHeavy : M.hairline)
            .frame(width: vertical ? weight : nil, height: vertical ? nil : weight)
    }
}

extension WidgetSnapshot {
    /// Alleen voor de voorvertoning in de widgetgalerij.
    static let preview: WidgetSnapshot = {
        let names = [("Mila", 2, 0, 31), ("Sanne", 0, 2, 38), ("Bram", 3, 8, 49), ("Joost", 1, 5, 53)]
        let entries = names.enumerated().map { index, item in
            Entry(id: UUID(), name: item.0, initial: String(item.0.prefix(1)),
                  total: item.3, rank: index + 1, rampIndex: item.1,
                  avatarIndex: item.2, gap: item.3 - 31)
        }
        return WidgetSnapshot(
            open: OpenMatch(id: UUID(), gameName: "Jokeren", mono: "JO",
                            unitLabel: "kaarten", position: "ronde 4 van 9",
                            rule: "laagste totaal wint", startedAt: .now, lastPlayed: .now,
                            standings: entries,
                            playedRounds: [
                                .init(label: "1", cells: ["4", "12", "21", "30"]),
                                .init(label: "2", cells: ["18", "4", "25", "8"]),
                                .init(label: "3", cells: ["9", "22", "3", "15"])
                            ]),
            ranking: names.enumerated().map { index, item in
                RankEntry(id: UUID(), name: item.0, initial: String(item.0.prefix(1)),
                          rampIndex: item.1, avatarIndex: item.2,
                          winRate: [0.44, 0.41, 0.36, 0.31][index], played: 31 - index)
            },
            period: "90 dagen", totalMatches: 31, lastFinished: .now)
    }()
}
