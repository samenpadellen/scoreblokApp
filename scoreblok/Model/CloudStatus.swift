import CloudKit
import CoreData
import Foundation
import SwiftUI

/// Wat iCloud werkelijk doet. Dat een container opengaat zegt niets: SwiftData
/// zet de winkel ook op zonder ingelogd account en synchroniseert dan gewoon
/// niet. Daarom kijken we naar de accountstatus én naar de synchronisatie zelf.
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
    /// Of de app überhaupt met een iCloud-winkel is gestart.
    private(set) var containerIsCloud = false

    private var observers: [NSObjectProtocol] = []

    // MARK: - Samenvatting voor de interface

    var title: String {
        guard containerIsCloud else { return "Lokaal" }
        return account.isAvailable ? "iCloud" : "Lokaal"
    }

    var detail: String {
        guard containerIsCloud else { return "Alleen op dit apparaat" }
        guard account.isAvailable else { return account.summary }
        if let lastSync {
            if lastSync.succeeded {
                return "Bijgewerkt \(lastSync.at.formatted(.dateTime.hour().minute()))"
            }
            return lastSync.error ?? "De laatste synchronisatie ging mis"
        }
        return "Synchroniseert met je andere apparaten"
    }

    var isHealthy: Bool {
        guard containerIsCloud, account.isAvailable else { return false }
        return lastSync?.succeeded ?? true
    }

    // MARK: - Bijhouden

    @MainActor
    func start(containerIsCloud: Bool) {
        self.containerIsCloud = containerIsCloud
        guard containerIsCloud else { return }

        refresh()

        // Uitloggen of van account wisselen merken we zonder herstart.
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })

        // De echte synchronisatie: opzetten, ophalen en wegschrijven.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let event = note.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                      event.endDate != nil else { return }
                Task { @MainActor in self?.record(event) }
            })
    }

    @MainActor
    func refresh() {
        guard containerIsCloud else { return }
        CKContainer(identifier: Storage.cloudContainerID).accountStatus { [weak self] status, error in
            Task { @MainActor in
                self?.account = switch status {
                case .available: .available
                case .noAccount: .noAccount
                case .restricted: .restricted
                case .temporarilyUnavailable:
                    .unavailable("iCloud is tijdelijk niet bereikbaar")
                default:
                    .unavailable(error?.localizedDescription ?? "Status onbekend")
                }
            }
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
                        error: event.error.map { "Synchroniseren (\(kind)) ging mis: \($0.localizedDescription)" })
    }
}
