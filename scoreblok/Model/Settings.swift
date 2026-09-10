import Foundation
import SwiftUI

/// De handvol keuzes die echt iets veranderen aan hoe je speelt. Alles wat
/// bij één spel hoort staat in het sjabloon, niet hier.
enum SettingsKey {
    /// Vraagt na de laatste speler of de ronde afgesloten mag worden.
    static let confirmRoundEnd = "instelling.bevestigRonde"
    /// De periode waarop het statistiekenscherm opent.
    static let statsPeriod = "instelling.statistiekPeriode"
    /// Afgebroken potjes tussen de rest in de geschiedenis.
    static let showAbandoned = "instelling.toonAfgebroken"
    /// Potjes en spelers doorgeven aan de zoekfunctie van het systeem.
    static let spotlight = "instelling.spotlight"
    /// Is de rondleiding een keer afgerond of overgeslagen?
    static let onboarded = "instelling.rondleidingGezien"
    /// Staat er een verzoek open om de tips weer te tonen?
    static let tipsReset = "instelling.tipsHerstellen"
    /// De stand van het lopende potje op het toegangsscherm en in het Dynamic Island.
    static let liveActivity = "instelling.liveActivity"
    /// Een kort verslag van Apple Intelligence onder de eindstand.
    static let matchReport = "instelling.verslag"
    /// Bij welk aantal potjes er voor het laatst om een beoordeling is gevraagd.
    static let reviewAskedAt = "instelling.beoordelingGevraagd"
}

extension StatsPeriod {
    /// De periode uit de instellingen, met 90 dagen als terugval.
    static var preferred: StatsPeriod {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.statsPeriod)
        return raw.flatMap(StatsPeriod.init(rawValue:)) ?? .days90
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "onbekend"
    }
}
