import SwiftUI

struct ContentView: View {
    @State private var status = "Ready"
    @State private var showingTimerSettings = false

    var body: some View {
//        VStack(spacing: 20) {
//            Text(status)
//                .font(.system(.headline))
//                .padding()
//
//            Text("Sleep Monitor")
//                .font(.system(.subheadline))
//
//            Button("Configure Timer") {
//                showingTimerSettings = true
//            }
//            .padding()
//            .background(Color.blue)
//            .foregroundColor(.white)
//            .cornerRadius(10)
//        }
//        .onAppear {
//            setupStatusObserver()
//            StimulationTimerManager.shared.loadSettings()
//        }
//        .sheet(isPresented: $showingTimerSettings) {
//            SettingsViewControllerWrapper()
//        }
    }

    private func setupStatusObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StatusUpdate"),
            object: nil,
            queue: .main
        ) { notification in
            if let status = notification.userInfo?["status"] as? String {
                self.status = status
            }
        }
    }
}

struct SettingsViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SettingsViewController {
        return SettingsViewController()
    }

    func updateUIViewController(_ uiViewController: SettingsViewController, context: Context) {
        // No-op
    }
}
