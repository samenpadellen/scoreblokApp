import CloudKit
import CoreData
import Foundation
import SwiftUI

/// Wat iCloud werkelijk doet. Dat een container opengaat zegt niets: SwiftData
/// zet de winkel ook op zonder ingelogd account en synchroniseert dan gewoon
/// niet. Daarom kijken we naar de accountstatus én naar de synchronisatie zelf.
@MainActor
@Observable
final class CloudStatus {

    enum Account: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case unavailable(String)

        var isAvailable: Bool { self == .available }

        var summary: String {
            switch self {
            case .unknown: "Nog niet gecontroleerd"
            case .available: "Ingelogd bij iCloud"
            case .noAccount: "Niet ingelogd bij iCloud"
            case .restricted: "iCloud is geblokkeerd op dit apparaat"
            case .unavailable(let reason): reason
            }
        }
    }

    /// Wat er als laatste met de synchronisatie gebeurde.
    struct Sync: Equatable {
        var kind: String
        var succeeded: Bool
        var at: Date
        var error: String?
    }

    @MainActor static let shared = CloudStatus()

    private(set) var account: Account = .unknown
    private(set) var lastSync: Sync?
    /// Wanneer iCloud voor het laatst met succes gegevens ophaalde.
    private(set) var lastImportAt: Date?
    /// Of er gekozen is voor iCloud en die opslag openging.
    private(set) var containerIsCloud = false

    /// Na elke gelukte ophaalronde; daarna ruimt de app dubbelingen op.
    @ObservationIgnored var onImport: (@MainActor () -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // MARK: - Samenvatting voor de interface

    /// Volgt de keuze, niet het account. Wie iCloud koos en niet is
    /// ingelogd, staat op iCloud dat niet werkt — niet op lokaal.
    var title: String { containerIsCloud ? "iCloud" : "Lokaal" }

    var detail: String {
        guard containerIsCloud else { return "Alleen op dit apparaat" }
        switch account {
        case .unknown:
            return "iCloud wordt gecontroleerd"
        case .available:
            if let lastSync {
                if lastSync.succeeded {
                    return "Bijgewerkt \(lastSync.at.formatted(.dateTime.hour().minute()))"
                }
                return lastSync.error ?? "De laatste synchronisatie ging mis"
            }
            return "Synchroniseert met je andere apparaten"
        default:
            return "\(account.summary) · er wordt niets gesynchroniseerd"
        }
    }

    var isHealthy: Bool {
        guard containerIsCloud else { return true }
        switch account {
        case .unknown: return true
        case .available: return lastSync?.succeeded ?? true
        default: return false
        }
    }

    // MARK: - Bijhouden

    /// Mag vaker worden aangeroepen: bij elke nieuwe opslag opnieuw.
    @MainActor
    func start(containerIsCloud: Bool) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        self.containerIsCloud = containerIsCloud
        refresh()
        guard containerIsCloud else { return }

        // Uitloggen of van account wisselen merken we zonder herstart.
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })

        // De echte synchronisatie: opzetten, ophalen en wegschrijven.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let event = note.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                      event.endDate != nil else { return }
                Task { @MainActor [weak self] in self?.record(event) }
            })
    }

    /// Controleert het account, ook als de app lokaal draait: het keuzescherm
    /// en de overstap moeten weten of iCloud kan.
    @MainActor
    func refresh() {
        Task { await checkAccount() }
    }

    @MainActor
    @discardableResult
    func checkAccount() async -> Bool {
        do {
            let status = try await CKContainer(identifier: Storage.cloudContainerID).accountStatus()
            account = switch status {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .temporarilyUnavailable: .unavailable("iCloud is tijdelijk niet bereikbaar")
            default: .unavailable("Status van iCloud onbekend")
            }
        } catch {
            account = .unavailable(error.localizedDescription)
        }
        return account.isAvailable
    }

    /// Een foutcode zegt de gebruiker niets. De bekende gevallen in gewone taal.
    private static func explain(_ error: any Error, kind: String) -> String {
        switch (error as NSError).code {
        case 134400:
            // Het iCloud-account ontbreekt of is niet bruikbaar voor CloudKit.
            "iCloud-account niet beschikbaar · er wordt niets gesynchroniseerd"
        default:
            "Synchroniseren (\(kind)) ging mis: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let kind = switch event.type {
        case .setup: "opzetten"
        case .import: "ophalen"
        case .export: "wegschrijven"
        @unknown default: "synchroniseren"
        }
        lastSync = Sync(kind: kind,
                        succeeded: event.succeeded,
                        at: event.endDate ?? .now,
                        error: event.error.map { Self.explain($0, kind: kind) })
        if event.type == .import, event.succeeded {
            lastImportAt = event.endDate ?? .now
            onImport?()
        }
    }
}
