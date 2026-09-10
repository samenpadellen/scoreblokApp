import SwiftUI

/// Beweging in één toon: kort, strak, zonder te stuiteren. Elke animatie in
/// de app haalt zijn tempo hier vandaan. Wie in iOS "Verminder beweging"
/// aanzet, houdt alleen vervagen over: niets schuift, groeit of deukt in.
extension M {
    enum Motion {
        /// Indrukken, een vinkje, een cel kiezen.
        static let quick = Animation.snappy(duration: 0.18)
        /// Iets dat van plek wisselt: de keuze in een balk, de actieve tab.
        static let settle = Animation.snappy(duration: 0.3)
        /// Iets dat verschijnt: balken die vollopen, het podium.
        static let reveal = Animation.spring(duration: 0.55, bounce: 0.12)
    }
}

/// Knoppen en rijen die meegeven onder je vinger. Toetsen deuken duidelijk
/// in, rijen bijna niet; beide krijgen zolang je drukt een zweem inkt.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var shade: Double = 0.06

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Rectangle()
                    .fill(M.ink.opacity(configuration.isPressed ? shade : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(M.Motion.quick, value: configuration.isPressed)
    }
}

/// Laat iets vanaf nul oplopen zodra het in beeld komt: een balk van links,
/// het podium van onder.
private struct RiseIn: ViewModifier {
    let delay: Double
    let anchor: UnitPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        let vertical = anchor == .bottom
        return content
            .scaleEffect(x: vertical || visible ? 1 : 0.001,
                         y: !vertical || visible ? 1 : 0.001,
                         anchor: anchor)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(M.Motion.reveal.delay(delay)) { shown = true }
                }
            }
    }
}

/// Tekent iets van links naar rechts in beeld, zoals een lijn die wordt
/// getrokken. Zonder beweging staat het er meteen.
private struct RevealFromLeading: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: shown || reduceMotion ? proxy.size.width + 120 : 0)
                }
            }
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.9).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Van links naar rechts in beeld tekenen.
    func revealFromLeading(delay: Double = 0) -> some View {
        modifier(RevealFromLeading(delay: delay))
    }

    /// Oplopen bij verschijnen. `from: .leading` voor balken, `.bottom` voor zuilen.
    func riseIn(delay: Double = 0, from anchor: UnitPoint = .leading) -> some View {
        modifier(RiseIn(delay: delay, anchor: anchor))
    }
}
