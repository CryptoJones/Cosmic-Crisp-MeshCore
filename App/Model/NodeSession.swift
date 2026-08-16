import Foundation
import Observation
import MeshCoreKit

/// App-facing state for the connected node. Owns the `MeshCoreClient`, keeps
/// the contact list and message log, and drains pushes into UI state.
@MainActor
@Observable
final class NodeSession {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    struct LoggedMessage: Identifiable, Equatable {
        let id = UUID()
        let received: Date
        let message: ReceivedMessage
        var senderName: String?
    }

    private(set) var status: Status = .disconnected
    private(set) var selfInfo: SelfInfo?
    private(set) var deviceInfo: DeviceInfo?
    private(set) var battery: BatteryInfo?
    private(set) var contacts: [Contact] = []
    private(set) var messages: [LoggedMessage] = []
    private(set) var customVars: [String: String] = [:]
    private(set) var lastError: String?

    var gpsEnabled: Bool { customVars["gps"] == "1" }
    var transportDescription: String { TransportFactory.description }

    private var client: MeshCoreClient?
    private var pushTask: Task<Void, Never>?

    func connect() async {
        guard client == nil else { return }
        status = .connecting
        do {
            let transport = try await TransportFactory.make()
            let c = MeshCoreClient(transport: transport)
            await c.start()
            client = c
            selfInfo = try await c.appStart()
            deviceInfo = try? await c.deviceInfo()
            battery = try? await c.battery()
            customVars = (try? await c.customVars()) ?? [:]
            contacts = (try? await c.contacts()) ?? []
            status = .connected
            pushTask = Task { [weak self] in
                for await push in c.pushes { await self?.handle(push) }
            }
            await drainMessages()
        } catch {
            status = .failed("\(error)")
            lastError = "\(error)"
        }
    }

    func disconnect() async {
        pushTask?.cancel()
        await client?.stop()
        client = nil
        status = .disconnected
    }

    func refreshContacts() async {
        guard let client else { return }
        contacts = (try? await client.contacts()) ?? contacts
    }

    func refreshBattery() async {
        guard let client else { return }
        battery = try? await client.battery()
    }

    func setGPS(_ on: Bool) async {
        guard let client else { return }
        do {
            try await client.setGPS(enabled: on)
            customVars = (try? await client.customVars()) ?? customVars
        } catch { lastError = "\(error)" }
    }

    func setName(_ name: String) async {
        guard let client else { return }
        do {
            try await client.setName(name)
            selfInfo = try await client.appStart()
        } catch { lastError = "\(error)" }
    }

    func sendAdvert(flood: Bool) async {
        guard let client else { return }
        do { try await client.sendAdvert(flood: flood) } catch { lastError = "\(error)" }
    }

    func send(text: String, to contact: Contact) async {
        guard let client else { return }
        do { _ = try await client.sendMessage(to: contact.publicKey, text: text) }
        catch { lastError = "\(error)" }
    }

    func send(text: String, channel: UInt8) async {
        guard let client else { return }
        do { try await client.sendChannelMessage(channel: channel, text: text) }
        catch { lastError = "\(error)" }
    }

    // MARK: - Inbound

    private func handle(_ push: Response) async {
        switch push {
        case .pushMessagesWaiting:
            await drainMessages()
        case .pushNewAdvert(let contact):
            upsert(contact)
        case .pushAdvert, .pushPathUpdated:
            await refreshContacts()
        default:
            break
        }
    }

    private func drainMessages() async {
        guard let client else { return }
        while let m = try? await client.nextMessage() {
            var logged = LoggedMessage(received: .now, message: m)
            if case .contact(let prefix) = m.source {
                logged.senderName = contacts.first { $0.publicKey.starts(with: prefix) }?.name
            }
            messages.append(logged)
        }
    }

    private func upsert(_ contact: Contact) {
        if let i = contacts.firstIndex(where: { $0.publicKey == contact.publicKey }) {
            contacts[i] = contact
        } else {
            contacts.append(contact)
        }
    }
}
