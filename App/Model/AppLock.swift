import Foundation
import Observation
import LocalAuthentication
import CryptoKit
import Security

/// App lock: biometrics / device passcode on launch and after a background timeout,
/// plus optional per-profile passcodes (hashed, stored in the keychain).
@MainActor
@Observable
final class AppLock {
    enum Mode: String, CaseIterable, Identifiable {
        case off, onLaunch, everyForeground
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .onLaunch: "On launch"
            case .everyForeground: "Every time the app opens"
            }
        }
    }

    private(set) var isLocked = false
    private(set) var lastError: String?
    var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "applock.mode") ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "applock.mode"); if newValue == .off { isLocked = false } }
    }
    /// Seconds in background before a re-lock is required (foreground mode).
    var graceSeconds: Int {
        get { let v = UserDefaults.standard.integer(forKey: "applock.grace"); return v == 0 ? 60 : v }
        set { UserDefaults.standard.set(newValue, forKey: "applock.grace") }
    }
    private var backgroundedAt: Date?

    var biometryLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "device passcode"
        }
    }

    var deviceAuthAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func lockOnLaunch() { if mode != .off { isLocked = true } }

    func didEnterBackground() { backgroundedAt = .now }

    func willEnterForeground() {
        guard mode == .everyForeground, let t = backgroundedAt else { return }
        if Date().timeIntervalSince(t) >= Double(graceSeconds) { isLocked = true }
    }

    /// Prompt Face ID / Touch ID / passcode. Returns true on success.
    @discardableResult
    func unlock(reason: String = "Unlock Cosmic Crisp") async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { isLocked = false; lastError = nil }
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// For the simulator/tests where no biometry exists.
    func unlockWithoutAuth() { isLocked = false }

    // MARK: - Per-profile passcodes (keychain, salted SHA-256)

    private static let service = "net.thenetwerk.cosmiccrisp.profile-passcode"

    func hasProfilePasscode(_ nodeKeyHex: String) -> Bool { keychainRead(nodeKeyHex) != nil }

    func setProfilePasscode(_ nodeKeyHex: String, passcode: String?) {
        guard let passcode, !passcode.isEmpty else { keychainDelete(nodeKeyHex); return }
        let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let hash = Self.hash(passcode, salt: salt)
        keychainWrite(nodeKeyHex, Data(salt + hash))
    }

    func verifyProfilePasscode(_ nodeKeyHex: String, passcode: String) -> Bool {
        guard let stored = keychainRead(nodeKeyHex), stored.count == 48 else { return true }
        let salt = Array(stored.prefix(16)), hash = Array(stored.suffix(32))
        return Self.hash(passcode, salt: salt) == hash
    }

    static func hash(_ passcode: String, salt: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(salt + Array(passcode.utf8))))
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
    }
    // Keychain first; if it is unavailable (unsigned test hosts), a complete-protection file
    // holds the same salted hashes.
    private static var fallbackURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CosmicCrisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile-passcodes.json")
    }
    private func fallbackLoad() -> [String: Data] {
        (try? JSONDecoder().decode([String: Data].self, from: Data(contentsOf: Self.fallbackURL))) ?? [:]
    }
    private func fallbackSave(_ d: [String: Data]) {
        if let data = try? JSONEncoder().encode(d) { try? data.write(to: Self.fallbackURL, options: [.atomic, .completeFileProtection]) }
    }
    private func keychainRead(_ account: String) -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
        return fallbackLoad()[account]
    }
    private func keychainWrite(_ account: String, _ data: Data) {
        keychainDelete(account)
        var q = query(account); q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if SecItemAdd(q as CFDictionary, nil) != errSecSuccess {
            var d = fallbackLoad(); d[account] = data; fallbackSave(d)
        }
    }
    private func keychainDelete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var d = fallbackLoad(); if d.removeValue(forKey: account) != nil { fallbackSave(d) }
    }
}
