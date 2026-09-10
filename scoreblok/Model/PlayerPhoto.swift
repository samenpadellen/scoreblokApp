import Foundation
import SwiftData
import SwiftUI
import UIKit
import Vision

/// De profielfoto van een speler. Een eigen tabel in plaats van een veld op
/// de speler: zo blijft de speler zelf onveranderd en is de migratie net zo
/// licht als die van de speelgroepen. De foto zelf staat buiten de database
/// en gaat via iCloud mee als los bestand.
@Model
final class PlayerPhoto {
    var id: UUID = UUID()
    var playerID: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var updatedAt: Date = Date.now

    init(playerID: UUID, imageData: Data, updatedAt: Date = .now) {
        self.id = UUID()
        self.playerID = playerID
        self.imageData = imageData
        self.updatedAt = updatedAt
    }
}

/// Alle profielfoto's als kleine plaatjes in het geheugen, zodat een lijst
/// met spelers niet bij elke regel de database in hoeft. Staan er door
/// synchroniseren twee foto's voor één speler, dan wint de nieuwste; dat
/// kiest elk apparaat hetzelfde.
@MainActor
@Observable
final class PhotoBook {
    static let shared = PhotoBook()

    private(set) var images: [UUID: UIImage] = [:]
    @ObservationIgnored private var stamps: [UUID: Date] = [:]

    func image(for playerID: UUID) -> UIImage? { images[playerID] }

    /// Leest de foto's opnieuw in. Alleen wat veranderde wordt opnieuw
    /// gedecodeerd, en dat gebeurt buiten de hoofdthread.
    func reload(_ photos: [PlayerPhoto]) {
        let newest = Self.newest(photos)
        var changed: [(UUID, Date, Data)] = []
        for (playerID, photo) in newest where stamps[playerID] != photo.updatedAt {
            if let data = photo.imageData { changed.append((playerID, photo.updatedAt, data)) }
        }
        for gone in Set(images.keys).subtracting(newest.keys) {
            images[gone] = nil
            stamps[gone] = nil
        }
        guard !changed.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            var decoded: [(UUID, Date, UIImage)] = []
            for (playerID, stamp, data) in changed {
                if let image = PhotoProcessing.thumbnail(from: data) {
                    decoded.append((playerID, stamp, image))
                }
            }
            let finished = decoded
            await MainActor.run {
                for (playerID, stamp, image) in finished {
                    self.images[playerID] = image
                    self.stamps[playerID] = stamp
                }
            }
        }
    }

    /// De bewaarde foto van een speler, als bestand.
    func storedData(for playerID: UUID, in context: ModelContext) -> Data? {
        let photos = (try? context.fetch(FetchDescriptor<PlayerPhoto>(
            predicate: #Predicate { $0.playerID == playerID }))) ?? []
        return Self.newest(photos)[playerID]?.imageData
    }

    /// Zet of wist de foto van een speler. Eén foto per speler: oudere
    /// exemplaren gaan weg.
    func setPhoto(_ data: Data?, for playerID: UUID, in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<PlayerPhoto>(
            predicate: #Predicate { $0.playerID == playerID }))) ?? []
        for photo in existing { context.delete(photo) }
        if let data {
            context.insert(PlayerPhoto(playerID: playerID, imageData: data))
            images[playerID] = PhotoProcessing.thumbnail(from: data)
            stamps[playerID] = .now
        } else {
            images[playerID] = nil
            stamps[playerID] = nil
        }
        Storage.save(context)
    }

    static func newest(_ photos: [PlayerPhoto]) -> [UUID: PlayerPhoto] {
        var result: [UUID: PlayerPhoto] = [:]
        for photo in photos where !photo.isDeleted && photo.imageData != nil {
            if let current = result[photo.playerID] {
                let newer = photo.updatedAt > current.updatedAt
                    || (photo.updatedAt == current.updatedAt && photo.id.uuidString < current.id.uuidString)
                if newer { result[photo.playerID] = photo }
            } else {
                result[photo.playerID] = photo
            }
        }
        return result
    }
}

/// Van een willekeurige foto naar een vierkant portret. Vision zoekt het
/// gezicht, zodat een groepsfoto of een foto op armlengte vanzelf goed
/// wordt uitgesneden.
enum PhotoProcessing {
    nonisolated static let side: CGFloat = 512

    nonisolated static func thumbnail(from data: Data) -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 240, height: 240))
    }

    nonisolated static func portrait(from data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return await portrait(from: image)
    }

    nonisolated static func portrait(from image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let upright = upright(image)
            guard let cgImage = upright.cgImage else { return nil }
            let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
            let crop = square(around: largestFace(in: cgImage), width: width, height: height)
            guard let cropped = cgImage.cropping(to: crop) else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
                .image { _ in
                    UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
                }
            return rendered.jpegData(compressionQuality: 0.82)
        }.value
    }

    /// Het grootste gezicht, in pixels met de oorsprong linksboven.
    private nonisolated static func largestFace(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: {
                  $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
              }) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let box = face.boundingBox
        return CGRect(x: box.minX * width,
                      y: (1 - box.maxY) * height,
                      width: box.width * width,
                      height: box.height * height)
    }

    /// Een vierkant rond het gezicht met ruimte voor haar en schouders, of
    /// het midden van de foto als er geen gezicht is.
    private nonisolated static func square(around face: CGRect?, width: CGFloat, height: CGFloat) -> CGRect {
        let limit = min(width, height)
        guard let face else {
            return CGRect(x: (width - limit) / 2, y: (height - limit) / 2, width: limit, height: limit)
        }
        let size = min(limit, max(face.width, face.height) * 2.4)
        // Iets boven het midden van het gezicht, zodat de kin niet tegen de rand zit.
        var x = face.midX - size / 2
        var y = face.midY - size * 0.46
        x = min(max(0, x), width - size)
        y = min(max(0, y), height - size)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.rounded(), height: size.rounded())
    }

    private nonisolated static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
