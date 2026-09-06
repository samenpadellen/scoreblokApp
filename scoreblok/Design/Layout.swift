import SwiftUI

/// De breedte die het werkvlak naast de zijbalk overhoudt. Het ontwerp is
/// getekend op 1194 × 834 liggend; staand blijft er ruim 400 pt minder over,
/// en dan moeten kolommen onder elkaar in plaats van naast elkaar.
private struct ContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 980
}

extension EnvironmentValues {
    var contentWidth: CGFloat {
        get { self[ContentWidthKey.self] }
        set { self[ContentWidthKey.self] = newValue }
    }

    /// Staand op iPad, of een smal venster in Split View: kolommen stapelen.
    var isNarrow: Bool { contentWidth < 720 }

    /// iPhone of een derde van het scherm: geen zijbalk meer, en blokken
    /// die op een iPad naast elkaar staan gaan hier altijd onder elkaar.
    var isCompact: Bool { contentWidth < 560 }
}

/// Twee blokken naast elkaar als het past, onder elkaar als het niet past.
/// De scheidslijn draait mee: verticaal naast elkaar, horizontaal eronder.
struct AdaptiveSplit<Leading: View, Trailing: View>: View {
    /// Breedte van het tweede blok als beide naast elkaar staan.
    /// `nil` verdeelt de ruimte gelijk.
    var trailingWidth: CGFloat?
    /// Verhouding van het eerste blok bij een gelijke verdeling.
    var leadingFraction: CGFloat?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.isNarrow) private var isNarrow
    @Environment(\.contentWidth) private var contentWidth

    var body: some View {
        if isNarrow || contentWidth < 560 {
            VStack(spacing: 0) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Hairline()
                trailing()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                leading()
                    .frame(maxWidth: leadingFraction.map { contentWidth * $0 } ?? .infinity,
                           alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(M.hairline).frame(width: 1)
                    }
                trailing()
                    .frame(maxWidth: trailingWidth ?? .infinity, alignment: .leading)
            }
        }
    }
}

/// De rondleiding opnieuw openen, vanaf elke plek die er een knop voor heeft.
private struct OpenTourKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openTour: () -> Void {
        get { self[OpenTourKey.self] }
        set { self[OpenTourKey.self] = newValue }
    }
}
