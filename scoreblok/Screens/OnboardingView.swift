import SwiftUI

/// De rondleiding bij de eerste start. De app heeft veel in zich — elf
/// spellen, een spellenkast, tussentijds opslaan, statistieken, widgets — en
/// zonder uitleg is niet te zien wat waar zit. Vijf pagina's, elk met één
/// gedachte, en aan het eind twee knoppen die echt ergens heen gaan.
///
/// Dezelfde vijf pagina's op iPhone en iPad. Breed staan tekst en tekening
/// naast elkaar, smal onder elkaar; de inhoud verandert niet mee, want dan
/// zou de een minder leren dan de ander.
struct OnboardingView: View {
    /// Wat de gebruiker aan het eind kiest.
    enum Exit { case players, games, none }

    let onFinish: (Exit) -> Void

    @State private var index = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    private var pages: [OnboardingPage] { OnboardingPage.all }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                HeavyRule()
                pager(width: proxy.size.width)
                HeavyRule()
                footer
            }
            .background(M.paper)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Kop

    private var header: some View {
        HStack(spacing: 10) {
            Wordmark(size: 15, markSize: 24)
            Spacer(minLength: 8)
            Text("\(String(format: "%02d", index + 1)) / \(String(format: "%02d", pages.count))")
                .font(M.font(11, .semiBold))
                .tracking(em: 0.1, size: 11)
                .foregroundStyle(M.inkAlpha(0.55))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: - De pagina's

    private func pager(width: CGFloat) -> some View {
        TabView(selection: $index) {
            ForEach(Array(pages.enumerated()), id: \.offset) { position, page in
                OnboardingPageView(page: page, width: width)
                    .tag(position)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Voet

    private var footer: some View {
        HStack(spacing: 12) {
            if isLast {
                OutlineButton(title: "Bekijk de spellen") { onFinish(.games) }
                SolidButton(title: "Spelers toevoegen") { onFinish(.players) }
            } else {
                Button {
                    onFinish(.none)
                } label: {
                    Text("Overslaan")
                        .font(M.font(12.5, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .frame(minHeight: M.tap)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)
                progress
                Spacer(minLength: 8)

                SolidButton(title: "Verder") {
                    withAnimation(.snappy(duration: 0.25)) { index += 1 }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: isLast ? .trailing : .leading)
    }

    private var isLast: Bool { index == pages.count - 1 }

    /// Streepjes in plaats van bolletjes: het ontwerp kent geen ronde hoeken.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<pages.count, id: \.self) { spot in
                Rectangle()
                    .fill(spot <= index ? M.ink : M.inkAlpha(0.18))
                    .frame(width: spot == index ? 20 : 10, height: 3)
                    .animation(.snappy(duration: 0.25), value: index)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Pagina \(index + 1) van \(pages.count)")
    }
}

// MARK: - Eén pagina

struct OnboardingPage {
    let kicker: String
    let title: String
    let body: String
    /// Drie korte regels: waar het staat, niet wat het is.
    let points: [String]
    let art: Art

    enum Art { case mark, games, board, resume, stats }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            kicker: "Welkom",
            title: "Punten bijhouden,\nen daarna weten\nwat het waard was.",
            body: "Scoreblok houdt de telling bij aan tafel en onthoudt wat er is gebeurd. Geen losse blaadjes meer, en na een half jaar zie je nog steeds wie er wint.",
            points: ["Elf spellen klaar, en zeventien in de spellenkast",
                     "Je hoeft niets in te stellen om te beginnen",
                     "Alles blijft op je eigen apparaten"],
            art: .mark),
        OnboardingPage(
            kicker: "Spelen",
            title: "Kies een spel,\nzet de spelers klaar.",
            body: "Onder Spelen staat alles wat je kunt spelen. Wat je nooit speelt zet je in de spellenkast, zodat het overzicht kort blijft. Staat jouw spel er niet bij, dan maak je het onder Eigen spel.",
            points: ["Spelen · alle spellen en de spellenkast",
                     "Spelers · namen, foto's en hun cijfers",
                     "Eigen spel · zelf de regels bepalen"],
            art: .games),
        OnboardingPage(
            kicker: "Tellen",
            title: "Eén ronde tegelijk,\nmet grote toetsen.",
            body: "Je vult per speler in en gaat door naar de volgende ronde. Vergist? Ongedaan maken staat ernaast. Bij Jokeren telt het aantal kaarten dat je overhoudt, en de jokerteller kun je vóór het potje aanzetten.",
            points: ["Grote toetsen, ook staand op een iPhone",
                     "Ongedaan maken zolang het potje loopt",
                     "Een bevestiging voordat de ronde sluit"],
            art: .board),
        OnboardingPage(
            kicker: "Onderbreken",
            title: "Een potje hoeft\nniet af.",
            body: "Leg de iPad weg en ga morgen verder. Zolang er een potje loopt blijft er onderin een balk staan die je er in één tik weer in zet, ook vanaf een ander tabblad.",
            points: ["Alles wordt bewaard zodra je iets invult",
                     "De balk onderin en je toegangsscherm brengen je terug",
                     "Een potje afbreken kan ook, dat telt niet mee"],
            art: .resume),
        OnboardingPage(
            kicker: "Terugkijken",
            title: "Wie wint er nou\neigenlijk?",
            body: "Statistieken toont winstpercentages, kop-tot-kop en records over de periode die je kiest. In Geschiedenis staat elk potje terug, en een scorekaart deel je als pdf.",
            points: ["Statistieken · trends en onderlinge balans",
                     "Geschiedenis · elk potje, met scorekaart",
                     "Instellingen · opslag, reservekopie en speelgroepen"],
            art: .stats)
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let width: CGFloat

    /// Naast elkaar zodra er een kolom naast past.
    private var wide: Bool { width >= 700 }
    /// Een 13-inch iPad heeft zoveel ruimte dat het ontwerp op de maat van
    /// een iPhone eenzaam in het wit komt te staan.
    private var roomy: Bool { width >= 1000 }
    private var titleSize: CGFloat { roomy ? 40 : (wide ? 32 : 26) }

    var body: some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: 0) {
                    // Links de woorden, verticaal gecentreerd zodat ze op
                    // ooghoogte staan met de tekening ernaast.
                    words
                        .frame(maxWidth: roomy ? 580 : 520, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .leading)
                    Rectangle().fill(M.hairline).frame(width: 1)
                    OnboardingArt(kind: page.art, span: roomy ? 380 : 300)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        OnboardingArt(kind: page.art, fills: false)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        words
                    }
                }
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.kicker.uppercased())
                .font(M.font(10, .semiBold))
                .tracking(em: 0.14, size: 10)
                .foregroundStyle(M.red)
                .padding(.bottom, 14)

            Text(page.title)
                .font(M.font(titleSize, .extraBold))
                .tracking(em: -0.025, size: titleSize)
                .foregroundStyle(M.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Text(page.body)
                .font(M.font(roomy ? 15.5 : 14, .regular))
                .foregroundStyle(M.inkAlpha(0.72))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.points.enumerated()), id: \.offset) { spot, point in
                    if spot > 0 { Hairline() }
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(M.red)
                            .frame(width: 7, height: 2)
                            .padding(.top, 8)
                        Text(point)
                            .font(M.font(roomy ? 13.5 : 12.5, .semiBold))
                            .foregroundStyle(M.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(M.ruleHeavy).frame(height: 2) }
            .padding(.top, 2)

            if !wide { Spacer(minLength: 12) }
        }
        .padding(.horizontal, wide ? 40 : 20)
        .padding(.vertical, wide ? 30 : 22)
    }
}
