import SwiftUI
import UIKit

/// Afbeeldingen van spellen. Je levert ze zelf aan: één bestand per spel in
/// `scoreblok/Resources/Spelafbeeldingen`, met de naam van het spel als
/// bestandsnaam in kleine letters en koppeltekens ("Ticket to Ride Europe"
/// wordt `ticket-to-ride-europe.jpg`). Is er geen bestand, dan toont de app
/// het monogram, zoals altijd.
///
/// Werkt ook voor eigen spellen: noem het bestand naar het spel.
enum GameArtwork {
    static let extensions = ["jpg", "jpeg", "png", "webp", "heic"]

    /// Groot genoeg voor de grootste plek waar een afbeelding staat, klein
    /// genoeg om een lange lijst niet traag te maken.
    private static let thumbnailSide: CGFloat = 256

    @MainActor private static var cache: [String: UIImage?] = [:]

    /// "Mens Erger Je Niet" → "mens-erger-je-niet".
    static func fileName(for gameName: String) -> String {
        let folded = gameName
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "nl_NL"))
            .lowercased()
        var slug = ""
        var pendingDash = false
        for character in folded {
            if character.isLetter || character.isNumber {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                slug.append(character)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return slug
    }

    @MainActor
    static func image(for gameName: String) -> UIImage? {
        let key = fileName(for: gameName)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }

        let url = extensions.lazy
            .compactMap { Bundle.main.url(forResource: key, withExtension: $0) }
            .first
        let found = url
            .flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
            .map(thumbnail)
        cache[key] = found
        return found
    }

    private static func thumbnail(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > thumbnailSide else { return image }
        let scale = thumbnailSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: size) ?? image
    }
}
