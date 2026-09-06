import SwiftUI

// MARK: - Tekststijlen

extension View {
    /// Numeriek toetsenbord op de platforms die er een hebben; elders een
    /// gewoon veld, want het hardwaretoetsenbord doet het werk al.
    func numericKeyboard() -> some View {
        #if os(iOS) || os(visionOS)
        return keyboardType(.numbersAndPunctuation)
        #else
        return self
        #endif
    }
}

/// Klein kapitaal kopje boven een blok: 10px/800, ruime letterspatiëring.
struct SectionLabel: View {
    let text: String
    var tint: Color = M.inkAlpha(0.5)

    init(_ text: String, tint: Color = M.inkAlpha(0.5)) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(M.font(10, .semiBold))
            .tracking(em: 0.14, size: 10)
            .foregroundStyle(tint)
    }
}

/// De grote schermtitel (34px/800, strak gespatieerd).
struct ScreenTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(M.font(34, .extraBold))
            .tracking(em: -0.02, size: 34)
            .foregroundStyle(M.ink)
    }
}

// MARK: - Lijnen

/// Haarlijn (1px) tussen rijen binnen één blok.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(M.hairline).frame(height: 1)
    }
}

/// Zware scheidslijn (2px) tussen hoofdgebieden.
struct HeavyRule: View {
    var body: some View {
        Rectangle().fill(M.ruleHeavy).frame(height: 2)
    }
}

// MARK: - Speler

/// Monogram van een spel — twee letters op inkt of rood.
struct GameMark: View {
    let mono: String
    var background: Color = M.ink
    var foreground: Color = M.paper
    var size: CGFloat = 44

    var body: some View {
        Text(mono)
            .font(M.font(size * 0.34, .extraBold))
            .tracking(em: 0.02, size: size * 0.34)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
    }
}

// MARK: - Knoppen

/// Omlijnde knop: 1px rand, 44pt hoog, licht oplichtend bij aanraking.
struct OutlineButton: View {
    let title: String
    var tint: Color = M.ink
    var minHeight: CGFloat = M.tap
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(M.font(12.5, .extraBold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: minHeight)
                .background(pressed ? M.inkAlpha(0.07) : .clear)
                .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

/// Gevulde knop: de primaire actie. Rood, of inkt voor een zware maar
/// niet-primaire actie.
struct SolidButton: View {
    let title: String
    var fill: Color = M.red
    var foreground: Color = M.paper
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = M.tap
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(M.font(fontSize, .extraBold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minHeight: minHeight)
                .background(enabled ? fill : Color(hex: 0xBAB6B6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Terugpijl linksboven in een subscherm: "← SPELEN".
struct BackLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("← " + title.uppercased())
                .font(M.font(13, .semiBold))
                .foregroundStyle(M.red)
                .lineLimit(1)
                .frame(minHeight: M.tap)
        }
        .buttonStyle(.plain)
    }
}

/// Segmentkeuze met harde randen: één blok, scheidslijnen ertussen.
struct SegmentedBar<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var fontSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(M.font(fontSize, .extraBold))
                        .foregroundStyle(isOn ? M.paper : M.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: M.tap)
                        .background(isOn ? M.ink : .clear)
                        // Als overlay, zodat de lijn de balk niet oprekt.
                        .overlay(alignment: .trailing) {
                            if index < options.count - 1 {
                                Rectangle().fill(M.ruleHeavy).frame(width: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
    }
}

/// − / + paar met harde randen, 44pt per helft.
struct StepperPair: View {
    var canDecrement = true
    var canIncrement = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            key("−", enabled: canDecrement, action: onDecrement)
            Rectangle().fill(M.ruleHeavy).frame(width: 1)
            key("+", enabled: canIncrement, action: onIncrement)
        }
        .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
    }

    private func key(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(M.font(18, .regular))
                .foregroundStyle(enabled ? M.ink : M.inkAlpha(0.3))
                .frame(width: M.tap, height: M.tap)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Rechthoekige schakelaar: 64×34, 2px rand, knop schuift naar rechts.
struct HardToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                if isOn { Spacer(minLength: 0) }
                Rectangle()
                    .fill(isOn ? M.paper : M.ink)
                    .frame(width: 26, height: 26)
                if !isOn { Spacer(minLength: 0) }
            }
            .padding(2)
            .frame(width: 64, height: 34)
            .background(isOn ? M.red : Color.clear)
            .overlay(Rectangle().stroke(M.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Vierkant aankruisvakje, 20×20 met 2px rand.
struct HardCheckbox: View {
    let isOn: Bool

    var body: some View {
        Text(isOn ? "✓" : "")
            .font(M.font(12, .extraBold))
            .foregroundStyle(M.paper)
            .frame(width: 20, height: 20)
            .background(isOn ? M.ink : Color.clear)
            .overlay(Rectangle().stroke(isOn ? M.ink : M.ruleHeavy, lineWidth: 2))
    }
}

// MARK: - Blokken

/// Cijferblok met kopje, groot getal en onderschrift.
struct FigureTile: View {
    let label: String
    let value: String
    var sub: String?
    var valueSize: CGFloat = 32
    var minHeight: CGFloat = 126

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(M.font(10, .semiBold))
                .tracking(em: 0.1, size: 10)
                .foregroundStyle(M.inkAlpha(0.5))
                .lineSpacing(3)
                .frame(minHeight: 26, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(M.font(valueSize, .extraBold))
                .tracking(em: -0.03, size: valueSize)
                .foregroundStyle(M.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .padding(.top, 7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
        .frame(minHeight: minHeight, alignment: .topLeading)
    }
}

/// Horizontale voortgangsbalk in inkt op haarlijngrijs.
struct BarMeter: View {
    let fraction: Double
    var height: CGFloat = 8
    var fill: Color = M.ink
    var track: Color = M.hairline

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle()
                    .fill(fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Rij die het hele blok beslaat en aanraakbaar is, met haarlijn eronder.
struct RowButton<Content: View>: View {
    var background: Color = .clear
    var minHeight: CGFloat = 52
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: minHeight)
                .background(pressed ? M.paperDeep : background)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

/// Etiket in kapitalen op een vlak — "WINST", "AFGEBROKEN", "LEIDT".
struct Tag: View {
    let text: String
    var background: Color = M.ink
    var foreground: Color = M.paper
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(M.font(size, .extraBold))
            .tracking(em: 0.1, size: size)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(background)
    }
}

// MARK: - Invoer

/// Invoerveld met harde rand, zoals de velden in de spel-editor.
struct HardTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 16
    var minHeight: CGFloat = 48

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(M.font(fontSize, .semiBold))
            .foregroundStyle(M.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
    }
}

/// Een vlak paneel over het scherm: 2px inktrand, geen radius, geen schaduw.
struct ModalPanel<Content: View>: View {
    let title: String
    var width: CGFloat = 420
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            M.ink.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(M.font(17, .extraBold))
                        .foregroundStyle(M.ink)
                    Spacer()
                    Button(action: onClose) {
                        Text("✕")
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.6))
                            .frame(width: M.tap, height: M.tap)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 20)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                Rectangle().fill(M.ruleHeavy).frame(height: 2)

                content()
            }
            .frame(width: width)
            .background(M.paper)
            .overlay(Rectangle().stroke(M.ink, lineWidth: 2))
        }
    }
}

/// Rij in een regelblok: label links, waarde of bediening rechts.
struct RuleRow<Trailing: View>: View {
    let title: String
    var hint: String?
    var minHeight: CGFloat = 64
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(M.ink)
                if let hint {
                    Text(hint)
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(minHeight: minHeight)
    }
}

/// Bovenbalk van een subscherm: terugpijl, titel, en acties rechts.
struct ScreenBar<Trailing: View>: View {
    let backTitle: String
    let onBack: () -> Void
    var title: String?
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.isCompact) private var isCompact
    @Environment(\.contentWidth) private var contentWidth

    /// Onder deze breedte passen titel, regel en knoppen niet meer op één
    /// regel zonder dat er iets afkapt. Dan liever twee regels dan een
    /// afgekapte zin.
    private var stacked: Bool { contentWidth < 900 }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    BackLink(title: backTitle, action: onBack)
                    if let title {
                        Text(title)
                            .font(M.font(isCompact ? 17 : 19, .extraBold))
                            .tracking(em: -0.01, size: isCompact ? 17 : 19)
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { trailing() }
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, isCompact ? 16 : 24)
            .padding(.vertical, isCompact ? 10 : 12)
        } else {
            HStack(spacing: 16) {
                BackLink(title: backTitle, action: onBack)
                Rectangle().fill(M.hairline).frame(width: 1, height: 22)
                if let title {
                    Text(title)
                        .font(M.font(19, .extraBold))
                        .tracking(em: -0.01, size: 19)
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}
