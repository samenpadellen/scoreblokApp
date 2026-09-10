import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import MultipeerConnectivity
import UIKit

/// De ruwe verbinding tussen twee apparaten in de buurt. Het apparaat met de
/// QR-code maakt zich vindbaar; het andere zoekt en nodigt uit met de code
/// uit de QR-code. Alleen die uitnodiging wordt aangenomen, en de verbinding
/// is versleuteld. Draait buiten de main actor en meldt alles via `onEvent`.
final class SamenLink: NSObject, @unchecked Sendable {
    enum Event: Sendable {
        case connected(String)
        case disconnected
        case received(Data)
        case failed(String)
    }

    var onEvent: (@Sendable (Event) -> Void)?

    private let peer: MCPeerID
    private let session: MCSession
    private let token: Data
    private let discoveryHash: String
    private let lock = NSLock()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invited = false
    private var accepted = false
    private var everConnected = false

    init(displayName: String, invite: SamenInvite) {
        peer = MCPeerID(displayName: String(displayName.prefix(30)))
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        token = Data(invite.token.utf8)
        discoveryHash = invite.discoveryHash
        super.init()
        session.delegate = self
    }

    func host() {
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["h": discoveryHash],
                                                   serviceType: Samen.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    func join() {
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Samen.serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    func send(_ frames: [Data]) throws {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { throw CocoaError(.featureUnsupported) }
        for frame in frames {
            try session.send(frame, toPeers: peers, with: .reliable)
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }
}

extension SamenLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        lock.lock()
        let welcome = context == token && !accepted
        if welcome { accepted = true }
        lock.unlock()
        invitationHandler(welcome, welcome ? session : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        onEvent?(.failed("Dit apparaat kon zich niet vindbaar maken. Sta Scoreblok toe het lokale netwerk te gebruiken (Instellingen › Privacy en beveiliging › Lokaal netwerk)."))
    }
}

extension SamenLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard info?["h"] == discoveryHash else { return }
        lock.lock()
        let first = !invited
        invited = true
        lock.unlock()
        guard first else { return }
        browser.invitePeer(peerID, to: session, withContext: token, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        onEvent?(.failed("Zoeken naar het andere apparaat lukte niet. Sta Scoreblok toe het lokale netwerk te gebruiken (Instellingen › Privacy en beveiliging › Lokaal netwerk)."))
    }
}

extension SamenLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            lock.lock(); everConnected = true; lock.unlock()
            onEvent?(.connected(peerID.displayName))
        case .notConnected:
            lock.lock()
            let retry = !everConnected && browser != nil
            if retry { invited = false }
            lock.unlock()
            if retry {
                // Uitnodiging mislukt voordat er verbinding was: opnieuw zoeken.
                browser?.stopBrowsingForPeers()
                browser?.startBrowsingForPeers()
            } else {
                onEvent?(.disconnected)
            }
        default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onEvent?(.received(data))
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                 fromPeer peerID: MCPeerID) {}
}

// MARK: - Het verloop

/// Van QR-code tot samengevoegd. Beide apparaten doorlopen hetzelfde:
/// verbinden, kiezen wie meedoet, versturen, dan wie-is-wie en samenvoegen.
@MainActor
@Observable
final class SamenModel {
    enum Role: Equatable {
        case host
        case guest
    }

    enum Step: Equatable {
        case connecting
        case connected
        case waitingForOther
        case review
        case merging
        case done(SamenExchange.Outcome)
        case failed(String)
    }

    let role: Role
    let deviceName: String
    private(set) var invite: SamenInvite
    private(set) var qrImage: UIImage?
    private(set) var step: Step = .connecting
    private(set) var peerName: String?
    private(set) var received: SamenPayload?
    private(set) var receivedCount = 0
    private(set) var sent = false
    var members: Set<UUID> = []
    var choices: [UUID: SamenExchange.Choice] = [:]
    var groupName = ""

    @ObservationIgnored private var link: SamenLink?
    @ObservationIgnored private var pending: SamenPayload?
    @ObservationIgnored private var frames: [Int: Data] = [:]

    init(role: Role, invite: SamenInvite, deviceName: String) {
        self.role = role
        self.invite = invite
        self.deviceName = deviceName
        if role == .host { qrImage = QRCode.image(for: invite.url.absoluteString) }
    }

    func start() {
        let link = SamenLink(displayName: deviceName, invite: invite)
        link.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.link = link
        if role == .host { link.host() } else { link.join() }
    }

    func stop() {
        link?.onEvent = nil
        link?.stop()
        link = nil
    }

    /// Andere speelgroep kiezen kan alleen zolang er nog geen verbinding is.
    func changeGroup(to id: UUID) {
        guard peerName == nil, role == .host else { return }
        invite = SamenInvite(token: invite.token, groupID: id, hostName: invite.hostName)
        qrImage = QRCode.image(for: invite.url.absoluteString)
    }

    func proceed(with payload: SamenPayload) {
        pending = payload
        sendIfReady()
    }

    func fail(_ message: String) { step = .failed(message) }
    func beginMerge() { step = .merging }

    func finish(_ outcome: SamenExchange.Outcome) {
        step = .done(outcome)
        stop()
    }

    private func handle(_ event: SamenLink.Event) {
        switch event {
        case .connected(let name):
            peerName = name
            if step == .connecting { step = .connected }
            sendIfReady()

        case .disconnected:
            switch step {
            case .review, .merging, .done, .failed:
                break
            default:
                step = .failed("De verbinding viel weg. Houd de apparaten bij elkaar in de buurt en probeer het opnieuw.")
            }

        case .received(let data):
            guard let frame = SamenWire.frame(data) else { return }
            frames[frame.index] = frame.body
            guard frames.count == frame.total else { return }
            let bodies = (0..<frame.total).compactMap { frames[$0] }
            frames = [:]
            do {
                let payload = try SamenWire.unpack(bodies)
                guard payload.protocolVersion == Samen.protocolVersion else {
                    step = .failed("De andere Scoreblok is een andere versie. Werk allebei bij naar de nieuwste versie.")
                    return
                }
                received = payload
                receivedCount += 1
                if sent { step = .review }
            } catch {
                step = .failed("De gegevens kwamen niet goed aan. Probeer het opnieuw.")
            }

        case .failed(let message):
            step = .failed(message)
        }
    }

    private func sendIfReady() {
        guard !sent, peerName != nil, let pending, let link else { return }
        do {
            try link.send(SamenWire.pack(pending))
            sent = true
            step = received == nil ? .waitingForOther : .review
        } catch {
            step = .failed("Versturen lukte niet: \(error.localizedDescription)")
        }
    }
}

/// QR-code in harde pixels, zonder vervaging bij het vergroten.
enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
