import SwiftUI

struct DiagnosticsView: View {
    let publicKeyHex: String
    var body: some View { ContentUnavailableView("Diagnostics", systemImage: "waveform.path.ecg", description: Text("Coming in #10")) }
}
