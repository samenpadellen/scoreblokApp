import SwiftUI
import TipKit

/// De tips van Apple zelf: TipKit. Ze verschijnen één keer, bij de knop waar
/// ze over gaan, en verdwijnen zodra je ze hebt gezien. De rondleiding legt
/// uit waar iets staat; deze tips leggen uit wat een knop doet op het moment
/// dat je er echt voor staat.
enum AppTips {
    /// Tips horen pas te verschijnen als de rondleiding voorbij is. Anders
    /// staat er een tip dwars over de uitleg heen van precies datzelfde ding.
    @Parameter static var ready: Bool = false

    /// Bij de start. Een verzoek om de tips terug te zetten moet vóór
    /// `Tips.configure` worden afgehandeld — dat schrijft Apple voor — dus
    /// gebeurt het hier, bij de eerstvolgende start.
    static func configure() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SettingsKey.tipsReset) {
            try? Tips.resetDatastore()
            defaults.set(false, forKey: SettingsKey.tipsReset)
        }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    /// Zet klaar dat alle tips weer mogen verschijnen.
    static func requestReset() {
        UserDefaults.standard.set(true, forKey: SettingsKey.tipsReset)
    }

    /// De voorwaarde die elke tip deelt.
    static var readyRule: [Tips.Rule] { [#Rule(Self.$ready) { $0 == true }] }
}

/// Bij de balk onderin. De minst vanzelfsprekende plek in de app: dat een
/// onderbroken potje blijft staan is precies wat mensen niet verwachten.
struct ResumeTip: Tip {
    var title: Text { Text("Je potje loopt nog") }
    var message: Text? {
        Text("Tik op de balk om verder te tellen. Hij blijft staan tot je het potje afrondt, ook dagen later.")
    }
    var image: Image? { Image(systemName: "arrow.right.circle") }
    var rules: [Tips.Rule] { AppTips.readyRule }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Bij het ongedaan maken. Mensen tellen door en durven niet te corrigeren.
struct UndoTip: Tip {
    var title: Text { Text("Verkeerd getikt?") }
    var message: Text? {
        Text("Ongedaan maken haalt de laatste invoer weg, zo vaak als je wilt, zolang het potje loopt.")
    }
    var image: Image? { Image(systemName: "arrow.uturn.backward") }
    var rules: [Tips.Rule] { AppTips.readyRule }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Bij de spellenkast. Zonder uitleg lijkt het op verwijderen.
struct CupboardTip: Tip {
    var title: Text { Text("Te veel spellen in beeld?") }
    var message: Text? {
        Text("Zet wat je niet speelt in de spellenkast. Je raakt niets kwijt — de cijfers blijven staan en je haalt het er zo weer uit.")
    }
    var image: Image? { Image(systemName: "archivebox") }
    var rules: [Tips.Rule] { AppTips.readyRule }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Bij de jokerteller, vóór het potje. Achteraf aanzetten kan niet meer, en
/// dat is het soort ding dat je één keer wilt weten.
struct JokerTip: Tip {
    var title: Text { Text("Jokers meetellen?") }
    var message: Text? {
        Text("Zet dit aan vóór je begint. Tijdens het potje ligt het vast, zodat alle rondes op dezelfde manier geteld worden.")
    }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Tips.Rule] { AppTips.readyRule }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
