import SwiftUI

/// De tekeningen bij de rondleiding. Geen schermafdrukken: die verouderen
/// stilletjes en liegen daarna. Dit zijn schema's in dezelfde taal als de
/// app — rechte hoeken, twee lijndiktes, rood alleen waar het iets betekent.
struct OnboardingArt: View {
    let kind: OnboardingPage.Art
    /// Breed vult de tekening de kolom naast de tekst. Smal staat ze erboven
    /// en moet ze haar eigen hoogte bepalen, anders wordt ze afgeknipt.
    var fills = true
    /// Breedte van de tekening. Op een 13-inch iPad mag ze ruimer staan dan
    /// op een iPhone, anders verdrinkt ze in het wit.
    var span: CGFloat = 300

    var body: some View {
        Group {
            switch kind {
            case .mark: mark
            case .games: games
            case .board: board
            case .resume: resume
            case .stats: stats
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: fills ? .infinity : nil)
        .accessibilityHidden(true)
    }

    // MARK: - Het merkteken, groot

    private var mark: some View {
        ScoreblokMark(stroke: 11)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: fills ? span * 0.86 : 150)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Spellen op de plank, en één in de kast

    private var games: some View {
        VStack(spacing: 0) {
            tile("JO", "Jokeren", "6 rondes", accent: true)
            Hairline()
            tile("YA", "Yahtzee", "13 categorieën")
            Hairline()
            tile("QX", "Qwixx", "4 rijen")
            HeavyRule()
            HStack(spacing: 10) {
                Rectangle()
                    .stroke(M.ruleHeavy, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spellenkast")
                        .font(M.font(12.5, .extraBold))
                        .foregroundStyle(M.inkAlpha(0.5))
                    Text("wat je niet speelt")
                        .font(M.font(10, .regular))
                        .foregroundStyle(M.inkAlpha(0.4))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: span)
        .overlay(alignment: .top) { Rectangle().fill(M.ruleHeavy).frame(height: 2) }
    }

    private func tile(_ code: String, _ name: String, _ note: String,
                      accent: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(code)
                .font(M.font(11, .extraBold))
                .foregroundStyle(M.paper)
                .frame(width: 30, height: 30)
                .background(accent ? M.red : M.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(M.font(12.5, .extraBold))
                    .foregroundStyle(M.ink)
                Text(note)
                    .font(M.font(10, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Het telblok: drie spelers, drie rondes, één toets

    private var board: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                cell("", head: true, width: 34)
                cell("AN", head: true)
                cell("BO", head: true)
                cell("CH", head: true)
            }
            HeavyRule()
            ForEach(Array([["1", "12", "8", "20"],
                           ["2", "31", "24", "26"],
                           ["3", "—", "—", "—"]].enumerated()), id: \.offset) { spot, row in
                if spot > 0 { Hairline() }
                HStack(spacing: 0) {
                    cell(row[0], width: 34, dim: true)
                    cell(row[1], live: spot == 2)
                    cell(row[2], live: spot == 2)
                    cell(row[3], live: spot == 2)
                }
            }
            HeavyRule()
            HStack(spacing: 3) {
                ForEach(["7", "8", "9"], id: \.self) { key in
                    Text(key)
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.ink)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                }
                Text("OK")
                    .font(M.font(12, .extraBold))
                    .foregroundStyle(M.paper)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(M.red)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: span)
        .overlay(alignment: .top) { Rectangle().fill(M.ruleHeavy).frame(height: 2) }
    }

    private func cell(_ text: String, head: Bool = false, width: CGFloat? = nil,
                      dim: Bool = false, live: Bool = false) -> some View {
        Text(text)
            .font(M.font(head ? 10 : 13, head ? .semiBold : .extraBold))
            .tracking(em: head ? 0.1 : -0.02, size: head ? 10 : 13)
            .foregroundStyle(live ? M.red : (dim || head ? M.inkAlpha(0.5) : M.ink))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: head ? 26 : 32)
            .background(live ? M.redWash : .clear)
    }

    // MARK: - De balk onderin

    private var resume: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(M.inkAlpha(0.1)).frame(height: 12)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)

            HeavyRule()
            HStack(spacing: 10) {
                Text("JO")
                    .font(M.font(10, .extraBold))
                    .foregroundStyle(M.paper)
                    .frame(width: 28, height: 28)
                    .background(M.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jokeren · ronde 3 van 6")
                        .font(M.font(11.5, .extraBold))
                        .foregroundStyle(M.ink)
                    Text("gisteren onderbroken")
                        .font(M.font(9.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                }
                Spacer(minLength: 0)
                Text("VERDER")
                    .font(M.font(10, .extraBold))
                    .tracking(em: 0.1, size: 10)
                    .foregroundStyle(M.paper)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(M.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: span)
        .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
    }

    // MARK: - Staafjes met winstpercentages

    private var stats: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array([("Anne", 0.62), ("Bo", 0.48), ("Chris", 0.31)].enumerated()),
                    id: \.offset) { spot, row in
                if spot > 0 { Hairline() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.0)
                            .font(M.font(12, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 0)
                        Text(row.1.percentText)
                            .font(M.font(15, .extraBold))
                            .tracking(em: -0.02, size: 15)
                            .foregroundStyle(spot == 0 ? M.red : M.ink)
                    }
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(spot == 0 ? M.red : M.ink)
                            .frame(width: proxy.size.width * row.1, height: 8)
                    }
                    .frame(height: 8)
                    .background(alignment: .leading) {
                        Rectangle().fill(M.inkAlpha(0.08)).frame(height: 8)
                    }
                }
                .padding(.vertical, 11)
            }
        }
        .frame(maxWidth: span)
        .overlay(alignment: .top) { Rectangle().fill(M.ruleHeavy).frame(height: 2) }
    }
}
