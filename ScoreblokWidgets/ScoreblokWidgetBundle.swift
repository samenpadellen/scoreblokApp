import SwiftUI
import WidgetKit

@main
struct ScoreblokWidgetBundle: WidgetBundle {
    var body: some Widget {
        StandingsWidget()
        LiveScoreActivity()
        controls
    }

    /// Knoppen in het Bedieningspaneel bestaan pas vanaf iOS 18; op oudere
    /// versies blijft de rest van de widgets gewoon werken.
    @WidgetBundleBuilder
    private var controls: some Widget {
        if #available(iOS 18.0, *) {
            NewMatchControl()
            StandingsControl()
        }
    }
}
