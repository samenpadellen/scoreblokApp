import SwiftUI
import SwiftData

@main
struct ScoreblokApp: App {
    @State private var store = StoreController.shared

    init() {
        // Het keuzescherm gebruikt Archivo al vóórdat RootView bestaat.
        ArchivoFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            StoreGate(store: store)
                .preferredColorScheme(.light)
                .tint(M.red)
        }
    }
}

/// Wat er op het scherm staat hangt af van de opslag: nog geen keuze, bezig
/// met overstappen, of klaar voor gebruik.
struct StoreGate: View {
    let store: StoreController

    var body: some View {
        ZStack {
            if let container = store.container {
                RootView()
                    .modelContainer(container)
                    .id(store.generation)
                // Bij een overstap naar iCloud hangt de weergave al aan de
                // nieuwe opslag terwijl de potjes er nog in gaan. Het
                // voortgangsscherm ligt er dan overheen, zodat niemand er
                // tussendoor iets aan verandert.
                if store.phase.isWorking {
                    StorageWorkingView(step: store.phase.step)
                }
            } else if store.phase == .choosing {
                StorageChoiceView(store: store)
            } else {
                StorageWorkingView(step: store.phase.step)
            }
        }
        .environment(store)
        .overlay(alignment: .top) {
            if let notice = store.notice {
                StorageNoticeBanner(notice: notice) { store.notice = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: store.notice)
    }
}
