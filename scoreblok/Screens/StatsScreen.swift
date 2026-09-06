import SwiftUI
import SwiftData

struct StatsScreen: View {
    @Environment(Router.self) private var router
    @Query private var allMatches: [Match]
    @Query(sort: \Player.createdAt) private var players: [Player]

    @State private var period: StatsPeriod = .days90
    @State private var gameFilter: String? = nil

    private var me: Player? { players.first(where: \.isMe) ?? players.first }

    private var scoped: [Match] {
        let base = StatsEngine.matches(allMatches, in: period)
        guard let gameFilter else { return base }
        return base.filter { $0.gameName == gameFilter }
    }

    private var previous: [Match] {
        let base = StatsEngine.previousMatches(allMatches, in: period)
        guard let gameFilter else { return base }
        return base.filter { $0.gameName == gameFilter }
    }

    private var gameNames: [String] {
        Array(Set(allMatches.filter(\.counts).map(\.gameName))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Hairline()
                filterBar
                HeavyRule()

                if scoped.isEmpty {
                    empty
                } else {
                    tiles
                    HeavyRule()
                    formAndRanking
                    HeavyRule()
                    headToHeadAndRecords
                    HeavyRule()
                    jokerBlock
                    calendarAndMix
                }
            }
        }
    }

    private var header: some View {
        ScreenTitle("Statistieken")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 24, leading: 28, bottom: 16, trailing: 28))
    }

    private var empty: some View {
        Text("Nog geen afgeronde potjes in deze periode. Speel een potje, dan verschijnen hier de cijfers.")
            .font(M.font(13, .regular))
            .foregroundStyle(M.inkAlpha(0.6))
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
    }

    // MARK: - Filterbalk

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(StatsPeriod.allCases) { option in
                let isOn = option == period
                Button { period = option } label: {
                    Text(option.rawValue)
                        .font(M.font(12.5, .extraBold))
                        .foregroundStyle(isOn ? M.paper : M.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .background(isOn ? M.ink : .clear)
                }
                .buttonStyle(.plain)
                Rectangle().fill(M.hairline).frame(width: 1)
            }

            Menu {
                Button("Alle spellen") { gameFilter = nil }
                ForEach(gameNames, id: \.self) { name in
                    Button(name) { gameFilter = name }
                }
            } label: {
                Text("\(gameFilter ?? "Alle spellen") ▾")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.6))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
            }
            .menuStyle(.borderlessButton)
            Rectangle().fill(M.hairline).frame(width: 1)

            Spacer(minLength: 0)
            Text("Berekend, niet opgeslagen")
                .font(M.font(11.5, .regular))
                .foregroundStyle(M.inkAlpha(0.45))
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Cijferblokken

    private var tiles: some View {
        let mine = me.map { StatsEngine.results(for: $0, in: scoped) } ?? []
        let minePrev = me.map { StatsEngine.results(for: $0, in: previous) } ?? []
        let wins = mine.filter(\.isWin).count
        let rate = mine.isEmpty ? 0 : Double(wins) / Double(mine.count)
        let prevRate = minePrev.isEmpty ? 0
            : Double(minePrev.filter(\.isWin).count) / Double(minePrev.count)
        let averageRank = mine.isEmpty ? 0
            : Double(mine.map(\.rank).reduce(0, +)) / Double(mine.count)
        let streak = me.map { StatsEngine.streak(for: $0, in: scoped) } ?? Streak(count: 0, isWin: false)
        let evenings = StatsEngine.playDays(scoped)
        let prevEvenings = StatsEngine.playDays(previous)

        let items: [(String, String, String)] = [
            ("Potjes gespeeld", "\(scoped.count)",
             previous.isEmpty ? "geen vergelijking"
                : (scoped.count - previous.count).trendText + " potjes"),
            ("Winstpercentage — \(me?.name ?? "jij")", mine.isEmpty ? "—" : rate.percentText,
             minePrev.count < 3 ? "te weinig data om te vergelijken"
                : Int(((rate - prevRate) * 100).rounded()).trendText + "%"),
            ("Huidige reeks", streak.count == 0 ? "—" : "\(streak.count)", streak.long),
            ("Gemiddelde eindpositie", mine.isEmpty ? "—" : averageRank.dutch(1),
             "over \(mine.count) potjes"),
            ("Speelavonden", "\(evenings)",
             previous.isEmpty ? "geen vergelijking" : (evenings - prevEvenings).trendText)
        ]

        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.0.uppercased())
                        .font(M.font(10, .semiBold))
                        .tracking(em: 0.1, size: 10)
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineSpacing(3)
                        .frame(minHeight: 26, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(item.1)
                        .font(M.font(34, .extraBold))
                        .tracking(em: -0.03, size: 34)
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(item.2)
                        .font(M.font(11.5, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .padding(.top, 9)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
                .frame(minHeight: 126, alignment: .topLeading)
                .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
            }
        }
    }

    // MARK: - Vorm en ranglijst

    private var formAndRanking: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vorm")
                        .font(M.font(18, .extraBold))
                        .foregroundStyle(M.ink)
                    Spacer()
                    Text("winst% voortschrijdend over 10 potjes")
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                .padding(.bottom, 16)

                let lines = StatsEngine.formLines(for: players.filter { !$0.isArchived }, in: scoped)
                if lines.isEmpty {
                    Text("Te weinig potjes voor een lijn.")
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .frame(height: 176)
                } else {
                    FormChart(lines: lines).frame(height: 176)
                    HStack(spacing: 20) {
                        ForEach(lines) { line in
                            HStack(spacing: 8) {
                                Rectangle().fill(line.player.color).frame(width: 10, height: 10)
                                Text("\(line.player.name) \(line.last.percentText)")
                                    .font(M.font(12, .semiBold))
                                    .foregroundStyle(M.inkAlpha(0.7))
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 20, trailing: 24))
            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

            rankingBlock
                .frame(width: 380)
        }
    }

    private var rankingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ranglijst")
                .font(M.font(18, .extraBold))
                .foregroundStyle(M.ink)
                .padding(.bottom, 14)

            HStack {
                Text("SPELER")
                Spacer()
                Text("TREND · WINST% · N")
            }
            .font(M.font(9.5, .semiBold))
            .tracking(em: 0.12, size: 9.5)
            .foregroundStyle(M.inkAlpha(0.45))
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(M.ruleHeavy).frame(height: 2) }

            let rows = StatsEngine.standings(for: players, in: scoped)
            let before = StatsEngine.standings(for: players, in: previous)

            ForEach(rows) { row in
                let old = before.first { $0.id == row.id }
                let shift = old.map { Int(((row.winRate - $0.winRate) * 100).rounded()) }

                Button { router.screen = .detail(row.player) } label: {
                    HStack(spacing: 12) {
                        PlayerMark(player: row.player, size: 26)
                        Text(row.player.name)
                            .font(M.font(14, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 8)
                        Text(shift.map { $0 == 0 ? "—" : "\($0.trendText)%" } ?? "—")
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.55))
                            .frame(width: 62, alignment: .trailing)
                        Text(row.winRate.percentText)
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 46, alignment: .trailing)
                        Text("\(row.played)")
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.45))
                            .frame(width: 28, alignment: .trailing)
                    }
                    .frame(minHeight: 46)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
        .padding(EdgeInsets(top: 18, leading: 24, bottom: 8, trailing: 24))
    }

    // MARK: - Kop-tot-kop en records

    private var headToHeadAndRecords: some View {
        HStack(alignment: .top, spacing: 0) {
            headToHeadBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

            VStack(alignment: .leading, spacing: 0) {
                Text("Records")
                    .font(M.font(18, .extraBold))
                    .foregroundStyle(M.ink)
                    .padding(.bottom, 14)

                let records = StatsEngine.records(in: scoped)
                if records.isEmpty {
                    Text("Nog geen records.")
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                ForEach(records) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(record.label)
                            .font(M.font(13, .regular))
                            .foregroundStyle(M.inkAlpha(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(record.value)
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(M.ink)
                        Text(record.who)
                            .font(M.font(11, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 74, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                    Hairline()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 20, trailing: 24))
        }
    }

    private var headToHeadBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kop-tot-kop")
                .font(M.font(18, .extraBold))
                .foregroundStyle(M.ink)

            if let me, let opponent = StatsEngine.mostFrequentOpponent(of: me, in: scoped) {
                let lines = StatsEngine.headToHead(me, versus: opponent, in: scoped)
                let wins = lines.reduce(0) { $0 + $1.wins }
                let losses = lines.reduce(0) { $0 + $1.losses }
                let total = max(wins + losses, 1)

                Text("\(me.name) tegen \(opponent.name) · \(gameFilter ?? "alle spellen") · \(wins + losses) potjes samen")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .padding(.top, 6)
                    .padding(.bottom, 16)

                HStack(spacing: 14) {
                    Text("\(wins)")
                        .font(M.font(40, .extraBold))
                        .tracking(em: -0.03, size: 40)
                        .foregroundStyle(M.ink)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle().fill(M.red)
                                .frame(width: proxy.size.width * Double(wins) / Double(total))
                            Rectangle().fill(Color(hex: 0x2D2B2B))
                                .frame(width: proxy.size.width * Double(losses) / Double(total))
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 12)
                    .background(M.hairline)
                    Text("\(losses)")
                        .font(M.font(40, .extraBold))
                        .tracking(em: -0.03, size: 40)
                        .foregroundStyle(M.ink)
                }
                .padding(.bottom, 18)

                ForEach(lines) { line in
                    HStack(spacing: 12) {
                        Text(line.gameName)
                            .font(M.font(13.5, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.75))
                        Spacer(minLength: 8)
                        Text(line.score)
                            .font(M.font(14, .extraBold))
                            .foregroundStyle(M.ink)
                        Text("gem. \(Int(line.averageDifference.rounded()).signedText) punten")
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 130, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Hairline() }
                }
            } else {
                Text("Nog geen medespeler om tegen af te zetten.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .padding(.top, 10)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 24, bottom: 20, trailing: 24))
    }

    // MARK: - Jokerteller

    /// Alleen zichtbaar als er potjes met de jokerteller gespeeld zijn.
    @ViewBuilder
    private var jokerBlock: some View {
        let lines = StatsEngine.jokers(for: players, in: scoped)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Jokerteller")
                        .font(M.font(18, .extraBold))
                        .foregroundStyle(M.ink)
                    Spacer()
                    Text("jokers over alle potjes met de teller aan")
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                .padding(.bottom, 14)

                let most = max(lines.map(\.total).max() ?? 1, 1)
                ForEach(lines) { line in
                    HStack(spacing: 12) {
                        PlayerMark(player: line.player, size: 26)
                        Text(line.player.name)
                            .font(M.font(14, .semiBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                        BarMeter(fraction: Double(line.total) / Double(most),
                                 height: 10, fill: M.red, track: M.paperDeep)
                        Text("\(line.total)")
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 40, alignment: .trailing)
                        Text("\(line.perMatch.dutch(1)) p/potje")
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 96, alignment: .trailing)
                    }
                    .frame(minHeight: 46)
                    Hairline()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 20, trailing: 24))
            HeavyRule()
        }
    }

    // MARK: - Kalender en spelmix

    private var calendarAndMix: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Speelkalender")
                        .font(M.font(18, .extraBold))
                        .foregroundStyle(M.ink)
                    Spacer()
                    Text("potjes per week · 52 weken")
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                .padding(.bottom, 16)

                CalendarGrid(weeks: StatsEngine.calendar(allMatches.filter(\.counts)))

                HStack {
                    ForEach(calendarLabels, id: \.self) { label in
                        Text(label)
                        if label != calendarLabels.last { Spacer() }
                    }
                }
                .font(M.font(9.5, .semiBold))
                .tracking(em: 0.1, size: 9.5)
                .foregroundStyle(M.inkAlpha(0.45))
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 24, trailing: 24))
            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

            VStack(alignment: .leading, spacing: 0) {
                Text("Wat spelen we het meest")
                    .font(M.font(18, .extraBold))
                    .foregroundStyle(M.ink)
                    .padding(.bottom, 14)

                ForEach(StatsEngine.mix(in: scoped, previous: previous)) { line in
                    HStack(spacing: 12) {
                        Text(line.gameName)
                            .font(M.font(13, .semiBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)
                        BarMeter(fraction: line.fraction, height: 10, track: M.paperDeep)
                        Text("\(line.count)")
                            .font(M.font(13, .extraBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 34, alignment: .trailing)
                        Text(line.shift == 0 ? "—" : line.shift.signedText)
                            .font(M.font(11, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                    Hairline()
                }
            }
            .frame(width: 420, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 24, trailing: 24))
        }
    }

    private var calendarLabels: [String] {
        let calendar = Calendar.current
        let now = Date.now
        return [-51, -26, 0].compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: now)?
                .formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                .uppercased()
        }
    }
}

// MARK: - Vormgrafiek

/// Vlakke polylijnen, zoals de SVG in het ontwerp: geen assen, vier hulplijnen,
/// een vierkantje op het laatste punt.
struct FormChart: View {
    let lines: [FormLine]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let top: CGFloat = 4
            let bottom = height - 4

            ZStack(alignment: .topLeading) {
                ForEach([0.0, 1.0 / 3.0, 2.0 / 3.0], id: \.self) { fraction in
                    Rectangle()
                        .fill(M.hairline)
                        .frame(height: 1)
                        .offset(y: top + (bottom - top) * fraction)
                }
                Rectangle()
                    .fill(M.ink)
                    .frame(height: 2)
                    .offset(y: bottom)

                ForEach(lines) { line in
                    let points = coordinates(line, width: width, top: top, bottom: bottom)
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(line.player.color,
                            style: StrokeStyle(lineWidth: line.player.isMe ? 3 : 2.5,
                                               lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Rectangle()
                            .fill(line.player.color)
                            .frame(width: 9, height: 9)
                            .position(x: min(last.x, width - 5), y: last.y)
                    }
                }
            }
        }
    }

    private func coordinates(_ line: FormLine, width: CGFloat,
                             top: CGFloat, bottom: CGFloat) -> [CGPoint] {
        let count = line.points.count
        guard count > 1 else { return [] }
        let step = width / CGFloat(count - 1)
        return line.points.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: bottom - (bottom - top) * CGFloat(value))
        }
    }
}

// MARK: - Speelkalender

/// 52 vierkantjes in twee rijen van 26, donkerder naarmate er meer gespeeld is.
struct CalendarGrid: View {
    let weeks: [Int]

    private func shade(_ count: Int) -> (fill: Color, border: Color) {
        switch count {
        case 0: (.clear, M.hairline)
        case 1: (Color(hex: 0xE0DEDD), .clear)
        case 2: (Color(hex: 0xBAB6B6), .clear)
        case 3: (Color(hex: 0x7D7979), .clear)
        case 4: (Color(hex: 0x444141), .clear)
        default: (M.ink, .clear)
        }
    }

    var body: some View {
        let rows = stride(from: 0, to: weeks.count, by: 26).map { start in
            Array(weeks[start..<min(start + 26, weeks.count)])
        }
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, count in
                        let style = shade(count)
                        Rectangle()
                            .fill(style.fill)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Rectangle().stroke(style.border, lineWidth: 1))
                    }
                }
            }
        }
    }
}
