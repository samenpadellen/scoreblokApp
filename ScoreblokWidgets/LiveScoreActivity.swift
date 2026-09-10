import ActivityKit
import SwiftUI
import WidgetKit

/// Het lopende potje op het toegangsscherm en in het Dynamic Island. Op het
/// toegangsscherm dezelfde rode kaart als de widget; in het eiland alleen
/// wat je in een oogopslag wilt: het spel, de leider en zijn stand.
struct LiveScoreActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveScoreAttributes.self) { context in
            LiveScoreLockView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(M.red)
                .activitySystemActionForegroundColor(M.paper)
                .widgetURL(Self.url(for: context.attributes))
        } dynamicIsland: { context in
            let leader = context.state.lines.first
            // In het eiland draagt het spel zijn eigen kleur.
            let accent = context.attributes.accentHex.map { Color(hex: $0) } ?? M.red
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let leader {
                        HStack(spacing: 8) {
                            LiveMark(line: leader, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(context.state.isFinished ? "WINT" : "LEIDT")
                                    .font(M.font(9, .extraBold))
                                    .tracking(em: 0.12, size: 9)
                                    .foregroundStyle(accent)
                                Text(leader.name)
                                    .font(M.font(15, .extraBold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(leader?.total ?? 0)")
                        .font(M.font(30, .extraBold))
                        .tracking(em: -0.04, size: 30)
                        .foregroundStyle(accent)
                        .contentTransition(.numericText(value: Double(leader?.total ?? 0)))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(context.attributes.gameName) · \(context.state.position)".uppercased())
                            .font(M.font(9.5, .extraBold))
                            .tracking(em: 0.12, size: 9.5)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        HStack(spacing: 0) {
                            ForEach(Array(context.state.lines.dropFirst().prefix(3))) { line in
                                HStack(spacing: 5) {
                                    LiveMark(line: line, size: 14)
                                    Text(line.name)
                                        .font(M.font(11.5, .semiBold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text("\(line.total)")
                                        .font(M.font(12.5, .extraBold))
                                        .foregroundStyle(.white)
                                        .contentTransition(.numericText(value: Double(line.total)))
                                }
                                .padding(.trailing, 10)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(context.attributes.mono)
                    .font(M.font(13, .extraBold))
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text("\(leader?.total ?? 0)")
                    .font(M.font(13, .extraBold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(leader?.total ?? 0)))
            } minimal: {
                Text(leader?.initial ?? "·")
                    .font(M.font(13, .extraBold))
                    .foregroundStyle(accent)
            }
            .widgetURL(Self.url(for: context.attributes))
            .keylineTint(accent)
        }
    }

    static func url(for attributes: LiveScoreAttributes) -> URL? {
        URL(string: "scoreblok://match/\(attributes.matchID.uuidString)")
    }
}

struct LiveScoreLockView: View {
    let attributes: LiveScoreAttributes
    let state: LiveScoreAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(attributes.gameName) · \(state.position)".uppercased())
                    .font(M.font(10.5, .extraBold))
                    .tracking(em: 0.12, size: 10.5)
                    .foregroundStyle(M.paperAlpha(0.8))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.isFinished ? "AFGEROND" : attributes.rule.uppercased())
                    .font(M.font(9.5, .semiBold))
                    .tracking(em: 0.1, size: 9.5)
                    .foregroundStyle(M.paperAlpha(0.62))
                    .lineLimit(1)
            }

            if let leader = state.lines.first {
                HStack(alignment: .center, spacing: 10) {
                    LiveMark(line: leader, size: 30)
                    Text(state.isFinished ? "\(leader.name) wint" : "\(leader.name) leidt")
                        .font(M.font(22, .extraBold))
                        .tracking(em: -0.01, size: 22)
                        .foregroundStyle(M.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("\(leader.total)")
                        .font(M.font(40, .extraBold))
                        .tracking(em: -0.04, size: 40)
                        .foregroundStyle(M.paper)
                        .contentTransition(.numericText(value: Double(leader.total)))
                }
                .padding(.top, 10)
            }

            Rectangle()
                .fill(M.paperAlpha(0.35))
                .frame(height: 1)
                .padding(.vertical, 10)

            HStack(spacing: 0) {
                ForEach(Array(state.lines.dropFirst().prefix(4))) { line in
                    HStack(spacing: 6) {
                        LiveMark(line: line, size: 16)
                        Text(line.name)
                            .font(M.font(12, .semiBold))
                            .foregroundStyle(M.paperAlpha(0.86))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(line.total)")
                            .font(M.font(13, .extraBold))
                            .foregroundStyle(M.paper)
                            .contentTransition(.numericText(value: Double(line.total)))
                    }
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(M.redGradient)
    }
}

/// De spelermarkering in het klein, zoals op de widgets.
struct LiveMark: View {
    let line: LiveScoreAttributes.Line
    var size: CGFloat = 16

    private var ramp: (bg: Int, ink: Int) {
        M.playerRamp[((line.rampIndex % M.playerRamp.count) + M.playerRamp.count) % M.playerRamp.count]
    }

    var body: some View {
        AvatarShape(index: line.avatarIndex)
            .fill(Color(hex: ramp.ink))
            .frame(width: size, height: size)
            .background(Color(hex: ramp.bg))
    }
}
