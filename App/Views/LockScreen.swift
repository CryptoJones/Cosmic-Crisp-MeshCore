import SwiftUI

/// Full-screen gate: device authentication (Face ID / passcode) and, if the connected
/// radio's profile has its own passcode, that too.
struct LockScreen: View {
    @Environment(NodeSession.self) private var node
    @Environment(AppLock.self) private var lock
    @State private var passcode = ""
    @State private var wrong = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("Cosmic Crisp is locked").font(.title2.bold())
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Unlock with \(lock.biometryLabel)", systemImage: "faceid").font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    if !lock.deviceAuthAvailable {
                        Text("No device passcode set — app lock can't work on this iPad.").font(.caption).foregroundStyle(.red)
                        Button("Continue anyway") { lock.unlockWithoutAuth() }
                    }
                    if let e = lock.lastError { Text(e).font(.caption).foregroundStyle(.secondary) }
                } else if node.profileLocked {
                    Text("This radio (\(node.selfInfo?.name ?? "node")) has its own passcode.").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("Profile passcode", text: $passcode)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .onSubmit(tryProfile)
                    Button("Unlock", action: tryProfile).buttonStyle(.borderedProminent).disabled(passcode.isEmpty)
                    if wrong { Text("Wrong passcode").font(.caption).foregroundStyle(.red) }
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        .task { if lock.isLocked, lock.deviceAuthAvailable { await lock.unlock() } }
    }

    private func tryProfile() {
        wrong = !node.unlockProfile(passcode: passcode)
        passcode = ""
    }
}
